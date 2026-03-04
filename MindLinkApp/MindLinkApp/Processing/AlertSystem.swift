import Foundation

// MARK: - Alert

struct EEGAlert: Identifiable {
    let id = UUID()
    let level: AlertLevel
    let message: String
    let fatigueScore: Double
    let cognitiveDrift: Double
    let timestamp: Date
}

enum AlertLevel: String, CaseIterable {
    case low      = "low"
    case medium   = "medium"
    case high     = "high"
    case critical = "critical"

    var displayTitle: String {
        switch self {
        case .low:      return "Early Fatigue"
        case .medium:   return "Moderate Fatigue"
        case .high:     return "High Fatigue"
        case .critical: return "Critical Fatigue"
        }
    }

    var cooldown: TimeInterval {
        self == .critical ? Config.alertCooldownCritical : Config.alertCooldownDefault
    }

    var fatigueThreshold: Double {
        switch self {
        case .low:      return Config.alertLow
        case .medium:   return Config.alertMedium
        case .high:     return Config.alertHigh
        case .critical: return Config.alertCritical
        }
    }
}

// MARK: - AlertSystem (port of alert_system.py)

class AlertSystem {

    private var lastAlertTime: [AlertLevel: Date] = [:]
    private(set) var alertHistory: [EEGAlert] = []

    var onAlert: ((EEGAlert) -> Void)?

    // MARK: - Check Alerts

    @discardableResult
    func checkAlerts(features: EEGFeatures, prediction: PredictionResult) -> EEGAlert? {
        let score = prediction.fatigueScore
        let drift = prediction.cognitiveDrift
        let attn  = features.attentionMean
        let med   = features.meditationMean

        // Determine highest triggered level
        var level: AlertLevel? = nil
        var message = ""

        if score >= Config.alertCritical {
            level = .critical
            message = "CRITICAL: Severe mental fatigue detected! Immediate rest recommended."
        } else if score >= Config.alertHigh {
            level = .high
            message = "HIGH: Significant mental fatigue detected. Consider taking a break."
        } else if score >= Config.alertMedium {
            level = .medium
            message = "MEDIUM: Moderate fatigue detected. Monitor your cognitive state."
        } else if score >= Config.alertLow {
            level = .low
            message = "LOW: Early signs of fatigue detected. Stay aware."
        }

        // Cognitive drift escalation
        if drift > Config.driftThreshold {
            if level == nil || level == .low || level == .medium { level = .high }
            let driftStr = String(format: "%.2f", drift)
            message += message.isEmpty
                ? "Warning: Significant cognitive drift (\(driftStr))"
                : " Cognitive drift: \(driftStr)"
        }

        // Low attention
        if attn < Config.attentionLow, let lv = level, lv != .critical, lv != .high {
            let attnStr = String(format: "%.1f", attn)
            message += " Low attention: \(attnStr)"
        }

        // Low meditation
        if med < Config.meditationLow, let lv = level, lv != .critical, lv != .high {
            let medStr = String(format: "%.1f", med)
            message += " Low meditation: \(medStr)"
        }

        guard let alertLevel = level, shouldTrigger(alertLevel) else { return nil }

        let alert = EEGAlert(
            level: alertLevel,
            message: message,
            fatigueScore: score,
            cognitiveDrift: drift,
            timestamp: Date()
        )

        lastAlertTime[alertLevel] = Date()
        alertHistory.append(alert)
        if alertHistory.count > 100 { alertHistory.removeFirst() }

        onAlert?(alert)
        return alert
    }

    // MARK: - Cooldown check

    private func shouldTrigger(_ level: AlertLevel) -> Bool {
        guard let last = lastAlertTime[level] else { return true }
        return Date().timeIntervalSince(last) > level.cooldown
    }

    func reset() {
        lastAlertTime.removeAll()
        alertHistory.removeAll()
    }
}
