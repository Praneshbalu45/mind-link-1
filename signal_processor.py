"""
Signal processing module for EEG frequency band extraction
Processes RAW EEG data to extract Alpha, Beta, Theta, Delta, and Gamma bands
"""

import numpy as np
from scipy import signal
from scipy.fft import fft, fftfreq
from typing import Dict, Optional, Tuple
import logging
from config import SAMPLE_RATE, WINDOW_SIZE, OVERLAP, FREQUENCY_BANDS

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class SignalProcessor:
    """
    Processes RAW EEG signals to extract frequency bands and features
    """
    
    def __init__(self, sample_rate: int = SAMPLE_RATE):
        self.sample_rate = sample_rate
        self.raw_buffer = []
        self.buffer_size = 512  # Keep last 512 samples
        self.frequency_bands = FREQUENCY_BANDS
        
    def add_raw_sample(self, raw_value: float):
        """Add a raw EEG sample to the buffer"""
        self.raw_buffer.append(raw_value)
        if len(self.raw_buffer) > self.buffer_size:
            self.raw_buffer.pop(0)
    
    def extract_frequency_bands(self, signal_data: np.ndarray) -> Dict[str, float]:
        """
        Extract power in different frequency bands using FFT
        Args:
            signal_data: Array of EEG samples
        Returns:
            Dictionary with power values for each frequency band
        """
        if len(signal_data) < WINDOW_SIZE:
            return self._get_empty_bands()
        
        # Apply window function to reduce spectral leakage
        windowed = signal_data * signal.windows.hann(len(signal_data))
        
        # Compute FFT
        fft_values = fft(windowed)
        fft_freqs = fftfreq(len(windowed), 1.0 / self.sample_rate)
        
        # Get power spectral density
        power_spectrum = np.abs(fft_values) ** 2
        
        # Extract power in each frequency band
        bands = {}
        total_power = np.sum(power_spectrum)
        
        for band_name, (low_freq, high_freq) in self.frequency_bands.items():
            # Find indices for frequency range
            band_mask = (fft_freqs >= low_freq) & (fft_freqs <= high_freq)
            band_power = np.sum(power_spectrum[band_mask])
            
            # Normalize by total power
            bands[band_name] = band_power / total_power if total_power > 0 else 0.0
        
        return bands
    
    def process_raw_eeg(self, raw_value: Optional[float] = None) -> Dict[str, float]:
        """
        Process raw EEG value and extract frequency bands
        Args:
            raw_value: Raw EEG sample value
        Returns:
            Dictionary with frequency band powers
        """
        if raw_value is not None:
            self.add_raw_sample(raw_value)
        
        if len(self.raw_buffer) < WINDOW_SIZE:
            return self._get_empty_bands()
        
        # Convert buffer to numpy array
        signal_array = np.array(self.raw_buffer[-WINDOW_SIZE:])
        
        # Remove DC component
        signal_array = signal_array - np.mean(signal_array)
        
        # Apply bandpass filter (0.5-100 Hz) to remove noise
        try:
            sos = signal.butter(4, [0.5, 100], btype='band', 
                              fs=self.sample_rate, output='sos')
            filtered_signal = signal.sosfilt(sos, signal_array)
        except:
            filtered_signal = signal_array
        
        # Extract frequency bands
        bands = self.extract_frequency_bands(filtered_signal)
        
        return bands
    
    def process_tgam_power_data(self, eeg_power: Dict) -> Dict[str, float]:
        """
        Process TGAM1's pre-computed EEG power values
        TGAM1 provides: delta, theta, low_alpha, high_alpha, 
                        low_beta, high_beta, low_gamma, high_gamma
        """
        # Combine bands according to our frequency definitions
        total_power = sum(eeg_power.values())
        
        if total_power == 0:
            return self._get_empty_bands()
        
        bands = {
            'delta': eeg_power.get('delta', 0) / total_power,
            'theta': eeg_power.get('theta', 0) / total_power,
            'alpha': (eeg_power.get('low_alpha', 0) + 
                     eeg_power.get('high_alpha', 0)) / total_power,
            'beta': (eeg_power.get('low_beta', 0) + 
                    eeg_power.get('high_beta', 0)) / total_power,
            'gamma': (eeg_power.get('low_gamma', 0) + 
                     eeg_power.get('high_gamma', 0)) / total_power
        }
        
        return bands
    
    def calculate_band_ratios(self, bands: Dict[str, float]) -> Dict[str, float]:
        """
        Calculate important frequency band ratios for fatigue detection
        """
        ratios = {}
        
        # Alpha/Beta ratio (indicates relaxation vs alertness)
        if bands.get('beta', 0) > 0:
            ratios['alpha_beta'] = bands.get('alpha', 0) / bands.get('beta', 0)
        else:
            ratios['alpha_beta'] = 0.0
        
        # Theta/Alpha ratio (indicates drowsiness)
        if bands.get('alpha', 0) > 0:
            ratios['theta_alpha'] = bands.get('theta', 0) / bands.get('alpha', 0)
        else:
            ratios['theta_alpha'] = 0.0
        
        # Beta/Delta ratio (indicates cognitive activity)
        if bands.get('delta', 0) > 0:
            ratios['beta_delta'] = bands.get('beta', 0) / bands.get('delta', 0)
        else:
            ratios['beta_delta'] = 0.0
        
        # (Alpha + Theta) / Beta ratio (fatigue indicator)
        if bands.get('beta', 0) > 0:
            ratios['alpha_theta_beta'] = (bands.get('alpha', 0) + bands.get('theta', 0)) / bands.get('beta', 0)
        else:
            ratios['alpha_theta_beta'] = 0.0
        
        return ratios
    
    def _get_empty_bands(self) -> Dict[str, float]:
        """Return empty frequency bands dictionary"""
        return {band: 0.0 for band in self.frequency_bands.keys()}
    
    def reset(self):
        """Reset the signal buffer"""
        self.raw_buffer = []
