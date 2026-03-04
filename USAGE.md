# Usage Guide

## Installation

1. Install Python 3.8 or higher
2. Install required packages:
```bash
pip install -r requirements.txt
```

## Hardware Setup

1. **Power on the TGAM1 EEG sensor**
   - Ensure the device is fully charged (1.5 hours charging time)
   - Battery life: 4-5 hours of continuous operation

2. **Pair Bluetooth device**
   - On Windows: Go to Settings > Devices > Bluetooth
   - Pair the TGAM1 device
   - Note the COM port assigned (e.g., COM3, COM4)

3. **Connect via USB (if needed)**
   - Some systems may require USB connection for initial pairing
   - Use laptop USB port (5V) only

## Running the Application

1. **Start the application:**
```bash
python main.py
```

2. **Connect to device:**
   - Enter the COM port (or leave blank for auto-detection)
   - Click "Connect" button
   - Wait for "Connected" status

3. **Start monitoring:**
   - Click "Start Monitoring" button
   - The visualization window will open automatically
   - System will establish baseline for 60 seconds
   - After baseline, real-time monitoring begins

## Understanding the Dashboard

### Status Panel
- **Status**: Connection and monitoring status
- **Attention**: Current attention level (0-100)
- **Meditation**: Current meditation level (0-100)
- **Fatigue Score**: Current fatigue level (0-1, color-coded)

### Visualization Plots

1. **Attention & Meditation**
   - Real-time plot of attention and meditation values
   - Higher values indicate better cognitive state

2. **Frequency Band Powers**
   - Alpha (8-13 Hz): Relaxation, drowsiness indicator
   - Beta (13-30 Hz): Active thinking, alertness
   - Theta (4-8 Hz): Drowsiness, light sleep
   - Delta (0.5-4 Hz): Deep sleep
   - Gamma (30-100 Hz): Cognitive processing

3. **Fatigue Score**
   - Real-time fatigue level (0-1)
   - Orange line: Warning threshold (0.4)
   - Red line: Critical threshold (0.7)

4. **Alpha/Beta Ratio**
   - Higher ratio indicates relaxation/fatigue
   - Lower ratio indicates alertness

5. **Cognitive Drift**
   - Deviation from baseline cognitive patterns
   - Red line: Alert threshold (0.15)

6. **Frequency Band Distribution**
   - Current power distribution across bands
   - Bar chart showing relative power

## Alert System

The system provides four levels of alerts:

- **LOW**: Early signs of fatigue (score > 0.1)
- **MEDIUM**: Moderate fatigue (score > 0.2)
- **HIGH**: Significant fatigue (score > 0.3) - Break recommended
- **CRITICAL**: Severe fatigue (score > 0.4) - Immediate rest needed

Alerts are triggered when:
- Fatigue score exceeds thresholds
- Cognitive drift exceeds 0.15
- Attention drops below 40
- Meditation drops below 30

## Best Practices

1. **Baseline Establishment**
   - Sit comfortably in a quiet environment
   - Keep the device on for the full 60-second baseline period
   - Avoid movement during baseline

2. **Monitoring Session**
   - Typical sessions: 30-60 minutes
   - Take breaks when alerts are triggered
   - Monitor trends over time

3. **Device Care**
   - Clean electrodes before use
   - Ensure good contact with forehead
   - Charge device after each session

## Troubleshooting

### Connection Issues
- **Device not found**: Check Bluetooth pairing, try different COM port
- **Connection timeout**: Ensure device is powered on and in range
- **Data not received**: Check baud rate (should be 57600)

### Data Quality Issues
- **Poor signal**: Adjust headband position, clean electrodes
- **Noisy data**: Move to quieter environment, reduce movement
- **Inconsistent readings**: Ensure stable connection, check battery level

### Performance Issues
- **Slow visualization**: Reduce PLOT_HISTORY_SIZE in config.py
- **High CPU usage**: Increase UPDATE_INTERVAL in config.py

## Advanced Configuration

Edit `config.py` to customize:
- Frequency band definitions
- Fatigue thresholds
- Alert levels and cooldowns
- Visualization parameters
- ML model settings

## Exporting Data

Data can be exported by modifying the code to save:
- Raw EEG samples
- Frequency band powers
- Feature vectors
- Fatigue scores
- Alert history

## Support

For issues or questions:
- Check logs in console output
- Review configuration in config.py
- Ensure all dependencies are installed correctly
