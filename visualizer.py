"""
Real-time visualization dashboard for EEG data and fatigue monitoring
"""

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
import tkinter as tk
from tkinter import ttk
from collections import deque
from typing import Dict, Optional
import logging
from config import UPDATE_INTERVAL, PLOT_HISTORY_SIZE

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class EEGVisualizer:
    """
    Real-time visualization dashboard for EEG monitoring
    """
    
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("EEG Mental Fatigue Detection System")
        self.root.geometry("1400x900")
        
        # Data buffers
        self.time_buffer = deque(maxlen=PLOT_HISTORY_SIZE)
        self.attention_buffer = deque(maxlen=PLOT_HISTORY_SIZE)
        self.meditation_buffer = deque(maxlen=PLOT_HISTORY_SIZE)
        self.fatigue_buffer = deque(maxlen=PLOT_HISTORY_SIZE)
        self.alpha_buffer = deque(maxlen=PLOT_HISTORY_SIZE)
        self.beta_buffer = deque(maxlen=PLOT_HISTORY_SIZE)
        self.theta_buffer = deque(maxlen=PLOT_HISTORY_SIZE)
        self.delta_buffer = deque(maxlen=PLOT_HISTORY_SIZE)
        self.gamma_buffer = deque(maxlen=PLOT_HISTORY_SIZE)
        
        self.current_time = 0.0
        
        # Setup UI
        self._setup_ui()
        
        # Start animation
        self.ani = FuncAnimation(self.fig, self._update_plots, 
                                interval=UPDATE_INTERVAL, blit=False)
    
    def _setup_ui(self):
        """Setup the user interface"""
        # Create main frame
        main_frame = ttk.Frame(self.root, padding="10")
        main_frame.grid(row=0, column=0, sticky=(tk.W, tk.E, tk.N, tk.S))
        
        # Status frame
        status_frame = ttk.LabelFrame(main_frame, text="System Status", padding="10")
        status_frame.grid(row=0, column=0, columnspan=2, sticky=(tk.W, tk.E), pady=5)
        
        self.status_label = ttk.Label(status_frame, text="Status: Disconnected", 
                                      font=("Arial", 12, "bold"))
        self.status_label.grid(row=0, column=0, padx=10)
        
        self.attention_label = ttk.Label(status_frame, text="Attention: --", 
                                        font=("Arial", 10))
        self.attention_label.grid(row=0, column=1, padx=10)
        
        self.meditation_label = ttk.Label(status_frame, text="Meditation: --", 
                                         font=("Arial", 10))
        self.meditation_label.grid(row=0, column=2, padx=10)
        
        self.fatigue_label = ttk.Label(status_frame, text="Fatigue Score: --", 
                                      font=("Arial", 10, "bold"), foreground="blue")
        self.fatigue_label.grid(row=0, column=3, padx=10)
        
        # Create matplotlib figure
        self.fig = plt.Figure(figsize=(13, 8), dpi=100)
        self.canvas = FigureCanvasTkAgg(self.fig, main_frame)
        self.canvas.get_tk_widget().grid(row=1, column=0, columnspan=2, pady=10)
        
        # Create subplots
        self.ax1 = self.fig.add_subplot(2, 3, 1)  # Attention/Meditation
        self.ax2 = self.fig.add_subplot(2, 3, 2)  # Frequency Bands
        self.ax3 = self.fig.add_subplot(2, 3, 3)  # Fatigue Score
        self.ax4 = self.fig.add_subplot(2, 3, 4)  # Alpha/Beta Ratio
        self.ax5 = self.fig.add_subplot(2, 3, 5)  # Cognitive Drift
        self.ax6 = self.fig.add_subplot(2, 3, 6)  # Power Spectrum
        
        self.fig.tight_layout(pad=3.0)
        
        # Initialize plots
        self._init_plots()
    
    def _init_plots(self):
        """Initialize empty plots"""
        # Attention/Meditation plot
        self.ax1.set_title("Attention & Meditation", fontsize=10, fontweight='bold')
        self.ax1.set_xlabel("Time (s)")
        self.ax1.set_ylabel("Value (0-100)")
        self.ax1.set_ylim(0, 100)
        self.ax1.grid(True, alpha=0.3)
        self.line_attn, = self.ax1.plot([], [], 'b-', label='Attention', linewidth=2)
        self.line_med, = self.ax1.plot([], [], 'g-', label='Meditation', linewidth=2)
        self.ax1.legend()
        
        # Frequency Bands plot
        self.ax2.set_title("Frequency Band Powers", fontsize=10, fontweight='bold')
        self.ax2.set_xlabel("Time (s)")
        self.ax2.set_ylabel("Normalized Power")
        self.ax2.set_ylim(0, 1)
        self.ax2.grid(True, alpha=0.3)
        self.line_alpha, = self.ax2.plot([], [], 'r-', label='Alpha', linewidth=2)
        self.line_beta, = self.ax2.plot([], [], 'b-', label='Beta', linewidth=2)
        self.line_theta, = self.ax2.plot([], [], 'g-', label='Theta', linewidth=2)
        self.line_delta, = self.ax2.plot([], [], 'm-', label='Delta', linewidth=2)
        self.line_gamma, = self.ax2.plot([], [], 'c-', label='Gamma', linewidth=2)
        self.ax2.legend(fontsize=8)
        
        # Fatigue Score plot
        self.ax3.set_title("Fatigue Score", fontsize=10, fontweight='bold')
        self.ax3.set_xlabel("Time (s)")
        self.ax3.set_ylabel("Fatigue (0-1)")
        self.ax3.set_ylim(0, 1)
        self.ax3.grid(True, alpha=0.3)
        self.ax3.axhline(y=0.4, color='orange', linestyle='--', label='Warning')
        self.ax3.axhline(y=0.7, color='red', linestyle='--', label='Critical')
        self.line_fatigue, = self.ax3.plot([], [], 'r-', linewidth=2)
        self.ax3.legend(fontsize=8)
        
        # Alpha/Beta Ratio plot
        self.ax4.set_title("Alpha/Beta Ratio", fontsize=10, fontweight='bold')
        self.ax4.set_xlabel("Time (s)")
        self.ax4.set_ylabel("Ratio")
        self.ax4.grid(True, alpha=0.3)
        self.line_ab_ratio, = self.ax4.plot([], [], 'purple', linewidth=2)
        
        # Cognitive Drift plot
        self.ax5.set_title("Cognitive Drift", fontsize=10, fontweight='bold')
        self.ax5.set_xlabel("Time (s)")
        self.ax5.set_ylabel("Drift Value")
        self.ax5.set_ylim(0, 1)
        self.ax5.grid(True, alpha=0.3)
        self.ax5.axhline(y=0.15, color='red', linestyle='--', label='Threshold')
        self.line_drift, = self.ax5.plot([], [], 'orange', linewidth=2)
        self.ax5.legend(fontsize=8)
        
        # Power Spectrum (bar chart)
        self.ax6.set_title("Current Frequency Band Distribution", fontsize=10, fontweight='bold')
        self.ax6.set_xlabel("Frequency Band")
        self.ax6.set_ylabel("Power")
        self.ax6.set_ylim(0, 1)
        bands = ['Delta', 'Theta', 'Alpha', 'Beta', 'Gamma']
        self.bar_plot = self.ax6.bar(bands, [0]*5, color=['magenta', 'green', 'red', 'blue', 'cyan'])
        self.ax6.grid(True, alpha=0.3, axis='y')
    
    def update_data(self, data: Dict):
        """
        Update visualization with new data
        Args:
            data: Dictionary containing EEG data, features, and predictions
        """
        self.current_time += UPDATE_INTERVAL / 1000.0  # Convert to seconds
        
        # Update buffers
        self.time_buffer.append(self.current_time)
        
        if 'attention' in data:
            self.attention_buffer.append(data['attention'])
        if 'meditation' in data:
            self.meditation_buffer.append(data['meditation'])
        if 'fatigue_score' in data:
            self.fatigue_buffer.append(data['fatigue_score'])
        if 'frequency_bands' in data:
            bands = data['frequency_bands']
            self.alpha_buffer.append(bands.get('alpha', 0))
            self.beta_buffer.append(bands.get('beta', 0))
            self.theta_buffer.append(bands.get('theta', 0))
            self.delta_buffer.append(bands.get('delta', 0))
            self.gamma_buffer.append(bands.get('gamma', 0))
        
        # Update status labels
        if 'attention' in data:
            self.attention_label.config(text=f"Attention: {data['attention']:.1f}")
        if 'meditation' in data:
            self.meditation_label.config(text=f"Meditation: {data['meditation']:.1f}")
        if 'fatigue_score' in data:
            score = data['fatigue_score']
            color = 'green' if score < 0.3 else 'orange' if score < 0.5 else 'red'
            self.fatigue_label.config(text=f"Fatigue Score: {score:.3f}", 
                                     foreground=color)
    
    def _update_plots(self, frame):
        """Update all plots with current data"""
        if not self.time_buffer:
            return
        
        time_array = np.array(list(self.time_buffer))
        
        # Update Attention/Meditation
        if self.attention_buffer:
            self.line_attn.set_data(time_array, list(self.attention_buffer))
        if self.meditation_buffer:
            self.line_med.set_data(time_array, list(self.meditation_buffer))
        self.ax1.relim()
        self.ax1.autoscale_view()
        
        # Update Frequency Bands
        if self.alpha_buffer:
            self.line_alpha.set_data(time_array, list(self.alpha_buffer))
            self.line_beta.set_data(time_array, list(self.beta_buffer))
            self.line_theta.set_data(time_array, list(self.theta_buffer))
            self.line_delta.set_data(time_array, list(self.delta_buffer))
            self.line_gamma.set_data(time_array, list(self.gamma_buffer))
        self.ax2.relim()
        self.ax2.autoscale_view()
        
        # Update Fatigue Score
        if self.fatigue_buffer:
            self.line_fatigue.set_data(time_array, list(self.fatigue_buffer))
        self.ax3.relim()
        self.ax3.autoscale_view()
        
        # Update Alpha/Beta Ratio (if available)
        if self.alpha_buffer and self.beta_buffer:
            ab_ratio = [a/b if b > 0 else 0 for a, b in 
                       zip(self.alpha_buffer, self.beta_buffer)]
            self.line_ab_ratio.set_data(time_array, ab_ratio)
        self.ax4.relim()
        self.ax4.autoscale_view()
        
        # Update Cognitive Drift (placeholder - would need drift data)
        # self.line_drift.set_data(time_array, drift_data)
        
        # Update Power Spectrum bars
        if self.alpha_buffer:
            current_powers = [
                list(self.delta_buffer)[-1] if self.delta_buffer else 0,
                list(self.theta_buffer)[-1] if self.theta_buffer else 0,
                list(self.alpha_buffer)[-1] if self.alpha_buffer else 0,
                list(self.beta_buffer)[-1] if self.beta_buffer else 0,
                list(self.gamma_buffer)[-1] if self.gamma_buffer else 0
            ]
            for bar, power in zip(self.bar_plot, current_powers):
                bar.set_height(power)
            self.ax6.set_ylim(0, max(current_powers) * 1.2 if current_powers else 1)
        
        self.canvas.draw()
    
    def set_status(self, status: str, color: str = "black"):
        """Update status label"""
        self.status_label.config(text=f"Status: {status}", foreground=color)
    
    def reset(self):
        """Reset all buffers"""
        self.time_buffer.clear()
        self.attention_buffer.clear()
        self.meditation_buffer.clear()
        self.fatigue_buffer.clear()
        self.alpha_buffer.clear()
        self.beta_buffer.clear()
        self.theta_buffer.clear()
        self.delta_buffer.clear()
        self.gamma_buffer.clear()
        self.current_time = 0.0
