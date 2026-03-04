"""
Universal EEG Device Auto-Connector
Detects and connects to any supported neuro/EEG sensor automatically:
  - TGAM1 / NeuroSky MindWave / MindLink  (Bluetooth serial, 0xAA sync)
  - ESP32 multi-sensor hub                 (USB-serial, JSON stream)
  - Generic EEG / Brainwave / Nerve / Neuro USB devices (keyword match)

Usage:
    from auto_connector import UniversalAutoConnector
    uc = UniversalAutoConnector()
    device = uc.scan(progress_callback=print)
    if device:
        device.connector.set_data_callback(my_callback)
        # already connected — device.connector.is_connected == True
"""

from __future__ import annotations

import json
import logging
import time
from dataclasses import dataclass, field
from typing import Callable, List, Optional

import serial
import serial.tools.list_ports

logger = logging.getLogger(__name__)

# ──────────────────────────────────────────────────────────────────────────────
# Protocol constants
# ──────────────────────────────────────────────────────────────────────────────
TGAM1_SYNC       = b'\xAA\xAA'         # NeuroSky TGAM1 / MindWave / MindLink
TGAM1_BAUD       = 57600
ESP32_BAUD       = 115200
PROBE_TIMEOUT    = 2.5                  # seconds per port probe
RETRY_INTERVAL   = 10.0                 # seconds between full-scan retries

# Keywords used to prioritise / fingerprint ports when probing
PRIORITY_KEYWORDS = [
    'neurosky', 'tgam', 'mindwave', 'mindlink',          # known EEG devices
    'nerve', 'neuro', 'brainwave', 'eeg', 'biosensor',   # generic EEG terms
    'cp210', 'ch340', 'ch341', 'ftdi', 'silabs',         # common USB-serial chips
    'bluetooth', 'rfcomm', 'spp',                        # Bluetooth serial profiles
    'usb', 'serial',                                     # fallback
]

# Device-type constants
TYPE_TGAM1   = 'tgam1'      # TGAM1 / MindWave / MindLink
TYPE_ESP32   = 'esp32'      # ESP32 JSON hub
TYPE_GENERIC = 'generic'    # Keyword-matched, unknown protocol


# ──────────────────────────────────────────────────────────────────────────────
# Result data class
# ──────────────────────────────────────────────────────────────────────────────
@dataclass
class DetectedDevice:
    """
    Holds information about a successfully detected EEG device.
    `connector` is already connected (is_connected == True).
    """
    port: str
    device_type: str           # TYPE_TGAM1 | TYPE_ESP32 | TYPE_GENERIC
    description: str           # port description from OS
    connector: object          # TGAM1Connector | ESP32Connector (already connected)
    extra: dict = field(default_factory=dict)

    def __str__(self) -> str:
        return (f"DetectedDevice(type={self.device_type!r}, "
                f"port={self.port!r}, desc={self.description!r})")


# ──────────────────────────────────────────────────────────────────────────────
# Universal connector
# ──────────────────────────────────────────────────────────────────────────────
class UniversalAutoConnector:
    """
    Scans all available serial/Bluetooth ports and returns the first
    recognised EEG / neuro device as a DetectedDevice (already connected).

    Supported devices
    -----------------
    - TGAM1 / NeuroSky MindWave / MindLink   — detected via 0xAA 0xAA sync bytes
    - ESP32 multi-sensor hub                 — detected via JSON text stream
    - Generic EEG / nerve / brainwave sensor — detected via port-description keywords

    Parameters
    ----------
    retry_interval : float
        Seconds to wait between full-scan retries (used by consumers, not scan()).
    probe_timeout  : float
        Max seconds to listen on each port during probing.
    """

    def __init__(
        self,
        retry_interval: float = RETRY_INTERVAL,
        probe_timeout: float = PROBE_TIMEOUT,
    ):
        self.retry_interval = retry_interval
        self.probe_timeout = probe_timeout

    # ── Public API ─────────────────────────────────────────────────────────

    def find_all_ports(self) -> List[dict]:
        """
        Return a list of dicts for every available serial port.
        Each dict: {device, description, hwid, vid, pid, priority}
        """
        result = []
        for p in serial.tools.list_ports.comports():
            desc = (p.description or '').lower()
            hwid = (p.hwid or '').lower()
            combined = desc + ' ' + hwid

            priority = len(PRIORITY_KEYWORDS)   # lower = higher priority
            for i, kw in enumerate(PRIORITY_KEYWORDS):
                if kw in combined:
                    priority = i
                    break

            result.append({
                'device':      p.device,
                'description': p.description or '',
                'hwid':        p.hwid or '',
                'vid':         getattr(p, 'vid', None),
                'pid':         getattr(p, 'pid', None),
                'priority':    priority,
            })

        # Sort highest-priority first
        result.sort(key=lambda x: x['priority'])
        return result

    def scan(
        self,
        progress_callback: Optional[Callable[[str], None]] = None,
    ) -> Optional[DetectedDevice]:
        """
        Probe all available ports and return the first detected EEG device.

        Detection order for each port (tried in sequence):
          1. TGAM1 / MindWave / MindLink  (0xAA 0xAA at 57600 baud)
          2. ESP32 JSON hub               (JSON line at 115200 baud)
          3. Keyword match                (no protocol probe)

        Parameters
        ----------
        progress_callback : callable(str), optional
            Called with human-readable progress messages during scanning.

        Returns
        -------
        DetectedDevice or None
        """
        ports = self.find_all_ports()
        if not ports:
            self._emit(progress_callback, "No serial ports found on this machine.")
            return None

        self._emit(progress_callback,
                   f"Found {len(ports)} port(s) — scanning for EEG device…")

        for info in ports:
            device = info['device']
            desc   = info['description']
            self._emit(progress_callback, f"Probing {device}  ({desc})")

            # ── 1. TGAM1 / MindWave / MindLink probe ───────────────────
            detected = self._probe_tgam1(device, progress_callback)
            if detected:
                return detected

            # ── 2. ESP32 JSON probe ────────────────────────────────────
            detected = self._probe_esp32(device, progress_callback)
            if detected:
                return detected

            # ── 3. Keyword / description match (generic fallback) ───────
            detected = self._probe_generic_keyword(info, progress_callback)
            if detected:
                return detected

        self._emit(progress_callback,
                   "No EEG device recognised on any port.  "
                   f"Will retry in {int(self.retry_interval)}s …")
        return None

    # ── Protocol probes ────────────────────────────────────────────────────

    def _probe_tgam1(
        self,
        device: str,
        cb: Optional[Callable],
    ) -> Optional[DetectedDevice]:
        """
        Try to open *device* at TGAM1_BAUD and listen for 0xAA 0xAA sync bytes.
        Returns a connected DetectedDevice on success, None otherwise.
        """
        try:
            ser = serial.Serial(
                port=device, baudrate=TGAM1_BAUD, timeout=0.3,
                bytesize=serial.EIGHTBITS, parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
            )
        except Exception as e:
            logger.debug(f"TGAM1 open failed on {device}: {e}")
            return None

        try:
            deadline = time.time() + self.probe_timeout
            buf = b''
            while time.time() < deadline:
                chunk = ser.read(64)
                if chunk:
                    buf += chunk
                    if TGAM1_SYNC in buf:
                        self._emit(cb, f"  ✓ TGAM1/MindLink sync detected on {device}")
                        ser.close()
                        return self._make_tgam1_device(device, ser.port)
                else:
                    time.sleep(0.04)
        except Exception as e:
            logger.debug(f"TGAM1 probe read error on {device}: {e}")
        finally:
            try:
                ser.close()
            except Exception:
                pass
        return None

    def _probe_esp32(
        self,
        device: str,
        cb: Optional[Callable],
    ) -> Optional[DetectedDevice]:
        """
        Try to open *device* at ESP32_BAUD and check for a JSON line.
        Returns a connected DetectedDevice on success, None otherwise.
        """
        try:
            ser = serial.Serial(
                port=device, baudrate=ESP32_BAUD, timeout=0.3,
                bytesize=serial.EIGHTBITS, parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
            )
        except Exception as e:
            logger.debug(f"ESP32 open failed on {device}: {e}")
            return None

        try:
            # Send INIT to prompt the ESP32 to respond
            ser.write(b'INIT\n')
            time.sleep(0.3)

            deadline = time.time() + self.probe_timeout
            line_buf = b''
            while time.time() < deadline:
                chunk = ser.read(128)
                if chunk:
                    line_buf += chunk
                    # Check for a complete JSON-like line
                    if b'\n' in line_buf:
                        for raw_line in line_buf.split(b'\n'):
                            text = raw_line.strip().decode('utf-8', errors='ignore')
                            if text.startswith('{'):
                                try:
                                    json.loads(text)
                                    self._emit(cb,
                                               f"  ✓ ESP32 JSON stream detected on {device}")
                                    ser.close()
                                    return self._make_esp32_device(device, text)
                                except json.JSONDecodeError:
                                    pass
                else:
                    time.sleep(0.04)
        except Exception as e:
            logger.debug(f"ESP32 probe read error on {device}: {e}")
        finally:
            try:
                ser.close()
            except Exception:
                pass
        return None

    def _probe_generic_keyword(
        self,
        info: dict,
        cb: Optional[Callable],
    ) -> Optional[DetectedDevice]:
        """
        Fallback: if the port description contains known EEG/neuro keywords,
        treat it as a TGAM1-compatible device (most EEG serial devices are).
        """
        MATCH_KEYWORDS = [
            'neurosky', 'tgam', 'mindwave', 'mindlink',
            'nerve', 'neuro', 'brainwave', 'eeg', 'biosensor',
        ]
        desc_lower = (info['description'] + ' ' + info['hwid']).lower()
        matched_kw = next((kw for kw in MATCH_KEYWORDS if kw in desc_lower), None)

        if matched_kw:
            device = info['device']
            self._emit(cb, f"  ✓ Keyword '{matched_kw}' matched on {device} — "
                           f"assuming TGAM1-compatible")
            return self._make_tgam1_device(device, info['description'])
        return None

    # ── Device construction helpers ────────────────────────────────────────

    def _make_tgam1_device(self, port: str, description: str) -> Optional[DetectedDevice]:
        """Connect via TGAM1Connector and return DetectedDevice."""
        try:
            from bluetooth_connector import TGAM1Connector
            conn = TGAM1Connector(port=port)
            ok = conn.connect(port=port)
            if not ok:
                return None
            return DetectedDevice(
                port=port,
                device_type=TYPE_TGAM1,
                description=str(description),
                connector=conn,
            )
        except Exception as e:
            logger.error(f"TGAM1Connector.connect failed on {port}: {e}")
            return None

    def _make_esp32_device(self, port: str, sample_json: str) -> Optional[DetectedDevice]:
        """Connect via ESP32Connector and return DetectedDevice."""
        try:
            from esp32_connector import ESP32Connector
            conn = ESP32Connector(port=port, baud_rate=ESP32_BAUD)
            ok = conn.connect(port=port)
            if not ok:
                return None
            return DetectedDevice(
                port=port,
                device_type=TYPE_ESP32,
                description='ESP32 multi-sensor hub',
                connector=conn,
                extra={'sample_json': sample_json},
            )
        except Exception as e:
            logger.error(f"ESP32Connector.connect failed on {port}: {e}")
            return None

    # ── Utility ────────────────────────────────────────────────────────────

    @staticmethod
    def _emit(cb: Optional[Callable], msg: str):
        logger.info(msg)
        if cb:
            cb(msg)


# ──────────────────────────────────────────────────────────────────────────────
# Quick self-test (no hardware required)
# ──────────────────────────────────────────────────────────────────────────────
if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO,
                        format='%(levelname)s  %(message)s')

    print("UniversalAutoConnector — port scan test")
    print("=" * 50)

    uc = UniversalAutoConnector()
    ports = uc.find_all_ports()

    print(f"Detected {len(ports)} serial port(s):\n")
    for p in ports:
        print(f"  [{p['priority']:2d}]  {p['device']:<20}  {p['description']}")

    print("\nReturn type assertion …", end=" ")
    assert isinstance(ports, list), "find_all_ports() must return a list"
    print("OK")

    print("\nTo attempt a live scan, run:")
    print("  from auto_connector import UniversalAutoConnector")
    print("  d = UniversalAutoConnector().scan(progress_callback=print)")
    print("  print(d)")
