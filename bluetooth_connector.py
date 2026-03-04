"""
Bluetooth connectivity module for TGAM1 EEG sensor
Handles connection, data acquisition, and parsing of RAW EEG data
Supports auto-detection of TGAM1 device by probing serial ports.
"""

import serial
import serial.tools.list_ports
import time
import struct
import logging
from typing import Optional, Dict, Callable, List, Tuple
from config import BLUETOOTH_BAUD_RATE, BLUETOOTH_TIMEOUT, BLUETOOTH_RETRY_ATTEMPTS

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# TGAM1 sync byte pattern
TGAM1_SYNC = b'\xAA\xAA'
# Probe timeout when sniffing a port for the TGAM1 signature
PROBE_TIMEOUT = 2.0  # seconds


class TGAM1Connector:
    """
    Connector for TGAM1 EEG sensor via Bluetooth/Serial interface.
    Includes smart auto-detection that probes each port for the TGAM1
    sync-byte signature (0xAA 0xAA) before committing to a connection.
    """

    def __init__(self, port: Optional[str] = None):
        self.port = port
        self.serial_conn: Optional[serial.Serial] = None
        self.is_connected = False
        self.data_callback: Optional[Callable] = None

    # ------------------------------------------------------------------
    # Port discovery helpers
    # ------------------------------------------------------------------

    def find_available_ports(self) -> List[str]:
        """Return a list of all available serial port device paths."""
        ports = serial.tools.list_ports.comports()
        return [p.device for p in ports]

    def find_available_ports_info(self) -> List[Dict]:
        """
        Return detailed info for every available serial port.
        Each dict contains: device, description, hwid, vid, pid.
        """
        result = []
        for p in serial.tools.list_ports.comports():
            result.append({
                'device': p.device,
                'description': p.description or '',
                'hwid': p.hwid or '',
                'vid': getattr(p, 'vid', None),
                'pid': getattr(p, 'pid', None),
            })
        return result

    def _probe_port_for_tgam1(self, device: str) -> bool:
        """
        Open *device* briefly and check whether it emits the TGAM1
        sync-byte pattern (0xAA 0xAA).  Returns True if detected.
        """
        try:
            probe = serial.Serial(
                port=device,
                baudrate=BLUETOOTH_BAUD_RATE,
                timeout=0.3,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
            )
            deadline = time.time() + PROBE_TIMEOUT
            buffer = b''
            while time.time() < deadline:
                chunk = probe.read(64)
                if chunk:
                    buffer += chunk
                    if TGAM1_SYNC in buffer:
                        probe.close()
                        logger.info(f"TGAM1 signature detected on {device}")
                        return True
                else:
                    time.sleep(0.05)
            probe.close()
        except Exception as e:
            logger.debug(f"Probe failed on {device}: {e}")
        return False

    def detect_tgam1_port(self, progress_callback: Optional[Callable[[str], None]] = None) -> Optional[str]:
        """
        Scan all available serial ports and return the first one that
        looks like a TGAM1 device (emits 0xAA 0xAA sync bytes).

        Args:
            progress_callback: Optional callable(message) called while scanning.
        Returns:
            Device path string, or None if not found.
        """
        ports = self.find_available_ports_info()
        if not ports:
            logger.warning("No serial ports found during auto-detection scan.")
            return None

        logger.info(f"Auto-detection: scanning {len(ports)} port(s) …")

        # Priority heuristic: prefer ports whose description hints at
        # Bluetooth / TGAM / NeuroSky / CP210x / CH340 chipsets.
        PRIORITY_KEYWORDS = ['bluetooth', 'tgam', 'neurosky', 'cp210', 'ch340',
                             'ftdi', 'serial', 'usb']

        def _priority(p: Dict) -> int:
            desc = (p['description'] + p['hwid']).lower()
            for i, kw in enumerate(PRIORITY_KEYWORDS):
                if kw in desc:
                    return i
            return len(PRIORITY_KEYWORDS)

        sorted_ports = sorted(ports, key=_priority)

        for info in sorted_ports:
            device = info['device']
            msg = f"Probing {device} ({info['description']}) …"
            logger.info(msg)
            if progress_callback:
                progress_callback(msg)
            if self._probe_port_for_tgam1(device):
                if progress_callback:
                    progress_callback(f"✓ TGAM1 found on {device}")
                return device

        logger.warning("Auto-detection: TGAM1 not found on any port.")
        return None

    # ------------------------------------------------------------------
    # Connection management
    # ------------------------------------------------------------------

    def connect(self, port: Optional[str] = None,
                progress_callback: Optional[Callable[[str], None]] = None) -> bool:
        """
        Connect to TGAM1 device.

        Args:
            port: Serial port name.  Pass None to trigger auto-detection.
            progress_callback: Optional callable(message) for status updates.
        Returns:
            True if connection successful, False otherwise.
        """
        if port:
            self.port = port

        if not self.port:
            # --- Smart auto-detection ---
            if progress_callback:
                progress_callback("Scanning for TGAM1 device …")
            detected = self.detect_tgam1_port(progress_callback=progress_callback)
            if detected:
                self.port = detected
            else:
                # Fall back: use first available port
                all_ports = self.find_available_ports()
                if not all_ports:
                    logger.error("No serial ports found")
                    return False
                self.port = all_ports[0]
                logger.info(f"Fallback – using first available port: {self.port}")

        logger.info(f"Connecting to {self.port} …")
        for attempt in range(BLUETOOTH_RETRY_ATTEMPTS):
            try:
                self.serial_conn = serial.Serial(
                    port=self.port,
                    baudrate=BLUETOOTH_BAUD_RATE,
                    timeout=BLUETOOTH_TIMEOUT,
                    bytesize=serial.EIGHTBITS,
                    parity=serial.PARITY_NONE,
                    stopbits=serial.STOPBITS_ONE,
                )
                time.sleep(2)  # Wait for connection to stabilize
                self.is_connected = True
                logger.info(f"Connected to TGAM1 on {self.port}")
                return True
            except Exception as e:
                logger.warning(f"Connection attempt {attempt + 1} failed: {e}")
                if attempt < BLUETOOTH_RETRY_ATTEMPTS - 1:
                    time.sleep(1)

        logger.error("Failed to connect to TGAM1 device")
        return False
    
    def disconnect(self):
        """Disconnect from TGAM1 device"""
        if self.serial_conn and self.serial_conn.is_open:
            self.serial_conn.close()
            self.is_connected = False
            logger.info("Disconnected from TGAM1")
    
    def parse_packet(self, packet: bytes) -> Optional[Dict]:
        """
        Parse TGAM1 data packet
        TGAM1 protocol: [SYNC, SYNC, PLENGTH, PAYLOAD..., CHKSUM]
        """
        if len(packet) < 4:
            return None
        
        # Check for sync bytes (0xAA, 0xAA)
        if packet[0] != 0xAA or packet[1] != 0xAA:
            return None
        
        payload_length = packet[2]
        if len(packet) < 3 + payload_length + 1:
            return None
        
        payload = packet[3:3 + payload_length]
        checksum = packet[3 + payload_length]
        
        # Verify checksum
        calculated_checksum = (~sum(packet[2:3 + payload_length])) & 0xFF
        if checksum != calculated_checksum:
            return None
        
        data = {}
        i = 0
        while i < len(payload):
            code = payload[i]
            i += 1
            
            if code == 0x02:  # Poor signal quality
                if i < len(payload):
                    data['poor_signal'] = payload[i]
                    i += 1
            elif code == 0x04:  # Attention
                if i < len(payload):
                    data['attention'] = payload[i]
                    i += 1
            elif code == 0x05:  # Meditation
                if i < len(payload):
                    data['meditation'] = payload[i]
                    i += 1
            elif code == 0x80:  # Raw EEG value (2 bytes, big-endian)
                if i + 1 < len(payload):
                    raw_value = struct.unpack('>h', payload[i:i+2])[0]
                    data['raw_eeg'] = raw_value
                    i += 2
            elif code == 0x83:  # ASIC EEG power values
                if i + 24 < len(payload):
                    # 8 frequency bands, 3 bytes each
                    bands = []
                    for j in range(8):
                        band_value = struct.unpack('>I', b'\x00' + payload[i:i+3])[0]
                        bands.append(band_value)
                        i += 3
                    data['eeg_power'] = {
                        'delta': bands[0],
                        'theta': bands[1],
                        'low_alpha': bands[2],
                        'high_alpha': bands[3],
                        'low_beta': bands[4],
                        'high_beta': bands[5],
                        'low_gamma': bands[6],
                        'high_gamma': bands[7]
                    }
        
        return data if data else None
    
    def read_data(self) -> Optional[Dict]:
        """
        Read and parse data from TGAM1
        Returns:
            Dictionary containing EEG data or None if no valid data
        """
        if not self.is_connected or not self.serial_conn:
            return None
        
        try:
            if self.serial_conn.in_waiting > 0:
                data = self.serial_conn.read(self.serial_conn.in_waiting)
                parsed = self.parse_packet(data)
                if parsed and self.data_callback:
                    self.data_callback(parsed)
                return parsed
        except Exception as e:
            logger.error(f"Error reading data: {e}")
            return None
        
        return None
    
    def set_data_callback(self, callback: Callable):
        """Set callback function for received data"""
        self.data_callback = callback
    
    def __enter__(self):
        """Context manager entry"""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        self.disconnect()
