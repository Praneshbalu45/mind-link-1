import Foundation

// MARK: - All constants ported from config.py

enum Config {

    // MARK: Signal Processing
    static let sampleRate: Double = 512        // TGAM1 typical sample rate Hz
    static let windowSize: Int    = 256        // FFT window size
    static let overlap: Int       = 128        // Window overlap

    // MARK: Frequency Bands (Hz) — (low, high)
    static let frequencyBands: [(name: String, low: Double, high: Double)] = [
        ("delta", 0.5,  4.0),
        ("theta", 4.0,  8.0),
        ("alpha", 8.0, 13.0),
        ("beta",  13.0, 30.0),
        ("gamma", 30.0, 100.0),
    ]

    // MARK: Feature Window
    static let featureWindowSize: Int  = 10   // rolling samples for features
    static let baselineSamples: Int    = 30   // samples before baseline established

    // MARK: Fatigue Thresholds
    static let attentionLow:    Double = 40.0
    static let meditationLow:   Double = 30.0
    static let alphaHigh:       Double = 0.4
    static let betaLow:         Double = 0.2
    static let thetaHigh:       Double = 0.3
    static let driftThreshold:  Double = 0.15

    // MARK: Alert Levels (fatigue score cutoffs)
    static let alertLow:      Double = 0.10
    static let alertMedium:   Double = 0.20
    static let alertHigh:     Double = 0.30
    static let alertCritical: Double = 0.40

    // MARK: Alert Cooldowns (seconds)
    static let alertCooldownDefault:  TimeInterval = 300   // 5 min
    static let alertCooldownCritical: TimeInterval = 60    // 1 min
}
