import SwiftUI
import Charts

// MARK: - Brain Waves View

struct BrainWavesView: View {
    @ObservedObject var bt: BluetoothManager

    private let bands: [(key: String, label: String, sub: String, hz: String)] = [
        ("delta",      "δ Delta",  "Deep Sleep",      "0.5–4 Hz"),
        ("theta",      "θ Theta",  "Drowsiness",      "4–8 Hz"),
        ("low_alpha",  "α Low",    "Relaxed",         "8–10 Hz"),
        ("high_alpha", "α High",   "Eyes Closed",     "10–13 Hz"),
        ("low_beta",   "β Low",    "Focus",           "13–17 Hz"),
        ("high_beta",  "β High",   "Active Thinking", "17–30 Hz"),
        ("low_gamma",  "γ Low",    "Cognition",       "30–40 Hz"),
        ("high_gamma", "γ High",   "Peak Processing", "40–100 Hz"),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                headerBar
                statusBanner
                bandGrid
                if let p = bt.latestPacket, p.hasPowerData {
                    dominantBandCard(p: p).padding(.horizontal)
                }
                supplementalRings.padding(.horizontal)
                Spacer(minLength: 20)
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Label("Brain Wave Bands", systemImage: "brain")
                .font(.title3).fontWeight(.bold)
                .foregroundColor(.primary)
            Spacer()
            statusPill
        }
        .padding(.horizontal)
    }

    private var statusPill: some View {
        let hasPower = bt.latestPacket?.hasPowerData == true
        let hasData  = bt.rawPacketsReceived > 0
        return HStack(spacing: 5) {
            Circle()
                .fill(hasPower ? AppTheme.accent : hasData ? AppTheme.warn : AppTheme.danger)
                .frame(width: 7, height: 7)
            Text(hasPower ? "Live band powers"
                 : hasData ? "Signal — waiting for band data"
                 : "No signal")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(AppTheme.cardBG)
        .clipShape(Capsule())
    }

    // MARK: - Status Banner (only when no power yet but signal exists)

    @ViewBuilder
    private var statusBanner: some View {
        if bt.latestPacket?.hasPowerData != true && bt.rawPacketsReceived > 0 {
            HStack(spacing: 10) {
                Image(systemName: "info.circle").foregroundColor(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Waiting for EEG band powers")
                        .font(.subheadline).fontWeight(.semibold)
                    Text("Attention & meditation are live. The device sends band powers (δθαβγ) once per second via code 0x83 — rings will update automatically.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(AppTheme.accentDim)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.accentMid, lineWidth: 1))
            .padding(.horizontal)
        }
    }

    // MARK: - Band Grid (all same accent color)

    private var bandGrid: some View {
        let p      = bt.latestPacket
        let total  = max(p?.powerDict.values.reduce(0, +) ?? 0, 1)
        let hasPow = p?.hasPowerData == true

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(bands, id: \.key) { band in
                let rawVal  = p?.powerDict[band.key] ?? 0
                let percent = hasPow ? rawVal / total : 0
                BandRingCard(
                    label:    band.label,
                    subtitle: band.sub,
                    hz:       band.hz,
                    percent:  percent,
                    rawValue: rawVal,
                    isPending: !hasPow
                )
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Supplemental Rings (attention / meditation / fatigue / drift)

    private var supplementalRings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Live Computed Metrics")
                .font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                .textCase(.uppercase).tracking(0.5)
            HStack(spacing: 12) {
                ScoreRing(label: "Attention",  value: (bt.latestReading?.attention  ?? 0) / 100,
                          display: bt.latestReading.map { "\(Int($0.attention))" } ?? "—")
                ScoreRing(label: "Meditation", value: (bt.latestReading?.meditation ?? 0) / 100,
                          display: bt.latestReading.map { "\(Int($0.meditation))" } ?? "—")
                ScoreRing(label: "Fatigue",    value: bt.latestReading?.fatigueScore ?? 0,
                          display: bt.latestReading.map { String(format: "%.2f", $0.fatigueScore) } ?? "—")
                ScoreRing(label: "Drift",      value: min((bt.latestReading?.cognitiveDrift ?? 0) * 10, 1),
                          display: bt.latestReading.map { String(format: "%.3f", $0.cognitiveDrift) } ?? "—")
            }
        }
        .padding(14)
        .background(AppTheme.cardBG)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Dominant Band Card

    @ViewBuilder
    private func dominantBandCard(p: TGAM1Packet) -> some View {
        let total = max(p.powerDict.values.reduce(0, +), 1)
        guard let dominant = bands.max(by: { (p.powerDict[$0.key] ?? 0) < (p.powerDict[$1.key] ?? 0) })
        else { return AnyView(EmptyView()) as AnyView }
        let pct = (p.powerDict[dominant.key] ?? 0) / total
        return AnyView(
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(AppTheme.accentDim).frame(width: 52, height: 52)
                    Text(dominant.label.prefix(1).description)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(AppTheme.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dominant Band").font(.caption2).textCase(.uppercase).foregroundColor(.secondary)
                    Text("\(dominant.label) · \(dominant.hz)").font(.headline).fontWeight(.bold)
                    Text(brainState(dominant.key)).font(.subheadline).foregroundColor(.secondary)
                    Text(String(format: "%.1f%% of total power", pct * 100))
                        .font(.caption2).foregroundColor(AppTheme.accent)
                }
                Spacer()
            }
            .padding(14)
            .background(AppTheme.cardBG)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        )
    }

    private func brainState(_ key: String) -> String {
        switch key {
        case "delta":      return "🌙 Deep rest"
        case "theta":      return "😴 Drowsy / deeply relaxed"
        case "low_alpha":  return "😌 Calm and relaxed"
        case "high_alpha": return "🧘 Eyes-closed rest"
        case "low_beta":   return "🧠 Focused and alert"
        case "high_beta":  return "⚡ Active problem solving"
        case "low_gamma":  return "🔥 Strong cognitive engagement"
        case "high_gamma": return "🚀 Peak mental processing"
        default:           return ""
        }
    }
}

// MARK: - Band Ring Card (single accent color)

struct BandRingCard: View {
    let label:     String
    let subtitle:  String
    let hz:        String
    let percent:   Double
    let rawValue:  Double
    var isPending: Bool = false
    @State private var animated: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(AppTheme.fill, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: animated)
                    .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: animated)
                VStack(spacing: 1) {
                    Text(isPending ? "—" : String(format: "%.1f%%", percent * 100))
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(isPending ? .secondary : AppTheme.accent)
                    Text(label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 90, height: 90)
            .onChange(of: percent) { _, v in animated = min(v, 1) }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { animated = min(percent, 1) } }

            VStack(spacing: 2) {
                Text(subtitle).font(.caption).fontWeight(.semibold)
                Text(hz).font(.caption2).foregroundColor(.secondary)
                if rawValue > 0 {
                    Text(String(format: "%.0f", rawValue))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(AppTheme.accentMid)
                }
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(AppTheme.cardBG)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Score Ring (single accent color)

struct ScoreRing: View {
    let label:   String
    let value:   Double
    let display: String
    @State private var animated: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(AppTheme.fill, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: animated)
                    .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: animated)
                Text(display)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.accent)
            }
            .frame(width: 58, height: 58)
            .onChange(of: value) { _, v in animated = min(v, 1) }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { animated = min(value, 1) } }
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview { BrainWavesView(bt: BluetoothManager()) }
