# Project Summary: EEG-Based Mental Fatigue & Micro-Burnout Early Warning System

## Project Overview

This project implements a comprehensive real-time EEG-based early warning system for detecting mental fatigue and micro-burnout conditions. The system uses a TGAM1 EEG headset to continuously monitor brain activity and provides proactive alerts when cognitive drift is detected.

## Key Features Implemented

### 1. **Hardware Integration** (`bluetooth_connector.py`)
- Bluetooth 3.0 connectivity for TGAM1 chipset
- Serial communication at 57600 baud rate
- Automatic port detection
- Robust packet parsing for TGAM1 protocol
- Support for RAW EEG data and pre-processed power values
- Attention and meditation metrics extraction

### 2. **Signal Processing** (`signal_processor.py`)
- Real-time frequency band extraction:
  - **Delta** (0.5-4 Hz): Deep sleep
  - **Theta** (4-8 Hz): Drowsiness, light sleep
  - **Alpha** (8-13 Hz): Relaxation, drowsiness indicator
  - **Beta** (13-30 Hz): Active thinking, alertness
  - **Gamma** (30-100 Hz): Cognitive processing
- FFT-based spectral analysis
- Bandpass filtering (0.5-100 Hz)
- Frequency band ratio calculations for fatigue indicators

### 3. **Feature Extraction** (`feature_extractor.py`)
- Statistical feature extraction from time-series data
- Baseline establishment (60-second calibration period)
- Cognitive drift calculation
- Composite fatigue score computation
- Trend analysis (linear regression)
- Multi-dimensional feature vectors for ML model

### 4. **Machine Learning Model** (`ml_model.py`)
- Gradient Boosting Regressor for fatigue prediction
- Feature normalization and scaling
- Rule-based fallback when model not trained
- Fatigue level classification (low/medium/high/critical)
- Cognitive drift severity assessment
- Model persistence (save/load functionality)

### 5. **Real-Time Visualization** (`visualizer.py`)
- Multi-panel dashboard with 6 synchronized plots:
  1. Attention & Meditation trends
  2. Frequency band powers over time
  3. Fatigue score with warning thresholds
  4. Alpha/Beta ratio (relaxation indicator)
  5. Cognitive drift monitoring
  6. Current frequency band distribution
- Live status indicators
- Color-coded fatigue alerts
- Configurable update intervals

### 6. **Alert System** (`alert_system.py`)
- Four-level alert system:
  - **LOW**: Early fatigue signs (score > 0.1)
  - **MEDIUM**: Moderate fatigue (score > 0.2)
  - **HIGH**: Significant fatigue (score > 0.3)
  - **CRITICAL**: Severe fatigue (score > 0.4)
- Cooldown mechanism to prevent alert spam
- Multi-factor alert triggering:
  - Fatigue score thresholds
  - Cognitive drift detection
  - Attention/meditation drops
- Alert history tracking

### 7. **Main Application** (`main.py`)
- Complete system orchestration
- GUI for device connection and control
- Multi-threaded data acquisition
- Real-time processing pipeline
- Error handling and recovery
- Graceful shutdown

## Technical Architecture

```
┌─────────────────┐
│  TGAM1 Device   │
│  (Bluetooth)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Bluetooth       │
│ Connector       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Signal          │
│ Processor       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Feature         │
│ Extractor       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ ML Model        │
│ (Fatigue        │
│  Detector)      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Alert System    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Visualizer      │
│ (Dashboard)     │
└─────────────────┘
```

## Scientific Foundation

### EEG Frequency Bands and Fatigue Indicators

1. **Alpha Band (8-13 Hz)**
   - Increased alpha power indicates relaxation and potential drowsiness
   - High alpha/beta ratio suggests reduced alertness

2. **Beta Band (13-30 Hz)**
   - Decreased beta power indicates reduced cognitive activity
   - Critical for maintaining attention and focus

3. **Theta Band (4-8 Hz)**
   - Increased theta power indicates drowsiness
   - High theta/alpha ratio is a strong fatigue indicator

4. **Attention & Meditation Metrics**
   - TGAM1 provides proprietary attention (0-100) and meditation (0-100) scores
   - Declining trends indicate cognitive fatigue

### Cognitive Drift Detection

The system monitors gradual deviations from baseline cognitive patterns:
- Baseline established during initial 60-second calibration
- Continuous comparison of current state vs. baseline
- Detects subtle changes that may precede overt fatigue

## Configuration

All system parameters are configurable via `config.py`:
- Frequency band definitions
- Fatigue thresholds
- Alert levels and cooldowns
- Signal processing parameters
- Visualization settings
- ML model paths

## Usage Modes

1. **Production Mode**: Connect to actual TGAM1 device
   ```bash
   python main.py
   ```

2. **Demo Mode**: Test without hardware using simulated data
   ```bash
   python demo_mode.py
   ```

## Dependencies

- **numpy**: Numerical computations
- **scipy**: Signal processing and FFT
- **pandas**: Data manipulation
- **scikit-learn**: Machine learning
- **matplotlib**: Visualization
- **pyserial**: Serial/Bluetooth communication
- **joblib**: Model persistence

## Project Structure

```
project-code/
├── main.py                 # Main application
├── bluetooth_connector.py  # TGAM1 connectivity
├── signal_processor.py     # EEG signal processing
├── feature_extractor.py    # Feature extraction
├── ml_model.py            # ML fatigue detector
├── visualizer.py          # Real-time dashboard
├── alert_system.py        # Early warning alerts
├── config.py              # Configuration
├── demo_mode.py           # Demo/testing mode
├── requirements.txt       # Dependencies
├── README.md              # Project documentation
├── USAGE.md               # Usage guide
├── PROJECT_SUMMARY.md     # This file
└── models/                # Trained ML models
```

## Future Enhancements

Potential improvements for Phase 3:
1. **Data Logging**: Persistent storage of EEG data and alerts
2. **Historical Analysis**: Long-term trend analysis and reporting
3. **Personalization**: User-specific baseline adaptation
4. **Mobile App**: Android/iOS companion app
5. **Cloud Integration**: Remote monitoring and analytics
6. **Advanced ML**: Deep learning models for improved accuracy
7. **Multi-user Support**: Session management for multiple users
8. **Export Features**: CSV/JSON data export for research

## Research Applications

This system can be used for:
- Academic performance monitoring
- Workplace productivity optimization
- Safety-critical environment monitoring
- Mental health awareness
- Cognitive load assessment
- Burnout prevention research

## Authors

- **Pranesh** (22619153)
- **Aswin Sujin** (22619128)

**Internal Guide**: Dr. K. Ulagapriya, Associate Professor

## License

Academic project for Phase 2 - B.Tech CSE (AIML), Year IV, Semester VIII
