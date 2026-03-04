<div align="center">

# 🧠 MindLink EEG

### Real-Time Mental Fatigue & Cognitive Monitoring System

*A complete EEG pipeline — from raw brainwaves to intelligent alerts — running natively on iPad*

[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-17+-blue?logo=apple)](https://developer.apple.com/ios/)
[![Python](https://img.shields.io/badge/Python-3.10+-yellow?logo=python)](https://python.org)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

</div>

---

## ✨ Overview

MindLink is an EEG-based mental fatigue detection system that connects directly to the **NeuroSky TGAM1** headset and monitors your cognitive state in real time. It ships as both a **native iPad app** (SwiftUI) and a **Python server** for desktop use.

No cloud. No external server. The entire pipeline — signal processing, feature extraction, fatigue scoring, and alerting — runs on-device.

---

## 📱 iPad App — Features

<table>
<tr>
<td width="50%">

**Dashboard**
- Live attention & meditation scores
- Fatigue score gauge (0–1)
- Cognitive drift indicator
- α/β and θ/α frequency ratios
- Real-time trend charts

**Brain Waves**
- 8 animated circular ring gauges
- δ Delta · θ Theta · α Low/High
- β Low/High · γ Low/High
- Dominant band detection
- Brain state interpretation

**Sessions**
- Record study/work sessions
- Wellness score (A–F grade)
- Session history with stats
- Per-session alert count

</td>
<td width="50%">

**Raw Data**
- Real-time ECG-style waveform (512 Hz)
- All 8 TGAM1 band powers
- Packet rate & byte counter
- Device test checklist (8 checks)

**Alerts**
- Fatigue alert history
- Low · Medium · High · Critical levels
- Cognitive drift escalation

**Settings**
- Custom attention/meditation thresholds
- Email alerts via Apple Mail
- iOS push notifications
- Alert cooldown control

</td>
</tr>
</table>

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         iPad App (Swift)                        │
│                                                                 │
│  TGAM1 ──BT──▶ BluetoothManager ──▶ TGAM1Parser               │
│                     │                    │                      │
│                     ▼                    ▼                      │
│              SignalProcessor        Raw Ring Buffer             │
│            (vDSP FFT / Accelerate)  (512 samples, 20fps)       │
│                     │                                           │
│                     ▼                                           │
│           FeatureExtractor ──▶ FatiguePredictor                │
│           (baseline · drift ·    (rule-based score)            │
│            rolling stats)              │                        │
│                     │                  ▼                        │
│                     └──────────▶ AlertSystem                   │
│                                   │        │                    │
│                            In-App │   Push │  Email            │
│                            Banner │  (UNS) │  (MFMail)         │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🧬 EEG Pipeline (Ported from Python → Swift)

| Python Module | Swift Equivalent | What it does |
|---|---|---|
| `signal_processor.py` | `SignalProcessor.swift` | Hann window FFT → band powers (Accelerate / vDSP) |
| `feature_extractor.py` | `FeatureExtractor.swift` | Baseline calibration, rolling stats, cognitive drift |
| `ml_model.py` | `FatiguePredictor.swift` | Rule-based fatigue score (GBR fallback from Python) |
| `alert_system.py` | `AlertSystem.swift` | Cooldown-aware alerts with level escalation |
| `config.py` | `Config.swift` | All thresholds & constants |

> **Note on ML model:** The Python implementation uses `GradientBoostingRegressor` (scikit-learn).
> Since sklearn can't run on iOS, we port the identical `_rule_based_predict` fallback — results are the same since no pre-trained model is loaded.

---

## ⚡ Fatigue Score Formula

```
Fatigue = (1 − attention/100) × 0.30
        + (1 − meditation/100) × 0.20
        + min(alpha × 2, 1)    × 0.20   ← high alpha → drowsy
        + (1 − min(beta×3, 1)) × 0.15   ← low beta → less alert
        + min(theta × 3, 1)    × 0.15   ← high theta → drowsy

Level:  Low < 0.10 · Medium < 0.20 · High < 0.30 · Critical ≥ 0.30
```

---

## 📁 Project Structure

```
mind-link-1/
│
├── 📱 MindLinkApp/                     # Native iPad Xcode project
│   ├── project.yml                     # XcodeGen spec
│   └── MindLinkApp/
│       ├── App/
│       │   ├── MindLinkApp.swift       # App entry point
│       │   └── Info.plist
│       ├── Bluetooth/
│       │   ├── BluetoothManager.swift  # CoreBluetooth + ExternalAccessory
│       │   └── TGAM1Parser.swift       # Binary packet parser (AA AA sync)
│       ├── Processing/
│       │   ├── Config.swift            # All constants & thresholds
│       │   ├── SignalProcessor.swift   # vDSP FFT, band powers
│       │   ├── FeatureExtractor.swift  # Baseline, drift, fatigue score
│       │   ├── FatiguePredictor.swift  # Rule-based prediction
│       │   ├── AlertSystem.swift       # Cooldown alert engine
│       │   ├── AlertSettings.swift     # Custom thresholds (UserDefaults)
│       │   └── SessionManager.swift    # Session recording & wellness score
│       └── Views/
│           ├── ContentView.swift       # 6-tab main view
│           ├── BrainWavesView.swift    # Circular band ring gauges
│           ├── RawDataView.swift       # ECG waveform + device test
│           ├── SessionHistoryView.swift# Session list + wellness rings
│           ├── AlertSettingsView.swift # Email + threshold sliders
│           └── Components.swift       # Shared chart & card components
│
├── 🐍 Python Server (optional desktop fallback)
│   ├── main.py                        # Entry point
│   ├── web_server.py                  # Flask web dashboard
│   ├── bluetooth_connector.py         # PyBluez RFCOMM connector
│   ├── signal_processor.py            # NumPy/SciPy FFT pipeline
│   ├── feature_extractor.py           # Feature computation
│   ├── ml_model.py                    # GBR + rule-based fallback
│   ├── alert_system.py                # Alert engine
│   ├── config.py                      # Configuration
│   └── requirements.txt
│
└── 📊 static/
    └── index.html                     # Web dashboard (served by Flask)
```

---

## 🔌 Hardware

| Spec | Value |
|---|---|
| **Chipset** | NeuroSky TGAM1 |
| **Protocol** | ThinkGear (AA AA sync bytes) |
| **Baud Rate** | 57,600 |
| **Connectivity** | Bluetooth Classic 3.0 (SPP/RFCOMM) |
| **Electrodes** | 3 × forehead (EEG · GND · REF) |
| **Sample Rate** | 512 Hz raw EEG |
| **Band Output** | ~1 Hz (8 bands: δ θ α-lo α-hi β-lo β-hi γ-lo γ-hi) |
| **Battery** | Li-ion 3.7V 180 mAh |
| **Run Time** | 4–5 hours |

---

## 🚀 Getting Started

### iPad App

**Requirements:** Mac with Xcode 15+, XcodeGen, free Apple ID

```bash
# Install XcodeGen (once)
brew install xcodegen

# Generate Xcode project
cd MindLinkApp && xcodegen generate

# Open in Xcode
open MindLinkApp.xcodeproj
```

1. Connect iPad via USB  
2. In Xcode → select your iPad as destination  
3. Signing & Capabilities → set your Team (free Apple ID works)  
4. Press **▶ Run** (⌘R)  
5. On iPad: Settings → Bluetooth → pair MindLink  
6. Open app → tap **Scan** → connect → calibrate for 30 seconds

### Python Server (optional)

```bash
pip install -r requirements.txt
python main.py
# Visit http://<your-mac-ip>:5000 from any browser on the same network
```

---

## 📡 How the App Connects to MindLink

```
iPad Settings → Bluetooth: pair MindLink (Classic BT)
         ↓
ExternalAccessory framework (EASession, protocol: com.neurosky.thinkgear)
         ↓
StreamDelegate reads RFCOMM bytes → TGAM1Parser finds AA AA sync frames
         ↓
Checksum-validated packets → BluetoothManager → EEG Pipeline
```

> **Calibration:** The app collects 30 packets (~30 seconds) to establish your personal baseline before fatigue scoring begins.

---

## 👥 Authors

| Name | Student ID |
|---|---|
| Pranesh | 22619153 |
| Aswin Sujin | 22619128 |

---

<div align="center">
<sub>Built with ❤️ using Swift, SwiftUI, Accelerate, and NeuroSky TGAM1</sub>
</div>
