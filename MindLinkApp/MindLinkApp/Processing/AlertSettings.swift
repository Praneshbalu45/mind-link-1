import Foundation
import Combine

// MARK: - Alert Settings (persisted in UserDefaults)

class AlertSettings: ObservableObject {

    // ── Email ─────────────────────────────────────────────────────────────
    @Published var recipientEmail: String { didSet { save("recipientEmail", recipientEmail) } }
    @Published var emailEnabled: Bool     { didSet { save("emailEnabled",   emailEnabled)   } }

    // ── Attention ─────────────────────────────────────────────────────────
    @Published var attentionAlertEnabled: Bool   { didSet { save("attnAlertOn", attentionAlertEnabled) } }
    @Published var attentionThreshold: Double    { didSet { save("attnThresh",  attentionThreshold)   } }

    // ── Meditation ────────────────────────────────────────────────────────
    @Published var meditationAlertEnabled: Bool  { didSet { save("medAlertOn",  meditationAlertEnabled) } }
    @Published var meditationThreshold: Double   { didSet { save("medThresh",   meditationThreshold)   } }

    // ── Fatigue ───────────────────────────────────────────────────────────
    @Published var fatigueAlertEnabled: Bool     { didSet { save("fatAlertOn",  fatigueAlertEnabled) } }
    @Published var fatigueThreshold: Double      { didSet { save("fatThresh",   fatigueThreshold)   } }

    // ── Cooldown ──────────────────────────────────────────────────────────
    @Published var cooldownMinutes: Double        { didSet { save("cooldown",    cooldownMinutes)   } }

    // ── Status (UI feedback) ──────────────────────────────────────────────
    @Published var lastEmailStatus: String = ""
    @Published var isSendingEmail  = false

    private var lastAttentionAlert:  Date? = nil
    private var lastMeditationAlert: Date? = nil
    private var lastFatigueAlert:    Date? = nil

    init() {
        let ud = UserDefaults.standard
        recipientEmail           = ud.string(forKey: "recipientEmail") ?? ""
        emailEnabled             = ud.bool(forKey: "emailEnabled")
        attentionAlertEnabled    = ud.object(forKey: "attnAlertOn")    as? Bool   ?? false
        attentionThreshold       = ud.object(forKey: "attnThresh")     as? Double ?? 40
        meditationAlertEnabled   = ud.object(forKey: "medAlertOn")     as? Bool   ?? false
        meditationThreshold      = ud.object(forKey: "medThresh")      as? Double ?? 30
        fatigueAlertEnabled      = ud.object(forKey: "fatAlertOn")     as? Bool   ?? true
        fatigueThreshold         = ud.object(forKey: "fatThresh")      as? Double ?? 0.4
        cooldownMinutes          = ud.object(forKey: "cooldown")       as? Double ?? 5
    }

    // MARK: - Check thresholds

    struct CustomAlert {
        let type:    AlertType
        let subject: String
        let body:    String
    }
    enum AlertType { case attention, meditation, fatigue }

    func checkReading(_ r: EEGReading) -> [CustomAlert] {
        var out: [CustomAlert] = []
        let cd = cooldownMinutes * 60

        if attentionAlertEnabled && r.attention < attentionThreshold, canFire(&lastAttentionAlert, cooldown: cd) {
            out.append(CustomAlert(type: .attention,
                subject: "⚠️ Low Attention — MindLink",
                body: """
                Your attention level dropped below your threshold.
                
                Current:   \(Int(r.attention)) / 100
                Threshold: below \(Int(attentionThreshold))
                
                Take a short break or refocus your task.
                — MindLink EEG Monitor
                """))
            lastAttentionAlert = Date()
        }
        if meditationAlertEnabled && r.meditation < meditationThreshold, canFire(&lastMeditationAlert, cooldown: cd) {
            out.append(CustomAlert(type: .meditation,
                subject: "⚠️ High Stress — MindLink",
                body: """
                Your meditation (calm) level is low — stress detected.
                
                Current:   \(Int(r.meditation)) / 100
                Threshold: below \(Int(meditationThreshold))
                
                Try deep breathing for 2 minutes.
                — MindLink EEG Monitor
                """))
            lastMeditationAlert = Date()
        }
        if fatigueAlertEnabled && r.fatigueScore > fatigueThreshold, canFire(&lastFatigueAlert, cooldown: cd) {
            out.append(CustomAlert(type: .fatigue,
                subject: "🔴 \(r.fatigueLevel.rawValue) Fatigue — MindLink",
                body: """
                Fatigue level: \(r.fatigueLevel.rawValue)
                
                Fatigue score:    \(String(format: "%.2f", r.fatigueScore)) / 1.0
                Cognitive drift:  \(String(format: "%.3f", r.cognitiveDrift))
                Threshold:        above \(String(format: "%.1f", fatigueThreshold))
                
                Please rest. Sustained fatigue reduces performance.
                — MindLink EEG Monitor
                """))
            lastFatigueAlert = Date()
        }
        return out
    }

    // MARK: - SMTP Send

    func sendEmail(subject: String, body: String) {
        guard emailEnabled, !recipientEmail.isEmpty else { return }
        isSendingEmail  = true
        lastEmailStatus = "Sending…"
        Task {
            do {
                try await SMTPSender.shared.send(
                    to:      recipientEmail,
                    subject: subject,
                    body:    body
                )
                await MainActor.run {
                    self.lastEmailStatus = "✓ Sent at \(timeStr())"
                    self.isSendingEmail  = false
                }
            } catch {
                await MainActor.run {
                    self.lastEmailStatus = "✗ Failed: \(error.localizedDescription)"
                    self.isSendingEmail  = false
                }
            }
        }
    }

    // MARK: - Helpers

    private func canFire(_ last: inout Date?, cooldown: Double) -> Bool {
        guard let l = last else { return true }
        return Date().timeIntervalSince(l) >= cooldown
    }
    private func timeStr() -> String {
        let f = DateFormatter(); f.timeStyle = .short; return f.string(from: Date())
    }
    private func save(_ key: String, _ val: Any) { UserDefaults.standard.set(val, forKey: key) }
    private func str(_ key: String)              -> String { UserDefaults.standard.string(forKey: key) ?? "" }
    private func bool(_ key: String)             -> Bool   { UserDefaults.standard.bool(forKey: key) }
    private func bool2(_ key: String, def: Bool = false) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? def
    }
    private func dbl(_ key: String, def: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? def
    }
}
