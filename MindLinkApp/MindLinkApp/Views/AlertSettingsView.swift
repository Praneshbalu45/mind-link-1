import SwiftUI

// MARK: - Alert Settings View

struct AlertSettingsView: View {
    @ObservedObject var bt: BluetoothManager
    @ObservedObject var alertSettings: AlertSettings

    var body: some View {
        Form {

            // ── Google SMTP Section ──────────────────────────────────────
            Section {
                HStack {
                    Image(systemName: "envelope").foregroundColor(AppTheme.accent)
                    Text("Alert Recipient Email")
                    Spacer()
                    TextField("recipient@email.com", text: $alertSettings.recipientEmail)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Toggle(isOn: $alertSettings.emailEnabled) {
                    Label("Enable Email Alerts", systemImage: "bell.badge")
                }
            } header: {
                Label("Email Alerts", systemImage: "envelope.fill")
            } footer: {
                Text("Enter the email address where you want to receive EEG alerts.")
                    .font(.caption).foregroundColor(.secondary)
            }

            // ── SMTP Status / Test ───────────────────────────────────────
            Section {
                Button {
                    alertSettings.sendEmail(
                        subject: "MindLink — Test Email",
                        body: """
                        This is a test email from your MindLink EEG app.
                        
                        Current readings:
                        • Attention:  \(bt.latestReading.map { "\(Int($0.attention))" } ?? "N/A")
                        • Meditation: \(bt.latestReading.map { "\(Int($0.meditation))" } ?? "N/A")
                        • Fatigue:    \(bt.latestReading.map { String(format: "%.2f", $0.fatigueScore) } ?? "N/A")
                        
                        — MindLink EEG Monitor
                        """
                    )
                } label: {
                    HStack {
                        Label("Send Test Email", systemImage: "paperplane")
                        Spacer()
                        if alertSettings.isSendingEmail {
                            ProgressView().scaleEffect(0.7)
                        }
                    }
                }
                .disabled(alertSettings.isSendingEmail ||
                          alertSettings.gmailSender.isEmpty ||
                          alertSettings.gmailAppPassword.isEmpty ||
                          alertSettings.recipientEmail.isEmpty)

                if !alertSettings.lastEmailStatus.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: alertSettings.lastEmailStatus.hasPrefix("✓") ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(alertSettings.lastEmailStatus.hasPrefix("✓") ? .green : .red)
                        Text(alertSettings.lastEmailStatus).font(.caption)
                    }
                }
            } header: {
                Label("Test", systemImage: "paperplane.fill")
            }

            // ── Attention Threshold ──────────────────────────────────────
            Section {
                Toggle(isOn: $alertSettings.attentionAlertEnabled) {
                    Label("Attention Alert", systemImage: "eye")
                }
                if alertSettings.attentionAlertEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Alert when below:")
                            Spacer()
                            Text("\(Int(alertSettings.attentionThreshold))")
                                .fontWeight(.bold).foregroundColor(.blue)
                        }
                        Slider(value: $alertSettings.attentionThreshold, in: 10...90, step: 5).tint(.blue)
                    }
                    liveBadge(current: bt.latestReading?.attention,
                              threshold: alertSettings.attentionThreshold,
                              label: "Attention", trigger: .below)
                }
            } header: { Label("Attention", systemImage: "brain.head.profile") }

            // ── Meditation Threshold ─────────────────────────────────────
            Section {
                Toggle(isOn: $alertSettings.meditationAlertEnabled) {
                    Label("Meditation Alert", systemImage: "figure.mind.and.body")
                }
                if alertSettings.meditationAlertEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Alert when below:")
                            Spacer()
                            Text("\(Int(alertSettings.meditationThreshold))")
                                .fontWeight(.bold).foregroundColor(.green)
                        }
                        Slider(value: $alertSettings.meditationThreshold, in: 10...90, step: 5).tint(.green)
                    }
                    liveBadge(current: bt.latestReading?.meditation,
                              threshold: alertSettings.meditationThreshold,
                              label: "Meditation", trigger: .below)
                }
            } header: { Label("Meditation", systemImage: "waveform.path") }

            // ── Fatigue Threshold ────────────────────────────────────────
            Section {
                Toggle(isOn: $alertSettings.fatigueAlertEnabled) {
                    Label("Fatigue Alert", systemImage: "exclamationmark.triangle")
                }
                if alertSettings.fatigueAlertEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Alert when above:")
                            Spacer()
                            Text(String(format: "%.1f", alertSettings.fatigueThreshold))
                                .fontWeight(.bold).foregroundColor(.orange)
                        }
                        Slider(value: $alertSettings.fatigueThreshold, in: 0.1...0.9, step: 0.05).tint(.orange)
                    }
                }
            } header: { Label("Fatigue", systemImage: "bolt.trianglebadge.exclamationmark") }

            // ── Cooldown ─────────────────────────────────────────────────
            Section {
                HStack {
                    Text("Cooldown between alerts")
                    Spacer()
                    Text("\(Int(alertSettings.cooldownMinutes)) min").foregroundColor(.secondary)
                }
                Slider(value: $alertSettings.cooldownMinutes, in: 1...30, step: 1).tint(.purple)
            } header: { Label("Cooldown", systemImage: "clock") }
            footer: { Text("Minimum time between repeated alerts for the same metric.") }
        }
        .navigationTitle("Alert Settings")
    }

    // MARK: - Live threshold badge

    enum TriggerDirection { case above, below }

    @ViewBuilder
    private func liveBadge(current: Double?, threshold: Double, label: String, trigger: TriggerDirection) -> some View {
        if let cur = current {
            let triggered = trigger == .below ? cur < threshold : cur > threshold
            HStack(spacing: 6) {
                Image(systemName: triggered ? "bell.fill" : "bell.slash")
                    .foregroundColor(triggered ? .red : .green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Current \(label): \(Int(cur))")
                        .font(.caption).fontWeight(.semibold)
                    Text(triggered ? "Currently below threshold — would fire" : "Currently above threshold — OK")
                        .font(.caption2).foregroundColor(triggered ? .red : .green)
                }
            }
            .padding(8)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
