import SwiftUI
import MessageUI

// MARK: - Alert Settings View

struct AlertSettingsView: View {
    @ObservedObject var bt: BluetoothManager
    @ObservedObject var alertSettings: AlertSettings

    @State private var showMailComposer = false
    @State private var mailResult: MailComposerView.MailResult? = nil
    @State private var testAlertType: TestAlertType? = nil

    enum TestAlertType: Identifiable {
        case attention, meditation
        var id: Int { self == .attention ? 0 : 1 }
    }

    var body: some View {
        Form {
            // ── Email Configuration ──────────────────────────────────────
            Section {
                HStack {
                    Image(systemName: "envelope.fill").foregroundColor(.blue)
                    TextField("your@email.com", text: $alertSettings.email)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Toggle(isOn: $alertSettings.emailEnabled) {
                    Label("Email Alerts", systemImage: "bell.badge.fill")
                }
                if !MFMailComposeViewController.canSendMail() {
                    Label("Mail app not configured on this device", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundColor(.orange)
                }
            } header: {
                Label("Email Notifications", systemImage: "envelope")
            } footer: {
                Text("Alerts open Apple Mail to send when thresholds are crossed.")
            }

            // ── Attention Alert ──────────────────────────────────────────
            Section {
                Toggle(isOn: $alertSettings.attentionAlertEnabled) {
                    Label("Attention Alert", systemImage: "eye")
                }
                if alertSettings.attentionAlertEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Alert when below:")
                            Spacer()
                            Text("\(Int(alertSettings.attentionThreshold))")
                                .font(.system(.body, design: .rounded)).fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        Slider(value: $alertSettings.attentionThreshold, in: 10...90, step: 5)
                            .tint(.blue)
                        HStack {
                            Text("10 (very low)")
                                .font(.caption2).foregroundColor(.secondary)
                            Spacer()
                            Text("90 (high)")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    thresholdInfo(
                        current: bt.latestReading?.attention,
                        threshold: alertSettings.attentionThreshold,
                        label: "Attention",
                        color: .blue
                    )
                }
            } header: {
                Label("Attention Threshold", systemImage: "brain.head.profile")
            }

            // ── Meditation Alert ─────────────────────────────────────────
            Section {
                Toggle(isOn: $alertSettings.meditationAlertEnabled) {
                    Label("Meditation Alert", systemImage: "figure.mind.and.body")
                }
                if alertSettings.meditationAlertEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Alert when below:")
                            Spacer()
                            Text("\(Int(alertSettings.meditationThreshold))")
                                .font(.system(.body, design: .rounded)).fontWeight(.bold)
                                .foregroundColor(.green)
                        }
                        Slider(value: $alertSettings.meditationThreshold, in: 10...90, step: 5)
                            .tint(.green)
                        HStack {
                            Text("10 (very low)")
                                .font(.caption2).foregroundColor(.secondary)
                            Spacer()
                            Text("90 (high)")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    thresholdInfo(
                        current: bt.latestReading?.meditation,
                        threshold: alertSettings.meditationThreshold,
                        label: "Meditation",
                        color: .green
                    )
                }
            } header: {
                Label("Meditation Threshold", systemImage: "waveform.path")
            }

            // ── Fatigue Alert ─────────────────────────────────────────────
            Section {
                Toggle(isOn: $alertSettings.fatigueAlertEnabled) {
                    Label("Fatigue Alert", systemImage: "exclamationmark.triangle")
                }
                if alertSettings.fatigueAlertEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Alert when above:")
                            Spacer()
                            Text(String(format: "%.1f", alertSettings.fatigueThreshold))
                                .font(.system(.body, design: .rounded)).fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                        Slider(value: $alertSettings.fatigueThreshold, in: 0.1...0.9, step: 0.05)
                            .tint(.orange)
                        HStack {
                            Text("0.1 (early warning)")
                                .font(.caption2).foregroundColor(.secondary)
                            Spacer()
                            Text("0.9 (critical)")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Label("Fatigue Threshold", systemImage: "bolt.trianglebadge.exclamationmark")
            }

            // ── Test Email ───────────────────────────────────────────────
            Section {
                Button {
                    testAlertType = .attention
                    showMailComposer = true
                } label: {
                    Label("Send Test Email", systemImage: "paperplane.fill")
                }
                .disabled(!MFMailComposeViewController.canSendMail() || alertSettings.email.isEmpty)

                if let result = mailResult {
                    switch result {
                    case .sent:
                        Label("Email sent successfully ✓", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green).font(.caption)
                    case .cancelled:
                        Label("Email cancelled", systemImage: "xmark.circle")
                            .foregroundColor(.secondary).font(.caption)
                    case .failed(let e):
                        Label("Failed: \(e)", systemImage: "exclamationmark.circle")
                            .foregroundColor(.red).font(.caption)
                    }
                }
            } header: {
                Label("Test Alert", systemImage: "paperplane")
            }

            // ── Alert Cooldown ───────────────────────────────────────────
            Section {
                HStack {
                    Text("Cooldown between alerts")
                    Spacer()
                    Text("\(Int(alertSettings.cooldownMinutes)) min")
                        .foregroundColor(.secondary)
                }
                Slider(value: $alertSettings.cooldownMinutes, in: 1...30, step: 1)
                    .tint(.purple)
            } header: {
                Label("Cooldown", systemImage: "clock")
            } footer: {
                Text("Minimum time between repeated alerts for the same metric.")
            }
        }
        .navigationTitle("Alert Settings")
        .sheet(isPresented: $showMailComposer) {
            if MFMailComposeViewController.canSendMail() {
                MailComposerView(
                    toEmail: alertSettings.email,
                    subject: "MindLink Alert — Test",
                    body: """
                    This is a test alert from your MindLink EEG app.
                    
                    Current readings:
                    • Attention:  \(bt.latestReading.map { "\(Int($0.attention))" } ?? "N/A")
                    • Meditation: \(bt.latestReading.map { "\(Int($0.meditation))" } ?? "N/A")
                    • Fatigue:    \(bt.latestReading.map { String(format: "%.2f", $0.fatigueScore) } ?? "N/A")
                    
                    Thresholds configured:
                    • Attention alert below: \(Int(alertSettings.attentionThreshold))
                    • Meditation alert below: \(Int(alertSettings.meditationThreshold))
                    • Fatigue alert above: \(String(format: "%.1f", alertSettings.fatigueThreshold))
                    
                    Sent from MindLink EEG Monitor for iPad.
                    """,
                    result: $mailResult
                )
            }
        }
    }

    @ViewBuilder
    private func thresholdInfo(current: Double?, threshold: Double, label: String, color: Color) -> some View {
        HStack(spacing: 8) {
            if let val = current {
                let triggered = val < threshold
                Image(systemName: triggered ? "bell.fill" : "bell.slash")
                    .foregroundColor(triggered ? .red : .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current \(label): \(Int(val))")
                        .font(.caption).fontWeight(.semibold)
                    Text(triggered ? "⚠ Below threshold — alert would fire!" : "✓ Above threshold — no alert")
                        .font(.caption2)
                        .foregroundColor(triggered ? .red : .green)
                }
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right").foregroundColor(.secondary)
                Text("Connect MindLink to see live value").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Mail Composer (MessageUI wrapper)

struct MailComposerView: UIViewControllerRepresentable {

    enum MailResult {
        case sent, cancelled, failed(String)
    }

    let toEmail: String
    let subject: String
    let body: String
    @Binding var result: MailResult?

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([toEmail])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposerView
        init(_ parent: MailComposerView) { self.parent = parent }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true)
            switch result {
            case .sent:      parent.result = .sent
            case .cancelled: parent.result = .cancelled
            case .failed:    parent.result = .failed(error?.localizedDescription ?? "Unknown error")
            default:         break
            }
        }
    }
}
