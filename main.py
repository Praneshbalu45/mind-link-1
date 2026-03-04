"""
Main application for EEG-Based Mental Fatigue & Micro-Burnout Early Warning System
Features: Universal auto-detect (TGAM1 / MindLink / ESP32 / generic neuro),
          auto-connect, and auto-start monitoring.
"""

import tkinter as tk
from tkinter import messagebox, ttk
import threading
import time
import logging
from typing import Optional, Dict, List

from auto_connector import UniversalAutoConnector, TYPE_ESP32
from signal_processor import SignalProcessor
from feature_extractor import FeatureExtractor
from ml_model import FatigueDetector
from visualizer import EEGVisualizer
from alert_system import AlertSystem
from config import BASELINE_DURATION

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# How long to wait (seconds) before the first auto-connect attempt on launch
AUTO_CONNECT_DELAY = 1.0
# How often (seconds) to retry auto-connect when device is not yet found
AUTO_CONNECT_RETRY_INTERVAL = 10.0


class EEGFatigueSystem:
    """
    Main application orchestrator for EEG fatigue detection system.
    Supports universal auto-detect (TGAM1 / MindLink / ESP32 / generic neuro),
    auto-connect, and auto-start monitoring.
    """

    def __init__(self):
        # Universal auto-connector (handles all device types)
        self._auto_conn = UniversalAutoConnector(
            retry_interval=AUTO_CONNECT_RETRY_INTERVAL
        )

        # Active hardware connector (set after detection)
        self.connector = None

        self.signal_processor = SignalProcessor()
        self.feature_extractor = FeatureExtractor()
        self.ml_model = FatigueDetector()
        self.alert_system = AlertSystem()

        # State
        self.is_running = False
        self.data_thread: Optional[threading.Thread] = None
        self.visualizer: Optional[EEGVisualizer] = None
        self._auto_connect_active = False
        self._auto_connect_thread: Optional[threading.Thread] = None

        # Setup GUI
        self.root = tk.Tk()
        self._setup_gui()

        # Alert callback (connector callback set after detection)
        self.alert_system.set_alert_callback(self._on_alert)

    # ------------------------------------------------------------------
    # GUI setup
    # ------------------------------------------------------------------

    def _setup_gui(self):
        """Setup the main GUI with auto-connect controls and live port list."""
        self.root.title("MindLink – EEG Mental Fatigue Detection")
        self.root.geometry("480x560")
        self.root.resizable(False, False)
        self.root.configure(bg="#1a1a2e")

        # ── Title ──────────────────────────────────────────────────────
        title_frame = tk.Frame(self.root, bg="#1a1a2e")
        title_frame.pack(fill=tk.X, pady=(16, 4))
        tk.Label(
            title_frame, text="🧠  MindLink",
            font=("Arial", 20, "bold"), fg="#a78bfa", bg="#1a1a2e"
        ).pack()
        tk.Label(
            title_frame, text="EEG Mental Fatigue & Micro-Burnout Monitor",
            font=("Arial", 10), fg="#94a3b8", bg="#1a1a2e"
        ).pack()

        # ── Auto-Connect Card ──────────────────────────────────────────
        auto_card = tk.LabelFrame(
            self.root, text=" Auto-Connect ", font=("Arial", 10, "bold"),
            fg="#a78bfa", bg="#16213e", bd=1, relief=tk.GROOVE, padx=12, pady=10
        )
        auto_card.pack(fill=tk.X, padx=20, pady=8)

        # Status indicator
        status_row = tk.Frame(auto_card, bg="#16213e")
        status_row.pack(fill=tk.X, pady=(0, 4))

        self._dot_canvas = tk.Canvas(status_row, width=14, height=14, bg="#16213e",
                                     highlightthickness=0)
        self._dot_canvas.pack(side=tk.LEFT, padx=(0, 6))
        self._dot = self._dot_canvas.create_oval(2, 2, 12, 12, fill="#64748b", outline="")

        self.status_label = tk.Label(
            status_row, text="Ready – press Auto-Connect or enter port manually",
            font=("Arial", 9), fg="#94a3b8", bg="#16213e", anchor=tk.W
        )
        self.status_label.pack(side=tk.LEFT, fill=tk.X, expand=True)

        # Progress bar (marquee during scan)
        self.progress_bar = ttk.Progressbar(
            auto_card, mode='indeterminate', length=400
        )
        self.progress_bar.pack(fill=tk.X, pady=(0, 6))

        # Scan log (scrollable)
        log_frame = tk.Frame(auto_card, bg="#0f172a")
        log_frame.pack(fill=tk.X)
        self.scan_log = tk.Text(
            log_frame, height=5, state=tk.DISABLED, bg="#0f172a",
            fg="#67e8f9", font=("Courier", 8), bd=0, wrap=tk.WORD
        )
        scroll = tk.Scrollbar(log_frame, command=self.scan_log.yview)
        self.scan_log.configure(yscrollcommand=scroll.set)
        self.scan_log.pack(side=tk.LEFT, fill=tk.X, expand=True)
        scroll.pack(side=tk.RIGHT, fill=tk.Y)

        # ── Manual Port Entry  ─────────────────────────────────────────
        manual_card = tk.LabelFrame(
            self.root, text=" Manual Port ", font=("Arial", 10, "bold"),
            fg="#a78bfa", bg="#16213e", bd=1, relief=tk.GROOVE, padx=12, pady=8
        )
        manual_card.pack(fill=tk.X, padx=20, pady=4)

        port_row = tk.Frame(manual_card, bg="#16213e")
        port_row.pack(fill=tk.X)

        tk.Label(port_row, text="Port:", font=("Arial", 9), fg="#94a3b8",
                 bg="#16213e").pack(side=tk.LEFT)

        self.port_var = tk.StringVar()
        self.port_entry = ttk.Entry(port_row, textvariable=self.port_var, width=20)
        self.port_entry.pack(side=tk.LEFT, padx=8)

        # Available-ports dropdown
        self.ports_combo = ttk.Combobox(port_row, textvariable=self.port_var,
                                        width=22, state="readonly")
        self.ports_combo.pack(side=tk.LEFT, padx=4)
        self._refresh_ports_combo()

        ttk.Button(port_row, text="⟳", width=3,
                   command=self._refresh_ports_combo).pack(side=tk.LEFT)

        # ── Buttons ────────────────────────────────────────────────────
        btn_frame = tk.Frame(self.root, bg="#1a1a2e")
        btn_frame.pack(fill=tk.X, padx=20, pady=8)
        btn_frame.columnconfigure((0, 1, 2), weight=1)

        self.auto_btn = tk.Button(
            btn_frame, text="⚡ Auto-Connect",
            font=("Arial", 10, "bold"), bg="#7c3aed", fg="white",
            activebackground="#6d28d9", activeforeground="white",
            relief=tk.FLAT, cursor="hand2", bd=0, padx=10, pady=6,
            command=self._start_auto_connect
        )
        self.auto_btn.grid(row=0, column=0, padx=4, sticky=tk.EW)

        self.connect_btn = tk.Button(
            btn_frame, text="🔌 Connect",
            font=("Arial", 10), bg="#0f4c81", fg="white",
            activebackground="#1565c0", activeforeground="white",
            relief=tk.FLAT, cursor="hand2", bd=0, padx=10, pady=6,
            command=self._connect_device
        )
        self.connect_btn.grid(row=0, column=1, padx=4, sticky=tk.EW)

        self.disconnect_btn = tk.Button(
            btn_frame, text="✖ Disconnect",
            font=("Arial", 10), bg="#374151", fg="#9ca3af",
            activebackground="#4b5563", activeforeground="white",
            relief=tk.FLAT, cursor="hand2", bd=0, padx=10, pady=6,
            state=tk.DISABLED, command=self._disconnect_device
        )
        self.disconnect_btn.grid(row=0, column=2, padx=4, sticky=tk.EW)

        # ── Monitoring Controls ─────────────────────────────────────────
        ctrl_card = tk.LabelFrame(
            self.root, text=" Monitoring ", font=("Arial", 10, "bold"),
            fg="#a78bfa", bg="#16213e", bd=1, relief=tk.GROOVE, padx=12, pady=8
        )
        ctrl_card.pack(fill=tk.X, padx=20, pady=4)

        ctrl_row = tk.Frame(ctrl_card, bg="#16213e")
        ctrl_row.pack(fill=tk.X)
        ctrl_row.columnconfigure((0, 1), weight=1)

        self.start_btn = tk.Button(
            ctrl_row, text="▶ Start Monitoring",
            font=("Arial", 10, "bold"), bg="#166534", fg="white",
            activebackground="#15803d", activeforeground="white",
            relief=tk.FLAT, cursor="hand2", bd=0, padx=10, pady=6,
            state=tk.DISABLED, command=self._start_monitoring
        )
        self.start_btn.grid(row=0, column=0, padx=4, sticky=tk.EW)

        self.stop_btn = tk.Button(
            ctrl_row, text="■ Stop Monitoring",
            font=("Arial", 10), bg="#374151", fg="#9ca3af",
            activebackground="#4b5563", activeforeground="white",
            relief=tk.FLAT, cursor="hand2", bd=0, padx=10, pady=6,
            state=tk.DISABLED, command=self._stop_monitoring
        )
        self.stop_btn.grid(row=0, column=1, padx=4, sticky=tk.EW)

        # Auto-start monitoring checkbox
        self.auto_start_var = tk.BooleanVar(value=True)
        tk.Checkbutton(
            ctrl_card, text="Auto-start monitoring after connect",
            variable=self.auto_start_var, font=("Arial", 9),
            fg="#94a3b8", bg="#16213e", selectcolor="#0f172a",
            activeforeground="#c4b5fd", activebackground="#16213e"
        ).pack(anchor=tk.W, pady=(4, 0))

        # ── Status Footer ───────────────────────────────────────────────
        footer = tk.Frame(self.root, bg="#0f172a", height=36)
        footer.pack(fill=tk.X, side=tk.BOTTOM)
        footer.pack_propagate(False)
        self.footer_label = tk.Label(
            footer, text="●  Idle", font=("Arial", 9),
            fg="#64748b", bg="#0f172a"
        )
        self.footer_label.pack(pady=8)

    # ------------------------------------------------------------------
    # Port list helpers
    # ------------------------------------------------------------------

    def _refresh_ports_combo(self):
        """Populate the ports combobox with currently available ports."""
        ports = [p['device'] for p in self._auto_conn.find_all_ports()]
        self.ports_combo['values'] = ports
        if ports and not self.port_var.get():
            self.ports_combo.current(0)

    # ------------------------------------------------------------------
    # Status / logging helpers
    # ------------------------------------------------------------------

    def _set_status(self, text: str, color: str = "#94a3b8", dot: str = "#64748b"):
        """Update the status label and indicator dot (thread-safe via after)."""
        def _update():
            self.status_label.config(text=text, fg=color)
            self._dot_canvas.itemconfig(self._dot, fill=dot)
        self.root.after(0, _update)

    def _log_scan(self, message: str):
        """Append a line to the scan log widget (thread-safe)."""
        def _append():
            self.scan_log.config(state=tk.NORMAL)
            self.scan_log.insert(tk.END, message + "\n")
            self.scan_log.see(tk.END)
            self.scan_log.config(state=tk.DISABLED)
        self.root.after(0, _append)

    def _set_footer(self, text: str, color: str = "#64748b"):
        self.root.after(0, lambda: self.footer_label.config(text=text, fg=color))

    # ------------------------------------------------------------------
    # Auto-connect logic
    # ------------------------------------------------------------------

    def _start_auto_connect(self):
        """Begin universal auto-detect + connect in a background thread."""
        if self._auto_connect_active:
            return
        if self.connector and self.connector.is_connected:
            return
        self._auto_connect_active = True
        self.root.after(0, self._ui_scanning_state)

        self._auto_connect_thread = threading.Thread(
            target=self._auto_connect_worker, daemon=True
        )
        self._auto_connect_thread.start()

    def _auto_connect_worker(self):
        """Background: universal scan → detect → connect → optionally start monitoring."""
        self._log_scan("═══ Universal EEG device scan started ═══")
        self._set_status("Scanning all ports for EEG device…", "#f59e0b", "#f59e0b")

        def on_progress(msg: str):
            self._log_scan(f"  {msg}")

        device = self._auto_conn.scan(progress_callback=on_progress)

        if device:
            # Wire up the detected connector
            self.connector = device.connector
            self.connector.set_data_callback(self._on_eeg_data)
            label = {
                'tgam1':   'TGAM1 / MindLink',
                'esp32':   'ESP32 hub',
                'generic': 'EEG Sensor',
            }.get(device.device_type, device.device_type.upper())
            self._log_scan(f"✓ {label} connected on {device.port}")
            self.root.after(0, lambda: self._on_connected(device.port, label))
        else:
            self._log_scan("✗ No EEG device found on any port")
            self._log_scan(f"  Retrying in {int(AUTO_CONNECT_RETRY_INTERVAL)}s …")
            self._set_status("Device not found – retrying…", "#f87171", "#f87171")
            self._set_footer("●  Auto-Connect: retrying…", "#f87171")
            self.root.after(int(AUTO_CONNECT_RETRY_INTERVAL * 1000),
                            self._retry_auto_connect)

        self._auto_connect_active = False

    def _retry_auto_connect(self):
        """Scheduled retry of auto-connect."""
        if not (self.connector and self.connector.is_connected):
            self._start_auto_connect()

    def _on_connected(self, port: str, device_label: str = ""):
        """Called on the main thread after a successful connection."""
        self.root.after(0, self.progress_bar.stop)
        label_text = f"{device_label}  ─  {port}" if device_label else port
        self._set_status(f"Connected  ─  {label_text}", "#4ade80", "#4ade80")
        self._set_footer(f"●  Connected: {port}", "#4ade80")

        self.auto_btn.config(state=tk.DISABLED)
        self.connect_btn.config(state=tk.DISABLED)
        self.disconnect_btn.config(state=tk.NORMAL,
                                   bg="#7f1d1d", fg="white")
        self.start_btn.config(state=tk.NORMAL)

        # Auto-start monitoring if checkbox is ticked
        if self.auto_start_var.get():
            self._log_scan("Auto-start: launching monitoring…")
            self.root.after(500, self._start_monitoring)

    def _ui_scanning_state(self):
        """Update UI to reflect that scanning is in progress."""
        # Clear previous log and start progress bar
        self.scan_log.config(state=tk.NORMAL)
        self.scan_log.delete("1.0", tk.END)
        self.scan_log.config(state=tk.DISABLED)
        self.progress_bar.start(15)
        self.auto_btn.config(state=tk.DISABLED)
        self.connect_btn.config(state=tk.DISABLED)
        self._set_footer("●  Scanning…", "#f59e0b")

    # ------------------------------------------------------------------
    # Manual connect / disconnect
    # ------------------------------------------------------------------

    def _connect_device(self):
        """Manually connect using the entered/selected port."""
        if self.connector.is_connected:
            return
        port = self.port_var.get().strip() or None
        self._log_scan(f"Manual connect → {port or '(auto)'}")
        self._ui_scanning_state()

        def _worker():
            def on_progress(msg):
                self._log_scan(f"  {msg}")
            ok = self.connector.connect(port=port, progress_callback=on_progress)
            if ok:
                self.root.after(0, lambda: self._on_connected(self.connector.port))
            else:
                self._log_scan("✗ Connection failed")
                self.root.after(0, self._ui_ready_state)
                self.root.after(0, lambda: messagebox.showerror(
                    "Connection Failed",
                    "Could not connect to TGAM1 device.\n\n"
                    "Please verify:\n"
                    "  1. Device is powered on\n"
                    "  2. Bluetooth is paired\n"
                    "  3. Correct COM/serial port is selected"
                ))

        threading.Thread(target=_worker, daemon=True).start()

    def _ui_ready_state(self):
        """Restore UI to ready (disconnected) state."""
        self.progress_bar.stop()
        self.auto_btn.config(state=tk.NORMAL)
        self.connect_btn.config(state=tk.NORMAL)
        self.disconnect_btn.config(state=tk.DISABLED, bg="#374151", fg="#9ca3af")
        self.start_btn.config(state=tk.DISABLED)
        self._set_status("Ready – device disconnected", "#94a3b8", "#64748b")
        self._set_footer("●  Idle", "#64748b")

    def _disconnect_device(self):
        """Disconnect from TGAM1 device."""
        self._stop_monitoring()
        self.connector.disconnect()
        self._log_scan("Disconnected.")
        self._ui_ready_state()

    # ------------------------------------------------------------------
    # Monitoring
    # ------------------------------------------------------------------

    def _start_monitoring(self):
        """Start EEG monitoring session."""
        if not self.connector.is_connected:
            messagebox.showerror("Error", "Not connected to device")
            return
        if self.is_running:
            return

        # Initialize visualizer
        if self.visualizer is None:
            vis_window = tk.Toplevel(self.root)
            self.visualizer = EEGVisualizer(vis_window)

        # Reset components
        self.signal_processor.reset()
        self.feature_extractor.reset()
        self.alert_system.reset()
        self.visualizer.reset()

        # Start data acquisition thread
        self.is_running = True
        self.data_thread = threading.Thread(
            target=self._data_acquisition_loop, daemon=True
        )
        self.data_thread.start()

        self._set_status("Monitoring in progress…", "#38bdf8", "#38bdf8")
        self._set_footer("●  Monitoring", "#38bdf8")
        self.start_btn.config(state=tk.DISABLED)
        self.stop_btn.config(state=tk.NORMAL, bg="#7f1d1d", fg="white")
        logger.info("EEG monitoring started")

    def _stop_monitoring(self):
        """Stop EEG monitoring session."""
        if not self.is_running:
            return
        self.is_running = False
        if self.data_thread:
            self.data_thread.join(timeout=2)

        self._set_status(f"Monitoring stopped  ─  {self.connector.port}",
                         "#f59e0b", "#f59e0b")
        self._set_footer("●  Stopped", "#f59e0b")
        self.start_btn.config(state=tk.NORMAL)
        self.stop_btn.config(state=tk.DISABLED, bg="#374151", fg="#9ca3af")
        logger.info("EEG monitoring stopped")

    def _data_acquisition_loop(self):
        """Main real-time data acquisition and processing loop."""
        baseline_start_time = time.time()
        baseline_established = False

        while self.is_running:
            try:
                data = self.connector.read_data()

                if data is None:
                    time.sleep(0.1)
                    continue

                attention = data.get('attention')
                meditation = data.get('meditation')
                raw_eeg = data.get('raw_eeg')
                eeg_power = data.get('eeg_power')

                if eeg_power:
                    frequency_bands = self.signal_processor.process_tgam_power_data(eeg_power)
                elif raw_eeg is not None:
                    frequency_bands = self.signal_processor.process_raw_eeg(raw_eeg)
                else:
                    frequency_bands = {}

                band_ratios = self.signal_processor.calculate_band_ratios(frequency_bands)

                self.feature_extractor.add_sample(
                    attention, meditation, frequency_bands, band_ratios
                )

                if not baseline_established:
                    elapsed = time.time() - baseline_start_time
                    if elapsed >= BASELINE_DURATION and self.feature_extractor.baseline_established:
                        baseline_established = True
                        logger.info("Baseline established")
                        if self.visualizer:
                            self.visualizer.set_status("Monitoring (Baseline Ready)", "green")
                    continue

                features = self.feature_extractor.extract_features()
                predictions = self.ml_model.predict(features)
                alert = self.alert_system.check_alerts(features, predictions)

                if self.visualizer:
                    vis_data = {
                        'attention': attention if attention else features.get('attention_mean', 0),
                        'meditation': meditation if meditation else features.get('meditation_mean', 0),
                        'frequency_bands': frequency_bands,
                        'fatigue_score': predictions.get('fatigue_score', 0.0),
                        'cognitive_drift': predictions.get('cognitive_drift', 0.0),
                    }
                    self.visualizer.update_data(vis_data)

                time.sleep(0.1)

            except Exception as e:
                logger.error(f"Error in data acquisition loop: {e}")
                time.sleep(0.5)

    # ------------------------------------------------------------------
    # Callbacks
    # ------------------------------------------------------------------

    def _on_eeg_data(self, data: Dict):
        """Callback for received EEG data (called by connector)."""
        pass

    def _on_alert(self, alert: Dict):
        """Callback for triggered fatigue alerts."""
        level = alert['level']
        message = alert['message']
        if level == 'critical':
            self.root.after(0, lambda: messagebox.showwarning("⚠ CRITICAL ALERT", message))
        elif level == 'high':
            self.root.after(0, lambda: messagebox.showwarning("⚠ HIGH ALERT", message))
        else:
            logger.info(f"Alert [{level}]: {message}")

    # ------------------------------------------------------------------
    # Run
    # ------------------------------------------------------------------

    def run(self):
        """Start the application. Schedules background auto-connect."""
        # Kick off auto-connect shortly after the window opens
        self.root.after(int(AUTO_CONNECT_DELAY * 1000), self._start_auto_connect)
        try:
            self.root.mainloop()
        except KeyboardInterrupt:
            logger.info("Interrupted by user")
        finally:
            self._stop_monitoring()
            self.connector.disconnect()


def main():
    """Main entry point"""
    app = EEGFatigueSystem()
    app.run()


if __name__ == "__main__":
    main()
