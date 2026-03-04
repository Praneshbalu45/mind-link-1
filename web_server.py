"""
Web Server for MindLink EEG System — iPad / Browser Dashboard
Runs on the Mac, streams real-time EEG data to any browser on the local network.

Usage:
    python3 web_server.py            # real device (auto-detects sensor)
    python3 web_server.py --demo     # simulated data, no hardware needed
    python3 web_server.py --port 8080

Open in iPad Safari:  http://<mac-local-ip>:5000
"""

import argparse
import logging
import math
import random
import socket
import sys
import threading
import time
from collections import deque
from typing import Optional

from flask import Flask, jsonify, send_from_directory
from flask_socketio import SocketIO, emit

# ── Project modules ────────────────────────────────────────────────────────
from auto_connector import UniversalAutoConnector
from signal_processor import SignalProcessor
from feature_extractor import FeatureExtractor
from ml_model import FatigueDetector
from alert_system import AlertSystem
from config import BASELINE_DURATION

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s  %(message)s'
)
logger = logging.getLogger(__name__)

# ── Flask / SocketIO setup ─────────────────────────────────────────────────
app = Flask(__name__, static_folder='static')
app.config['SECRET_KEY'] = 'mindlink-eeg-2024'
socketio = SocketIO(app, cors_allowed_origins='*', async_mode='threading')


# ══════════════════════════════════════════════════════════════════════════════
# EEG Engine — holds the pipeline, independent of UI
# ══════════════════════════════════════════════════════════════════════════════
class EEGEngine:
    def __init__(self, demo_mode: bool = False):
        self.demo_mode = demo_mode
        self.connector = None
        self.signal_processor = SignalProcessor()
        self.feature_extractor = FeatureExtractor()
        self.ml_model = FatigueDetector()
        self.alert_system = AlertSystem()

        self.is_running = False
        self.is_connected = False
        self.device_label = 'Not connected'
        self.device_port = ''

        self._acq_thread: Optional[threading.Thread] = None
        self._auto_conn = UniversalAutoConnector()

        # Latest processed data (thread-safe snapshot)
        self._latest: dict = {}
        self._latest_lock = threading.Lock()

        self.alert_system.set_alert_callback(self._on_alert)

    # ── Connection ─────────────────────────────────────────────────────────

    def connect(self, port: Optional[str] = None,
                progress_cb=None) -> bool:
        if self.demo_mode:
            logger.info("Demo mode: skipping hardware connect")
            self.is_connected = True
            self.device_label = 'Demo (simulated)'
            self.device_port = 'demo'
            return True

        def on_progress(msg):
            logger.info(msg)
            if progress_cb:
                progress_cb(msg)

        if port:
            # single-port manual connect
            device = self._auto_conn._probe_tgam1(port, on_progress) \
                  or self._auto_conn._probe_esp32(port, on_progress)
            if device is None:
                from bluetooth_connector import TGAM1Connector
                c = TGAM1Connector(port=port)
                if c.connect(port=port, progress_callback=on_progress):
                    from auto_connector import DetectedDevice, TYPE_TGAM1
                    device = DetectedDevice(port=port, device_type=TYPE_TGAM1,
                                            description='manual', connector=c)
        else:
            device = self._auto_conn.scan(progress_callback=on_progress)

        if not device:
            logger.warning("No EEG device found")
            return False

        self.connector = device.connector
        self.connector.set_data_callback(self._on_raw_data)
        self.device_label = {
            'tgam1': 'TGAM1 / MindLink',
            'esp32': 'ESP32 hub',
            'generic': 'EEG Sensor',
        }.get(device.device_type, device.device_type.upper())
        self.device_port = device.port
        self.is_connected = True
        logger.info(f"Connected: {self.device_label} on {self.device_port}")
        return True

    def disconnect(self):
        self.stop()
        if self.connector:
            self.connector.disconnect()
        self.is_connected = False
        self.device_label = 'Not connected'
        self.device_port = ''

    # ── Monitoring ─────────────────────────────────────────────────────────

    def start(self):
        if self.is_running:
            return
        if not self.is_connected:
            logger.warning("Cannot start: not connected")
            return
        self.signal_processor.reset()
        self.feature_extractor.reset()
        self.alert_system.reset()
        self.is_running = True
        self._acq_thread = threading.Thread(
            target=self._acquisition_loop, daemon=True
        )
        self._acq_thread.start()
        logger.info("Monitoring started")

    def stop(self):
        if not self.is_running:
            return
        self.is_running = False
        if self._acq_thread:
            self._acq_thread.join(timeout=2)
        logger.info("Monitoring stopped")

    # ── Data loops ─────────────────────────────────────────────────────────

    def _acquisition_loop(self):
        baseline_start = time.time()
        baseline_done = False

        while self.is_running:
            try:
                if self.demo_mode:
                    data = self._simulate_data()
                    time.sleep(0.1)
                else:
                    data = self.connector.read_data()
                    if data is None:
                        time.sleep(0.1)
                        continue

                attention  = data.get('attention')
                meditation = data.get('meditation')
                raw_eeg    = data.get('raw_eeg')
                eeg_power  = data.get('eeg_power')

                if eeg_power:
                    freq_bands = self.signal_processor.process_tgam_power_data(eeg_power)
                elif raw_eeg is not None:
                    freq_bands = self.signal_processor.process_raw_eeg(raw_eeg)
                else:
                    freq_bands = {}

                band_ratios = self.signal_processor.calculate_band_ratios(freq_bands)
                self.feature_extractor.add_sample(
                    attention, meditation, freq_bands, band_ratios
                )

                if not baseline_done:
                    elapsed = time.time() - baseline_start
                    if elapsed >= BASELINE_DURATION and self.feature_extractor.baseline_established:
                        baseline_done = True
                        logger.info("Baseline established")
                    self._push_snapshot(attention, meditation, freq_bands, {}, 'calibrating')
                    continue

                features    = self.feature_extractor.extract_features()
                predictions = self.ml_model.predict(features)
                self.alert_system.check_alerts(features, predictions)

                self._push_snapshot(attention, meditation, freq_bands, predictions, 'monitoring')
                time.sleep(0.05)

            except Exception as e:
                logger.error(f"Acquisition error: {e}")
                time.sleep(0.5)

    def _push_snapshot(self, attention, meditation, freq_bands, predictions, phase):
        snapshot = {
            'attention':     round(attention or 0, 1),
            'meditation':    round(meditation or 0, 1),
            'fatigue_score': round(predictions.get('fatigue_score', 0.0), 3),
            'fatigue_level': predictions.get('fatigue_level', 'low'),
            'cognitive_drift': round(predictions.get('cognitive_drift', 0.0), 3),
            'freq_bands':    {k: round(v, 4) for k, v in freq_bands.items()},
            'phase':         phase,
            'timestamp':     time.time(),
        }
        with self._latest_lock:
            self._latest = snapshot
        socketio.emit('eeg_data', snapshot)

    def _on_raw_data(self, data):
        pass  # handled in loop

    def _on_alert(self, alert: dict):
        socketio.emit('alert', {
            'level':   alert['level'],
            'message': alert['message'],
            'ts':      time.time(),
        })
        logger.info(f"Alert [{alert['level']}]: {alert['message']}")

    # ── Demo simulator ─────────────────────────────────────────────────────

    _demo_t = 0.0

    def _simulate_data(self) -> dict:
        t = self._demo_t
        self._demo_t += 0.1
        attention  = 50 + 30 * math.sin(t / 8) + random.gauss(0, 5)
        meditation = 40 + 25 * math.cos(t / 10) + random.gauss(0, 4)
        raw_eeg    = int(1000 * math.sin(t * 50) + random.gauss(0, 200))
        return {
            'attention':  max(0, min(100, attention)),
            'meditation': max(0, min(100, meditation)),
            'raw_eeg':    raw_eeg,
        }

    # ── Getters ────────────────────────────────────────────────────────────

    def get_status(self) -> dict:
        with self._latest_lock:
            latest = dict(self._latest)
        return {
            'connected':    self.is_connected,
            'running':      self.is_running,
            'device':       self.device_label,
            'port':         self.device_port,
            'demo':         self.demo_mode,
            'latest':       latest,
        }


# ── Global engine instance ─────────────────────────────────────────────────
engine: EEGEngine = None  # initialised in main()


# ══════════════════════════════════════════════════════════════════════════════
# REST API
# ══════════════════════════════════════════════════════════════════════════════

@app.route('/')
def index():
    return send_from_directory('static', 'index.html')

@app.route('/api/status')
def api_status():
    return jsonify(engine.get_status())

@app.route('/api/connect', methods=['POST'])
def api_connect():
    if engine.is_connected:
        return jsonify({'ok': True, 'msg': 'Already connected'})

    def progress(msg):
        socketio.emit('scan_log', {'msg': msg})

    ok = engine.connect(progress_cb=progress)
    if ok:
        socketio.emit('connection_change', {
            'connected': True,
            'device': engine.device_label,
            'port': engine.device_port,
        })
        return jsonify({'ok': True, 'device': engine.device_label,
                        'port': engine.device_port})
    return jsonify({'ok': False, 'msg': 'Device not found'}), 404

@app.route('/api/start', methods=['POST'])
def api_start():
    if not engine.is_connected:
        # Try to connect first
        def progress(msg):
            socketio.emit('scan_log', {'msg': msg})
        ok = engine.connect(progress_cb=progress)
        if not ok:
            return jsonify({'ok': False, 'msg': 'Device not found'}), 404
        socketio.emit('connection_change', {
            'connected': True,
            'device': engine.device_label,
            'port': engine.device_port,
        })
    engine.start()
    socketio.emit('monitoring_change', {'running': True})
    return jsonify({'ok': True})

@app.route('/api/stop', methods=['POST'])
def api_stop():
    engine.stop()
    socketio.emit('monitoring_change', {'running': False})
    return jsonify({'ok': True})

@app.route('/api/disconnect', methods=['POST'])
def api_disconnect():
    engine.disconnect()
    socketio.emit('connection_change', {'connected': False, 'device': '', 'port': ''})
    socketio.emit('monitoring_change', {'running': False})
    return jsonify({'ok': True})

@app.route('/api/ports')
def api_ports():
    uc = UniversalAutoConnector()
    ports = uc.find_all_ports()
    return jsonify([{'device': p['device'], 'description': p['description']}
                    for p in ports])


# ══════════════════════════════════════════════════════════════════════════════
# SocketIO events
# ══════════════════════════════════════════════════════════════════════════════

@socketio.on('connect')
def on_connect():
    emit('status', engine.get_status())
    logger.info(f"Browser connected")

@socketio.on('disconnect')
def on_disconnect():
    logger.info(f"Browser disconnected")


# ══════════════════════════════════════════════════════════════════════════════
# Helpers
# ══════════════════════════════════════════════════════════════════════════════

def get_local_ip() -> str:
    """Return the Mac's LAN IP address."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return '127.0.0.1'


# ══════════════════════════════════════════════════════════════════════════════
# Entry point
# ══════════════════════════════════════════════════════════════════════════════

def main():
    global engine

    parser = argparse.ArgumentParser(description='MindLink Web Server')
    parser.add_argument('--demo',   action='store_true', help='Use simulated data (no hardware)')
    parser.add_argument('--port',   type=int, default=8080, help='HTTP port (default 8080)')
    parser.add_argument('--host',   default='0.0.0.0',      help='Bind host')
    parser.add_argument('--autostart', action='store_true',
                        help='Auto-connect and start monitoring on launch')
    args = parser.parse_args()

    engine = EEGEngine(demo_mode=args.demo)

    if args.autostart or args.demo:
        def _bg():
            time.sleep(1)
            def prog(m): socketio.emit('scan_log', {'msg': m})
            ok = engine.connect(progress_cb=prog)
            if ok:
                socketio.emit('connection_change', {
                    'connected': True,
                    'device': engine.device_label,
                    'port': engine.device_port,
                })
                engine.start()
                socketio.emit('monitoring_change', {'running': True})
        threading.Thread(target=_bg, daemon=True).start()

    ip = get_local_ip()
    print()
    print("=" * 55)
    print("  🧠  MindLink Web Server")
    print("=" * 55)
    print(f"  Local:   http://localhost:{args.port}")
    print(f"  iPad:    http://{ip}:{args.port}   ← open in Safari")
    if args.demo:
        print("  Mode:    DEMO (simulated data)")
    print("=" * 55)
    print()

    socketio.run(app, host=args.host, port=args.port, debug=False)


if __name__ == '__main__':
    main()
