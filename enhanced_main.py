"""
Enhanced Main Application with ESP32 Multi-Sensor Support
Uses ESP32 hub for improved accuracy through multi-sensor fusion
"""

import tkinter as tk
from tkinter import messagebox, ttk
import threading
import time
import logging
from typing import Optional, Dict

# Import standard modules
from signal_processor import SignalProcessor
from feature_extractor import FeatureExtractor
from ml_model import FatigueDetector
from visualizer import EEGVisualizer
from alert_system import AlertSystem
from config import BASELINE_DURATION

# Import ESP32 modules
from esp32_connector import ESP32Connector, MultiSensorFusion

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class EnhancedEEGFatigueSystem:
    """
    Enhanced application with ESP32 multi-sensor support
    """
    
    def __init__(self, use_esp32: bool = False):
        self.use_esp32 = use_esp32
        
        # Initialize components
        if use_esp32:
            self.connector = ESP32Connector()
            self.sensor_fusion = MultiSensorFusion()
            logger.info("Using ESP32 multi-sensor mode")
        else:
            # Use standard TGAM1 connector
            from bluetooth_connector import TGAM1Connector
            self.connector = TGAM1Connector()
            self.sensor_fusion = None
            logger.info("Using standard TGAM1 mode")
        
        self.signal_processor = SignalProcessor()
        self.feature_extractor = FeatureExtractor()
        self.ml_model = FatigueDetector()
        self.alert_system = AlertSystem()
        
        # State
        self.is_running = False
        self.data_thread: Optional[threading.Thread] = None
        self.visualizer: Optional[EEGVisualizer] = None
        
        # Setup GUI
        self.root = tk.Tk()
        self._setup_gui()
        
        # Set callbacks
        self.connector.set_data_callback(self._on_sensor_data)
        self.alert_system.set_alert_callback(self._on_alert)
    
    def _setup_gui(self):
        """Setup the main GUI"""
        self.root.title("EEG Mental Fatigue Detection System - Enhanced")
        self.root.geometry("250x200")
        
        # Control frame
        control_frame = ttk.Frame(self.root, padding="10")
        control_frame.pack()
        
        # Mode selection
        mode_frame = ttk.LabelFrame(control_frame, text="Mode", padding="10")
        mode_frame.pack(pady=5)
        
        self.mode_var = tk.StringVar(value="standard" if not self.use_esp32 else "esp32")
        ttk.Radiobutton(mode_frame, text="Standard (TGAM1 only)", 
                       variable=self.mode_var, value="standard").pack(anchor=tk.W)
        ttk.Radiobutton(mode_frame, text="Enhanced (ESP32 + Sensors)", 
                       variable=self.mode_var, value="esp32").pack(anchor=tk.W)
        
        # Connection frame
        conn_frame = ttk.LabelFrame(control_frame, text="Connection", padding="10")
        conn_frame.pack(pady=5)
        
        self.port_var = tk.StringVar()
        ttk.Label(conn_frame, text="Port:").grid(row=0, column=0, padx=5)
        port_entry = ttk.Entry(conn_frame, textvariable=self.port_var, width=15)
        port_entry.grid(row=0, column=1, padx=5)
        
        self.connect_btn = ttk.Button(conn_frame, text="Connect", 
                                     command=self._connect_device)
        self.connect_btn.grid(row=1, column=0, columnspan=2, pady=5)
        
        self.disconnect_btn = ttk.Button(conn_frame, text="Disconnect", 
                                         command=self._disconnect_device, 
                                         state=tk.DISABLED)
        self.disconnect_btn.grid(row=2, column=0, columnspan=2, pady=5)
        
        # Control frame
        ctrl_frame = ttk.LabelFrame(control_frame, text="Control", padding="10")
        ctrl_frame.pack(pady=5)
        
        self.start_btn = ttk.Button(ctrl_frame, text="Start Monitoring", 
                                    command=self._start_monitoring,
                                    state=tk.DISABLED)
        self.start_btn.pack(pady=5)
        
        self.stop_btn = ttk.Button(ctrl_frame, text="Stop Monitoring", 
                                  command=self._stop_monitoring,
                                  state=tk.DISABLED)
        self.stop_btn.pack(pady=5)
        
        # Status
        self.status_label = ttk.Label(control_frame, text="Status: Ready", 
                                      font=("Arial", 10, "bold"))
        self.status_label.pack(pady=5)
    
    def _connect_device(self):
        """Connect to device"""
        port = self.port_var.get().strip()
        if not port:
            port = None
        
        if self.connector.connect(port):
            mode = "ESP32" if self.use_esp32 else "TGAM1"
            self.status_label.config(text=f"Status: Connected ({mode})", foreground="green")
            self.connect_btn.config(state=tk.DISABLED)
            self.disconnect_btn.config(state=tk.NORMAL)
            self.start_btn.config(state=tk.NORMAL)
            messagebox.showinfo("Success", f"Connected to {mode} device successfully!")
        else:
            messagebox.showerror("Error", "Failed to connect to device")
    
    def _disconnect_device(self):
        """Disconnect from device"""
        self._stop_monitoring()
        self.connector.disconnect()
        self.status_label.config(text="Status: Disconnected", foreground="red")
        self.connect_btn.config(state=tk.NORMAL)
        self.disconnect_btn.config(state=tk.DISABLED)
        self.start_btn.config(state=tk.DISABLED)
    
    def _start_monitoring(self):
        """Start monitoring"""
        if not self.connector.is_connected:
            messagebox.showerror("Error", "Not connected to device")
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
        self.data_thread = threading.Thread(target=self._data_acquisition_loop, daemon=True)
        self.data_thread.start()
        
        self.status_label.config(text="Status: Monitoring...", foreground="blue")
        self.start_btn.config(state=tk.DISABLED)
        self.stop_btn.config(state=tk.NORMAL)
    
    def _stop_monitoring(self):
        """Stop monitoring"""
        self.is_running = False
        if self.data_thread:
            self.data_thread.join(timeout=2)
        
        self.status_label.config(text="Status: Stopped", foreground="orange")
        self.start_btn.config(state=tk.NORMAL)
        self.stop_btn.config(state=tk.DISABLED)
    
    def _data_acquisition_loop(self):
        """Main data acquisition and processing loop"""
        baseline_start_time = time.time()
        baseline_established = False
        
        while self.is_running:
            try:
                # Read data from device
                data = self.connector.read_data()
                
                if data is None:
                    time.sleep(0.1)
                    continue
                
                # Process data based on mode
                if self.use_esp32 and self.sensor_fusion:
                    # ESP32 mode: data already contains all sensors
                    eeg_data = data.get('eeg', {})
                    sensor_data = {k: v for k, v in data.items() if k != 'eeg'}
                    
                    # Fuse multi-sensor data
                    fused = self.sensor_fusion.fuse_data(eeg_data, sensor_data)
                    
                    attention = eeg_data.get('attention')
                    meditation = eeg_data.get('meditation')
                    eeg_power = eeg_data.get('power', {})
                    
                    # Use fused fatigue score
                    fatigue_score = fused.get('fused_fatigue_score', 0.0)
                else:
                    # Standard mode: process TGAM1 data
                    attention = data.get('attention')
                    meditation = data.get('meditation')
                    raw_eeg = data.get('raw_eeg')
                    eeg_power = data.get('eeg_power')
                    fatigue_score = None
                
                # Extract frequency bands
                if eeg_power:
                    frequency_bands = self.signal_processor.process_tgam_power_data(eeg_power)
                elif 'raw' in data or raw_eeg is not None:
                    raw_value = data.get('raw', raw_eeg)
                    frequency_bands = self.signal_processor.process_raw_eeg(raw_value)
                else:
                    frequency_bands = {}
                
                # Calculate band ratios
                band_ratios = self.signal_processor.calculate_band_ratios(frequency_bands)
                
                # Extract features
                self.feature_extractor.add_sample(
                    attention, meditation, frequency_bands, band_ratios
                )
                
                # Wait for baseline establishment
                if not baseline_established:
                    elapsed = time.time() - baseline_start_time
                    if elapsed >= BASELINE_DURATION and self.feature_extractor.baseline_established:
                        baseline_established = True
                        logger.info("Baseline established, starting fatigue detection")
                        if self.visualizer:
                            self.visualizer.set_status("Monitoring (Baseline Ready)", "green")
                    continue
                
                # Extract features for ML model
                features = self.feature_extractor.extract_features()
                
                # Use fused fatigue score if available, otherwise predict
                if fatigue_score is not None:
                    predictions = {
                        'fatigue_score': fatigue_score,
                        'fatigue_level': self._classify_fatigue_level(fatigue_score),
                        'cognitive_drift': features.get('cognitive_drift', 0.0),
                        'needs_alert': fatigue_score > 0.4
                    }
                else:
                    predictions = self.ml_model.predict(features)
                
                # Check for alerts
                alert = self.alert_system.check_alerts(features, predictions)
                
                # Update visualization
                if self.visualizer:
                    vis_data = {
                        'attention': attention if attention else features.get('attention_mean', 0),
                        'meditation': meditation if meditation else features.get('meditation_mean', 0),
                        'frequency_bands': frequency_bands,
                        'fatigue_score': predictions.get('fatigue_score', 0.0),
                        'cognitive_drift': predictions.get('cognitive_drift', 0.0)
                    }
                    self.visualizer.update_data(vis_data)
                
                time.sleep(0.1)
                
            except Exception as e:
                logger.error(f"Error in data acquisition loop: {e}")
                time.sleep(0.5)
    
    def _classify_fatigue_level(self, score: float) -> str:
        """Classify fatigue level from score"""
        if score < 0.3:
            return 'low'
        elif score < 0.5:
            return 'medium'
        elif score < 0.7:
            return 'high'
        else:
            return 'critical'
    
    def _on_sensor_data(self, data: Dict):
        """Callback for received sensor data"""
        pass
    
    def _on_alert(self, alert: Dict):
        """Callback for triggered alerts"""
        level = alert['level']
        message = alert['message']
        
        if level in ['critical', 'high']:
            messagebox.showwarning(f"{level.upper()} ALERT", message)
        else:
            logger.info(f"Alert: {message}")
    
    def run(self):
        """Run the application"""
        try:
            self.root.mainloop()
        except KeyboardInterrupt:
            logger.info("Application interrupted by user")
        finally:
            self._stop_monitoring()
            self.connector.disconnect()


def main():
    """Main entry point"""
    import sys
    
    # Check if ESP32 mode requested
    use_esp32 = '--esp32' in sys.argv or '-e' in sys.argv
    
    app = EnhancedEEGFatigueSystem(use_esp32=use_esp32)
    app.run()


if __name__ == "__main__":
    main()
