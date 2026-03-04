import Foundation
import Combine

// MARK: - Alert Settings (persisted in UserDefaults via @AppStorage equivalent)

class AlertSettings: ObservableObject {

    // Email
    @Published var email: String {
        didSet { UserDefaults.standard.set(email, forKey: "alertEmail") }
    }
    @Published var emailEnabled: Bool {
        didSet { UserDefaults.standard.set(emailEnabled, forKey: "alertEmailEnabled") }
    }

    // Attention
    @Published var attentionAlertEnabled: Bool {
        didSet { UserDefaults.standard.set(attentionAlertEnabled, forKey: "attentionAlertEnabled") }
    }
    @Published var attentionThreshold: Double {
        didSet { UserDefaults.standard.set(attentionThreshold, forKey: "attentionThreshold") }
    }

    // Meditation
    @Published var meditationAlertEnabled: Bool {
        didSet { UserDefaults.standard.set(meditationAlertEnabled, forKey: "meditationAlertEnabled") }
    }
    @Published var meditationThreshold: Double {
        didSet { UserDefaults.standard.set(meditationThreshold, forKey: "meditationThreshold") }
    }

    // Fatigue
    @Published var fatigueAlertEnabled: Bool {
        didSet { UserDefaults.standard.set(fatigueAlertEnabled, forKey: "fatigueAlertEnabled") }
    }
    @Published var fatigueThreshold: Double {
        didSet { UserDefaults.standard.set(fatigueThreshold, forKey: "fatigueThreshold") }
    }

    // Cooldown
    @Published var cooldownMinutes: Double {
        didSet { UserDefaults.standard.set(cooldownMinutes, forKey: "alertCooldownMinutes") }
    }

    // Last alert times (for cooldown)
    private var lastAttentionAlert: Date? = nil
    private var lastMeditationAlert: Date? = nil
    private var lastFatigueAlert: Date? = nil

    init() {
        email                  = UserDefaults.standard.string(forKey: "alertEmail") ?? ""
        emailEnabled           = UserDefaults.standard.bool(forKey: "alertEmailEnabled")
        attentionAlertEnabled  = UserDefaults.standard.object(forKey: "attentionAlertEnabled") as? Bool ?? false
        attentionThreshold     = UserDefaults.standard.object(forKey: "attentionThreshold")    as? Double ?? 40
        meditationAlertEnabled = UserDefaults.standard.object(forKey: "meditationAlertEnabled") as? Bool ?? false
        meditationThreshold    = UserDefaults.standard.object(forKey: "meditationThreshold")   as? Double ?? 30
        fatigueAlertEnabled    = UserDefaults.standard.object(forKey: "fatigueAlertEnabled")   as? Bool ?? true
        fatigueThreshold       = UserDefaults.standard.object(forKey: "fatigueThreshold")      as? Double ?? 0.4
        cooldownMinutes        = UserDefaults.standard.object(forKey: "alertCooldownMinutes")  as? Double ?? 5
    }

    // MARK: - Check reading against custom thresholds

    struct CustomAlert {
        let type:    AlertType
        let subject: String
        let body:    String
    }

    enum AlertType { case attention, meditation, fatigue }

    func checkReading(_ reading: EEGReading) -> [CustomAlert] {
        var triggered: [CustomAlert] = []
        let cooldown = cooldownMinutes * 60

        if attentionAlertEnabled && reading.attention < attentionThreshold {
            if canFire(&lastAttentionAlert, cooldown: cooldown) {
                triggered.append(CustomAlert(
                    type: .attention,
                    subject: "⚠️ Low Attention Alert",
                    body: """
                    Your MindLink app detected low attention.

                    Current attention level: \(Int(reading.attention)) / 100
                    Your threshold: below \(Int(attentionThreshold))

                    Consider taking a short break or refocusing your task.

                    — MindLink EEG Monitor
                    """
                ))
                lastAttentionAlert = Date()
            }
        }

        if meditationAlertEnabled && reading.meditation < meditationThreshold {
            if canFire(&lastMeditationAlert, cooldown: cooldown) {
                triggered.append(CustomAlert(
                    type: .meditation,
                    subject: "⚠️ Low Meditation Alert",
                    body: """
                    Your MindLink app detected low meditation (high stress).

                    Current meditation level: \(Int(reading.meditation)) / 100
                    Your threshold: below \(Int(meditationThreshold))

                    Try deep breathing or a short mindfulness exercise.

                    — MindLink EEG Monitor
                    """
                ))
                lastMeditationAlert = Date()
            }
        }

        if fatigueAlertEnabled && reading.fatigueScore > fatigueThreshold {
            if canFire(&lastFatigueAlert, cooldown: cooldown) {
                let level = reading.fatigueLevel.rawValue
                triggered.append(CustomAlert(
                    type: .fatigue,
                    subject: "🔴 \(level) Fatigue Alert",
                    body: """
                    Your MindLink app detected \(level.lowercased()) fatigue.

                    Fatigue score: \(String(format: "%.2f", reading.fatigueScore)) / 1.0
                    Cognitive drift: \(String(format: "%.3f", reading.cognitiveDrift))
                    Your threshold: above \(String(format: "%.1f", fatigueThreshold))

                    Please take a break. Adequate rest improves performance and wellbeing.

                    — MindLink EEG Monitor
                    """
                ))
                lastFatigueAlert = Date()
            }
        }

        return triggered
    }

    private func canFire(_ last: inout Date?, cooldown: Double) -> Bool {
        guard let l = last else { return true }
        return Date().timeIntervalSince(l) >= cooldown
    }
}
