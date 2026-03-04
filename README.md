<div align="center">

# 🧠 MindLink EEG

**Real-Time Mental Fatigue & Cognitive Monitoring — Native iPad App**

*Raw brainwaves → band powers → fatigue score → instant email alerts. Everything runs on-device.*

[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)](https://swift.org)
[![iPadOS](https://img.shields.io/badge/iPadOS-17+-black?logo=apple)](https://developer.apple.com)
[![Xcode](https://img.shields.io/badge/Xcode-15+-147EFB?logo=xcode&logoColor=white)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/License-MIT-brightgreen)](LICENSE)

</div>

---

## Overview

MindLink is a **native SwiftUI iPad application** that pairs with the NeuroSky TGAM1 EEG headset over Bluetooth Classic and gives you a complete real-time view of your cognitive state. The entire signal processing pipeline runs on-device using Apple's **Accelerate / vDSP** framework — no server, no cloud, no external services.

When your attention drops or fatigue builds, the app fires an **automatic email alert** directly via SMTP.

---

## Features

| Tab | Features |
|---|---|
| **Dashboard** | Live attention, meditation, fatigue · Cognitive drift · Calibration progress ring · Wellness score · Session record/stop |
| **Brain Waves** | 8 animated ring gauges (δ θ α-Lo α-Hi β-Lo β-Hi γ-Lo γ-Hi) · Dominant band card · Brain state interpretation · Live metric rings |
| **Sessions** | Record sessions · Wellness grade (A–F) · Session history · Per-session averages |
| **Raw Data** | ECG waveform (512 Hz live) · 8 live value cells · Band power bars with % · 8-item device test checklist |
| **Alerts** | Alert history log · Fatigue level timeline |
| **Settings** | Recipient email · Email toggles · Threshold sliders per metric · Cooldown control · Test email button |

---

## Architecture

```
NeuroSky TGAM1 Headset
        │ Bluetooth Classic (SPP/RFCOMM)
        ▼
  BluetoothManager  ──────────────────────────────────────────────
   │                                                              │
   ├─ TGAM1Parser                                                 │
   │    ├─ 0x80 RAW (512 Hz) ──→ rawEEGSamples ring buffer       │
   │    ├─ 0x83 EEG_POWER    ──→ 8 band powers (δθαβγ)          │
   │    ├─ 0x04 ATTENTION                                         │
   │    ├─ 0x05 MEDITATION                                        │
   │    └─ 0x02 POOR_SIGNAL                                       │
   │                                                              │
   ├─ SignalProcessor     (vDSP FFT, Hann window)                 │
   ├─ FeatureExtractor    (30-sample baseline, rolling stats)     │
   ├─ FatiguePredictor    (rule-based score 0–1)                  │
   └─ AlertSystem         (4-level cooldown-aware alerts)         │
                                                                  │
  AlertSettings                                                   │
   └─ SMTPSender  ─── smtp.hostinger.com:465 (SSL) ──→ Email     │
                                                                  │
  SessionManager  ──── wellness score, session history ───────────┘
  NotificationManager ── UNUserNotificationCenter (push)
```

---

## Fatigue Score

```
Score = (1 − attention/100)  × 0.30
      + (1 − meditation/100) × 0.20
      + min(alpha × 2, 1)    × 0.20   ← drowsy indicator
      + (1 − min(beta × 3, 1)) × 0.15 ← alertness indicator
      + min(theta × 3, 1)    × 0.15   ← drowsiness indicator

Levels:  ● Low < 0.10   ● Medium < 0.20   ● High < 0.30   ● Critical ≥ 0.30
```

---

## Email Alerts

Sent automatically via **SMTP** when a threshold is crossed:

- `⚠️ Low Attention` — attention drops below your set threshold
- `⚠️ High Stress` — meditation (calm) level is low
- `🔴 Fatigue Alert` — fatigue score exceeds your threshold

Configurable cooldown (default 5 min) prevents repeated notifications.

---

## Hardware Specs

| Spec | Value |
|---|---|
| Chip | NeuroSky TGAM1 |
| Protocol | ThinkGear — sync bytes 0xAA 0xAA |
| Band Powers | Code `0x83` · 8 bands · 24 bytes · ~1 Hz |
| Raw EEG | Code `0x80` · 512 Hz · 16-bit signed |
| Attention / Meditation | Codes `0x04` `0x05` · 0–100 |
| Connectivity | Bluetooth Classic 3.0 — SPP (RFCOMM) |
| Electrodes | 3 × forehead (EEG · GND · REF) |
| Battery | Li-ion 3.7V · 180 mAh · ~4–5 hr |

---

## Project Structure

```
MindLinkApp/
├── project.yml                          # XcodeGen project spec
└── MindLinkApp/
    ├── App/
    │   ├── MindLinkApp.swift            # @main entry point
    │   └── AppTheme.swift               # ← Change accent color here to retheme entire app
    │
    ├── Bluetooth/
    │   ├── BluetoothManager.swift       # CoreBluetooth + ExternalAccessory session
    │   └── TGAM1Parser.swift            # Binary frame decoder (0xAA 0xAA sync)
    │
    ├── Processing/
    │   ├── Config.swift                 # All constants & thresholds
    │   ├── SignalProcessor.swift        # vDSP FFT → band powers (Accelerate)
    │   ├── FeatureExtractor.swift       # Baseline calibration, drift, rolling stats
    │   ├── FatiguePredictor.swift       # Rule-based fatigue score
    │   ├── AlertSystem.swift            # 4-level cooldown-aware alert engine
    │   ├── AlertSettings.swift          # User thresholds persisted in UserDefaults
    │   ├── SessionManager.swift         # Session recording, wellness score, history
    │   └── GoogleSMTPSender.swift       # Hostinger SMTP client (Network.framework, port 465)
    │
    └── Views/
        ├── ContentView.swift            # 6-tab root + all shared state
        ├── BrainWavesView.swift         # 8 circular band ring gauges
        ├── RawDataView.swift            # ECG waveform + device test checklist
        ├── SessionHistoryView.swift     # Session list + wellness rings
        ├── AlertSettingsView.swift      # Email config + threshold sliders
        └── Components.swift             # Shared MetricCard, TrendChart, BandBarChart
```

---

## Getting Started

**Requirements:** Mac · Xcode 15+ · [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
# Install XcodeGen (once)
brew install xcodegen

# Generate the Xcode project
cd MindLinkApp
xcodegen generate

# Open in Xcode
open MindLinkApp.xcodeproj
```

1. Connect iPad via USB
2. Select your iPad as the run destination in Xcode
3. **Signing & Capabilities** → set your Team (free Apple ID works)
4. Press **▶ Run** (`⌘R`)
5. On your iPad: **Settings → Bluetooth** → pair MindLink device
6. Open the app → tap **Scan → Connect**
7. Wait ~30 seconds for calibration (collects 30-sample baseline)
8. Monitoring begins automatically

---

## Theming

The entire app uses **one accent color**. Edit a single line to retheme everything:

```swift
// App/AppTheme.swift
static let accent = Color(red: 0.22, green: 0.45, blue: 1.0)  // vivid blue
```

---

## Frameworks Used

| Framework | Purpose |
|---|---|
| `SwiftUI` | All UI and navigation |
| `CoreBluetooth` | BLE scanning |
| `ExternalAccessory` | RFCOMM stream (TGAM1 uses Classic BT) |
| `Accelerate / vDSP` | FFT and signal processing |
| `Charts` | ECG waveform, trend lines, bar charts |
| `Network` | SSL SMTP connection (port 465) |
| `UserNotifications` | On-device push alerts |
| `Combine` | `@Published` reactive data flow |

---

## Authors

| Name | Student ID |
|---|---|
| Pranesh | 22619153 |
| Aswin Sujin | 22619128 |

---

<div align="center">
<sub>Built with SwiftUI · Accelerate · Network.framework · NeuroSky TGAM1</sub>
</div>
