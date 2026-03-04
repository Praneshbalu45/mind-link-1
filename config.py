"""
Configuration settings for EEG-Based Mental Fatigue Detection System
"""

# Bluetooth Configuration
BLUETOOTH_BAUD_RATE = 57600
BLUETOOTH_TIMEOUT = 1.0
BLUETOOTH_RETRY_ATTEMPTS = 3

# EEG Signal Processing
SAMPLE_RATE = 512  # TGAM1 typical sample rate
WINDOW_SIZE = 256  # FFT window size
OVERLAP = 128      # Window overlap for continuous processing

# Frequency Bands (Hz)
FREQUENCY_BANDS = {
    'delta': (0.5, 4),
    'theta': (4, 8),
    'alpha': (8, 13),
    'beta': (13, 30),
    'gamma': (30, 100)
}

# Fatigue Detection Thresholds
FATIGUE_THRESHOLDS = {
    'attention_low': 40,      # Low attention threshold
    'meditation_low': 30,     # Low meditation threshold
    'alpha_high': 0.4,        # High alpha power ratio (relaxation/fatigue)
    'beta_low': 0.2,          # Low beta power ratio (alertness)
    'theta_high': 0.3,        # High theta power ratio (drowsiness)
    'drift_threshold': 0.15   # Cognitive drift threshold
}

# Baseline Calibration
BASELINE_DURATION = 60  # seconds for baseline establishment
BASELINE_SAMPLES = 30   # number of samples for baseline

# Alert System
ALERT_COOLDOWN = 300    # seconds between alerts
ALERT_LEVELS = {
    'low': 0.1,
    'medium': 0.2,
    'high': 0.3,
    'critical': 0.4
}

# Visualization
UPDATE_INTERVAL = 100   # milliseconds
PLOT_HISTORY_SIZE = 1000  # number of data points to display

# Machine Learning
ML_MODEL_PATH = 'models/fatigue_detector.pkl'
FEATURE_WINDOW_SIZE = 10  # number of samples for feature window
