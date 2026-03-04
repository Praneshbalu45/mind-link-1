import SwiftUI
import Charts
import MessageUI

struct ContentView: View {
    @StateObject private var bt             = BluetoothManager()
    @StateObject private var alertSettings  = AlertSettings()
    @StateObject private var sessionManager = SessionManager()

    @State private var history:        [EEGReading] = []
    @State private var alertDismissed  = false
    @State private var showDevicePicker = false
    @State private var selectedTab     = 0
    @State private var pendingMail:    AlertSettings.CustomAlert? = nil
    @State private var showMail        = false
    @State private var mailResult:     MailComposerView.MailResult? = nil

    private let maxHistory = 120

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()

                TabView(selection: $selectedTab) {
                    dashboardTab
                        .tabItem { Label("Dashboard",   systemImage: "waveform.path.ecg") }.tag(0)
                    BrainWavesView(bt: bt)
                        .tabItem { Label("Brain Waves", systemImage: "brain") }.tag(1)
                    SessionHistoryView(session: sessionManager, bt: bt)
                        .tabItem { Label("Sessions",    systemImage: "chart.bar.doc.horizontal") }.tag(2)
                    RawDataView(bt: bt)
                        .tabItem { Label("Raw Data",    systemImage: "waveform") }.tag(3)
                    alertTab
                        .tabItem { Label("Alerts",      systemImage: bt.alertHistory.isEmpty ? "bell" : "bell.badge") }.tag(4)
                    NavigationStack {
                        AlertSettingsView(bt: bt, alertSettings: alertSettings)
                    }
                    .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(5)
                }
            }
            .navigationTitle("MindLink EEG")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { connectionButton }
            }
            .sheet(isPresented: $showDevicePicker) {
                DevicePickerSheet(bt: bt, isPresented: $showDevicePicker)
            }
            .sheet(isPresented: $showMail) {
                if let alert = pendingMail {
                    MailComposerView(toEmail: alertSettings.email,
                                     subject: alert.subject, body: alert.body,
                                     result: $mailResult)
                }
            }
        }
        .onAppear {
            NotificationManager.shared.requestPermission()
            sessionManager.loadHistory()
        }
        .onChange(of: bt.latestReading) { _, r in
            guard let r else { return }
            history.append(r)
            if history.count > maxHistory { history.removeFirst() }
            if bt.alertMessage != nil { alertDismissed = false }

            // Feed session
            sessionManager.addReading(r)

            // Check custom thresholds
            let triggered = alertSettings.checkReading(r)
            for alert in triggered {
                sessionManager.incrementAlerts()
                // Push notification
                NotificationManager.shared.send(
                    title: alert.subject,
                    body:  String(alert.body.prefix(200)),
                    identifier: "custom-\(alert.type)-\(Date().timeIntervalSince1970)"
                )
                // Email (first alert only)
                if alertSettings.emailEnabled, !alertSettings.email.isEmpty,
                   MFMailComposeViewController.canSendMail(), pendingMail == nil {
                    pendingMail = alert; showMail = true
                }
            }
        }
        .onChange(of: bt.discoveredDevices) { _, devices in
            if !devices.isEmpty, case .scanning = bt.scanState { showDevicePicker = true }
        }
    }

    // MARK: - Dashboard Tab ────────────────────────────────────────────────

    private var dashboardTab: some View {
        ScrollView {
            LazyVStack(spacing: 16) {

                if let msg = bt.alertMessage, !alertDismissed {
                    AlertBanner(message: msg) { withAnimation { alertDismissed = true } }
                        .padding(.horizontal)
                        .animation(.spring(), value: msg)
                }

                statusRow.padding(.horizontal)

                // Wellness quick-card
                if !history.isEmpty {
                    wellnessQuickCard.padding(.horizontal)
                }

                if case .connected = bt.scanState {
                    if bt.phase == .calibrating {
                        calibrationView.padding(.horizontal)
                    } else if let r = bt.latestReading {
                        metricsRow(reading: r).padding(.horizontal)
                        chartsGrid(reading: r).padding(.horizontal)
                    }
                } else {
                    connectingView.frame(height: 360)
                }
            }
            .padding(.top, 12).padding(.bottom, 32)
        }
    }

    // MARK: - Wellness Quick Card

    private var wellnessQuickCard: some View {
        let score = sessionManager.isRecording
            ? sessionManager.currentWellness
            : sessionManager.computeWellness(history)
        let grade = gradeFor(score)
        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.purple.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: score / 100)
                    .stroke(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: score)
                VStack(spacing: 0) {
                    Text(grade).font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(.purple)
                    Text("Grade").font(.system(size: 9)).foregroundColor(.secondary)
                }
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text("Wellness Score").font(.caption2).textCase(.uppercase).foregroundColor(.secondary)
                Text(String(format: "%.0f / 100", score))
                    .font(.title3).fontWeight(.black).foregroundColor(.purple)
                Text(wellnessTip(score)).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            if !sessionManager.isRecording {
                Button {
                    if case .connected = bt.scanState { sessionManager.startSession() }
                } label: {
                    Label("Record", systemImage: "record.circle")
                        .font(.caption).fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button { sessionManager.stopSession() } label: {
                    Label("Stop", systemImage: "stop.circle")
                        .font(.caption).fontWeight(.semibold)
                }
                .buttonStyle(.bordered).tint(.red)
            }
        }
        .padding(14)
        .background(Color.purple.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.purple.opacity(0.2), lineWidth: 1))
    }

    private func gradeFor(_ score: Double) -> String {
        switch score {
        case 80...: return "A"; case 65...: return "B"
        case 50...: return "C"; case 35...: return "D"; default: return "F"
        }
    }

    private func wellnessTip(_ score: Double) -> String {
        switch score {
        case 80...: return "Excellent cognitive state 🎯"
        case 65...: return "Good focus level 👍"
        case 50...: return "Take a short stretch break"
        case 35...: return "Consider resting — fatigue detected"
        default:    return "Rest recommended — high fatigue"
        }
    }

    // MARK: - Calibration View

    private var calibrationView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 52))
                    .foregroundStyle(LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .symbolEffect(.pulse)
                Text("Calibrating Baseline")
                    .font(.title2).fontWeight(.bold)
                Text("Keep the headset on and stay relaxed.")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            .padding(.top, 24).padding(.bottom, 20)

            signalStatusCard.padding(.bottom, 12)
            progressSection.padding(.bottom, 20)

            if bt.rawPacketsReceived > 2 {
                liveMiniCharts
            }
            modelExplainerCard.padding(.top, 12)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var signalStatusCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                statPill(icon: "antenna.radiowaves.left.and.right", label: "BT Data",
                         value: bt.rawBytesReceived > 0 ? "\(bt.rawBytesReceived) B" : "None",
                         color: bt.rawBytesReceived > 0 ? .green : .orange)
                statPill(icon: "waveform", label: "Packets",
                         value: "\(bt.rawPacketsReceived)",
                         color: bt.rawPacketsReceived > 0 ? .blue : .gray)
                statPill(icon: "antenna.radiowaves.left.and.right.circle", label: "Contact",
                         value: bt.rawBytesReceived == 0 ? "---" : bt.signalQuality.rawValue,
                         color: signalQualityColor(bt.signalQuality))
                statPill(icon: "bolt.horizontal", label: "Raw EEG",
                         value: bt.rawBytesReceived == 0 ? "---" : "\(bt.lastRawValue)",
                         color: .teal)
            }

            if bt.rawBytesReceived == 0 {
                warningBanner(icon: "exclamationmark.bluetooth.2",
                              msg: "No BT data — make sure MindLink is on and paired.",
                              color: .orange)
            } else if bt.rawPacketsReceived == 0 {
                warningBanner(icon: "questionmark.circle",
                              msg: "Bytes arriving but no TGAM1 packets. Check pairing.",
                              color: .orange)
            } else if bt.signalQuality == .noContact {
                warningBanner(icon: "person.bust",
                              msg: "Electrode not touching — adjust headset.",
                              color: .red)
            }

            if !bt.rawHexPreview.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("First bytes", systemImage: "doc.text.magnifyingglass").font(.caption2).foregroundColor(.secondary)
                    Text(bt.rawHexPreview)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(bt.rawHexPreview.contains("AA AA") ? .green : .orange)
                        .lineLimit(2)
                    if bt.rawHexPreview.contains("AA AA") {
                        Label("TGAM1 sync found ✓", systemImage: "checkmark.circle.fill").font(.caption2).foregroundColor(.green)
                    } else {
                        Label("No TGAM1 sync — wrong protocol?", systemImage: "xmark.circle.fill").font(.caption2).foregroundColor(.orange)
                    }
                }
                .padding(10)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func statPill(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundColor(color).font(.system(size: 14))
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func warningBanner(icon: String, msg: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundColor(color).font(.system(size: 18))
            Text(msg).font(.caption).foregroundColor(color).fixedSize(horizontal: false, vertical: true)
        }.padding(10).background(color.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func signalQualityColor(_ q: TGAM1Packet.SignalQuality) -> Color {
        switch q { case .excellent: return .green; case .good: return .mint; case .fair: return .yellow; case .poor: return .orange; case .noContact: return .red }
    }

    private var progressSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.purple.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: bt.calibrationProgress)
                    .stroke(LinearGradient(colors: [.purple, .indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: bt.calibrationProgress)
                VStack(spacing: 2) {
                    Text("\(Int(bt.calibrationProgress * 100))%")
                        .font(.system(size: 34, weight: .black, design: .rounded)).foregroundColor(.purple)
                    Text("\(bt.rawPacketsReceived) / \(Config.baselineSamples)")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }.frame(width: 130, height: 130)

            Text(bt.rawBytesReceived == 0 ? "Waiting for EEG data…"
                 : bt.rawPacketsReceived == 0 ? "Parsing packets…"
                 : "Calibrating (\(Config.baselineSamples - bt.rawPacketsReceived) remaining)")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private var liveMiniCharts: some View {
        let recent = Array(history.suffix(30))
        return VStack(alignment: .leading, spacing: 6) {
            Text("Live Signal").font(.caption2).fontWeight(.bold).foregroundColor(.secondary).textCase(.uppercase)
            Chart(Array(recent.enumerated()), id: \.offset) { idx, r in
                LineMark(x: .value("t", idx), y: .value("A", r.attention)).foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 1.5)).interpolationMethod(.catmullRom)
                LineMark(x: .value("t", idx), y: .value("M", r.meditation)).foregroundStyle(.green).lineStyle(StrokeStyle(lineWidth: 1.5)).interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0...100).chartXAxis(.hidden).frame(height: 70)
            HStack(spacing: 16) {
                Label("Attention",  systemImage: "circle.fill").foregroundColor(.blue).font(.caption2)
                Label("Meditation", systemImage: "circle.fill").foregroundColor(.green).font(.caption2)
            }
        }
        .padding(12).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var modelExplainerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("How the model works", systemImage: "info.circle").font(.caption).fontWeight(.bold).foregroundColor(.secondary)
            explainerRow("1", "30-packet baseline established at start", .purple)
            explainerRow("2", "Band ratios (α/β, θ/α) + attention/meditation trend computed", .indigo)
            explainerRow("3", "Rule-based fatigue score 0–1 (Python fallback logic)", .blue)
            explainerRow("4", "Alerts at: Low>0.1 · Med>0.2 · High>0.3 · Critical>0.4", .orange)
        }
        .padding(14).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func explainerRow(_ num: String, _ text: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(num).font(.system(size: 11, weight: .black, design: .rounded)).foregroundColor(.white)
                .frame(width: 18, height: 18).background(color).clipShape(Circle())
            Text(text).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Alerts Tab

    private var alertTab: some View {
        Group {
            if bt.alertHistory.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.shield").font(.system(size: 60)).foregroundColor(.green.opacity(0.6))
                    Text("No alerts yet").font(.headline).foregroundColor(.secondary)
                    Text("Alerts appear when fatigue or custom thresholds are crossed.")
                        .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(bt.alertHistory) { alert in
                    HStack(spacing: 12) {
                        Circle().fill(alertColor(alert.level)).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(alert.level.displayTitle).font(.subheadline).fontWeight(.bold).foregroundColor(alertColor(alert.level))
                            Text(alert.message).font(.caption).foregroundColor(.secondary)
                            HStack {
                                Text("Fatigue: \(String(format: "%.2f", alert.fatigueScore))")
                                Text("Drift: \(String(format: "%.2f", alert.cognitiveDrift))")
                            }.font(.caption2).foregroundColor(.secondary)
                            Text(alert.timestamp, style: .time).font(.caption2).foregroundColor(.secondary)
                        }
                    }.padding(.vertical, 4)
                }.listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Monitoring Dashboard

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 10, height: 10).shadow(color: statusColor.opacity(0.6), radius: 4)
            Text(statusText).font(.subheadline).foregroundColor(.secondary)
            Spacer()
            if case .scanning = bt.scanState, !bt.discoveredDevices.isEmpty {
                Button { showDevicePicker = true } label: {
                    Label("\(bt.discoveredDevices.count) found", systemImage: "list.bullet").font(.caption).foregroundColor(.blue)
                }
            }
            if bt.phase == .monitoring {
                Label("Monitoring", systemImage: "checkmark.circle.fill").font(.caption).foregroundColor(.green)
            }
        }
        .padding(12).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func metricsRow(reading: EEGReading) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                MetricCard(title: "Attention",  value: "\(Int(reading.attention))",  accent: .blue)
                MetricCard(title: "Meditation", value: "\(Int(reading.meditation))", accent: .green)
                MetricCard(title: "Fatigue",    value: String(format: "%.2f", reading.fatigueScore),
                           accent: fatigueLevelColor(reading.fatigueLevel), subtitle: reading.fatigueLevel.rawValue)
            }
            HStack(spacing: 12) {
                MetricCard(title: "Drift",
                           value: String(format: "%.3f", reading.cognitiveDrift),
                           accent: reading.cognitiveDrift > Config.driftThreshold ? .orange : .teal,
                           subtitle: reading.cognitiveDrift > Config.driftThreshold ? "⚠ High" : "Normal")
                MetricCard(title: "α/β Ratio",
                           value: String(format: "%.2f", reading.beta > 0 ? reading.alpha / reading.beta : 0),
                           accent: .purple)
                MetricCard(title: "θ/α Ratio",
                           value: String(format: "%.2f", reading.alpha > 0 ? reading.theta / reading.alpha : 0),
                           accent: .indigo)
            }
        }
    }

    @ViewBuilder
    private func chartsGrid(reading: EEGReading) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: columns, spacing: 16) {
            chartCard(title: "Attention & Meditation") {
                if history.count >= 2 { TrendChart(history: history, title: "").frame(height: 150) }
                else { placeholder }
            }
            chartCard(title: "Fatigue Score") {
                if history.count >= 2 { FatigueTrendChart(history: history).frame(height: 150) }
                else { placeholder }
            }
            chartCard(title: "Frequency Bands") {
                BandBarChart(bands: BandBarChart.from(reading: reading)).frame(height: 140)
            }.gridCellColumns(2)
        }
    }

    @ViewBuilder
    private func chartCard<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).fontWeight(.bold).foregroundColor(.secondary).textCase(.uppercase).tracking(0.5)
            content()
        }
        .padding(14).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var placeholder: some View {
        Text("Collecting data…").foregroundColor(.secondary).frame(height: 150)
    }

    @ViewBuilder
    private var connectingView: some View {
        VStack(spacing: 20) {
            switch bt.scanState {
            case .scanning:
                ProgressView().scaleEffect(1.6)
                Text("Scanning…").font(.headline).foregroundColor(.secondary)
                if !bt.discoveredDevices.isEmpty {
                    Button { showDevicePicker = true } label: {
                        Label("Choose Device (\(bt.discoveredDevices.count) found)", systemImage: "list.bullet")
                    }.buttonStyle(.borderedProminent)
                }
            case .connecting(let n):
                ProgressView().scaleEffect(1.6); Text("Connecting to \(n)…").font(.headline)
            case .error(let m):
                Image(systemName: "exclamationmark.triangle").font(.system(size: 44)).foregroundColor(.orange)
                Text(m).font(.headline).multilineTextAlignment(.center)
                Button("Retry") { bt.startScan() }.buttonStyle(.borderedProminent)
            default:
                Image(systemName: "brain.head.profile").font(.system(size: 60)).foregroundColor(.purple.opacity(0.4))
                Text("Ready to connect").font(.headline).foregroundColor(.secondary)
                Button("Scan for Devices") { bt.startScan() }.buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var connectionButton: some View {
        switch bt.scanState {
        case .connected:
            Button("Disconnect", role: .destructive) { bt.disconnect() }
        case .scanning:
            HStack(spacing: 12) {
                if !bt.discoveredDevices.isEmpty { Button { showDevicePicker = true } label: { Image(systemName: "list.bullet") } }
                Button("Stop") { bt.stopScan() }
            }
        default: Button("Scan") { bt.startScan() }
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch bt.scanState {
        case .connected: return .green; case .scanning: return .orange
        case .connecting: return .yellow; case .error: return .red; case .idle: return .gray
        }
    }
    private var statusText: String {
        switch bt.scanState {
        case .idle: return "Not connected — tap Scan"
        case .scanning: return "Scanning…"
        case .connecting(let n): return "Connecting to \(n)…"
        case .connected(let n): return "Connected: \(n)"
        case .error(let m): return m
        }
    }
    private func fatigueLevelColor(_ l: FatigueLevel) -> Color {
        switch l { case .low: return .green; case .medium: return .orange; case .high: return .red; case .critical: return Color(red: 0.8, green: 0, blue: 0) }
    }
    private func alertColor(_ l: AlertLevel) -> Color {
        switch l { case .low: return .yellow; case .medium: return .orange; case .high: return .red; case .critical: return Color(red: 0.8, green: 0, blue: 0) }
    }
}

// MARK: - Device Picker Sheet

struct DevicePickerSheet: View {
    @ObservedObject var bt: BluetoothManager
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                if bt.discoveredDevices.isEmpty {
                    Section { HStack { ProgressView(); Text("Scanning…").foregroundColor(.secondary).padding(.leading, 8) } }
                } else {
                    let eegDevs   = bt.discoveredDevices.filter { eegScore($0.name) > 0 }
                    let otherDevs = bt.discoveredDevices.filter { eegScore($0.name) == 0 }
                    if !eegDevs.isEmpty   { Section("EEG / Neuro Devices") { ForEach(eegDevs)   { row($0) } } }
                    if !otherDevs.isEmpty { Section("Other Bluetooth Devices") { ForEach(otherDevs) { row($0) } } }
                }
            }
            .navigationTitle("Select Device").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading)  { Button("Cancel") { isPresented = false } }
                ToolbarItem(placement: .navigationBarTrailing) { Button("Rescan") { bt.startScan() } }
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func row(_ device: DiscoveredDevice) -> some View {
        Button { bt.connect(to: device); isPresented = false } label: {
            HStack(spacing: 14) {
                Image(systemName: eegScore(device.name) > 0 ? "brain.head.profile" : "dot.radiowaves.left.and.right")
                    .foregroundColor(eegScore(device.name) > 0 ? .purple : .blue).font(.system(size: 22)).frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name).font(.body).fontWeight(.semibold).foregroundColor(.primary)
                    Text("\(device.signalBars)  \(device.sourceLabel)").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
            }.padding(.vertical, 4)
        }
    }

    private func eegScore(_ name: String) -> Int {
        let l = name.lowercased()
        return ["mindlink","mindwave","tgam","neurosky","eeg","neuro","thinkgear","brainwave"].contains(where: { l.contains($0) }) ? 1 : 0
    }
}

#Preview { ContentView() }
