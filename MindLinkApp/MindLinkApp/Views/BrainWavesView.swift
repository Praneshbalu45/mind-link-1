import SwiftUI

// MARK: - Brain Waves View (circular band gauges)

struct BrainWavesView: View {
    @ObservedObject var bt: BluetoothManager
    @State private var animatePulse = false

    private let bands: [(key: String, label: String, sub: String, hz: String, color: Color)] = [
        ("delta",      "δ Delta",      "Deep Sleep",      "0.5–4 Hz",    .indigo),
        ("theta",      "θ Theta",      "Drowsiness",      "4–8 Hz",      .blue),
        ("low_alpha",  "α Low",        "Relaxed",         "8–10 Hz",     .cyan),
        ("high_alpha", "α High",       "Eyes Closed",     "10–13 Hz",    .teal),
        ("low_beta",   "β Low",        "Focus",           "13–17 Hz",    .green),
        ("high_beta",  "β High",       "Active Thinking", "17–30 Hz",    .mint),
        ("low_gamma",  "γ Low",        "Cognition",       "30–40 Hz",    .yellow),
        ("high_gamma", "γ High",       "Peak Processing", "40–100 Hz",   .orange),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {

                // ── Header ──────────────────────────────────────
                headerView

                // ── Grid of 8 band rings ─────────────────────
                if let p = bt.latestPacket {
                    let total = max(p.powerDict.values.reduce(0, +), 1)
                    let cols = [GridItem(.flexible()), GridItem(.flexible())]
                    LazyVGrid(columns: cols, spacing: 16) {
                        ForEach(bands, id: \.key) { band in
                            let value = p.powerDict[band.key] ?? 0
                            BandRingCard(
                                label:    band.label,
                                subtitle: band.sub,
                                hz:       band.hz,
                                percent:  value / total,
                                rawValue: value,
                                color:    band.color
                            )
                        }
                    }
                    .padding(.horizontal)

                    // ── Dominant Band ──────────────────────────
                    dominantCard(p: p, total: total)
                        .padding(.horizontal)

                } else {
                    // Not connected / calibrating
                    emptyState
                }

                Spacer(minLength: 20)
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "brain")
                    .font(.system(size: 26))
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .indigo, .blue],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text("Brain Wave Bands")
                    .font(.title2).fontWeight(.bold)
            }
            Text("Live power distribution from your TGAM1 chip")
                .font(.caption).foregroundColor(.secondary)

            // Signal pill
            HStack(spacing: 6) {
                Circle()
                    .fill(bt.rawPacketsReceived > 0 ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                    .shadow(color: (bt.rawPacketsReceived > 0 ? Color.green : .orange).opacity(0.8), radius: 4)
                Text(bt.rawPacketsReceived > 0 ? "Live — \(Int(bt.packetRateHz)) pkt/s" : "Waiting for signal…")
                    .font(.caption2).foregroundColor(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
        }
        .padding(.top, 4)
    }

    // MARK: - Dominant band card

    private func dominantCard(p: TGAM1Packet, total: Double) -> some View {
        guard let dominant = bands.max(by: {
            (p.powerDict[$0.key] ?? 0) < (p.powerDict[$1.key] ?? 0)
        }) else { return AnyView(EmptyView()) }

        let pct   = (p.powerDict[dominant.key] ?? 0) / total
        let state = brainState(dominant: dominant.key)

        return AnyView(
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(dominant.color.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Text(String(dominant.label.prefix(1)))
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(dominant.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Dominant Band")
                        .font(.caption2).textCase(.uppercase).tracking(0.6).foregroundColor(.secondary)
                    Text("\(dominant.label) · \(dominant.hz)")
                        .font(.headline).fontWeight(.bold)
                    Text(state)
                        .font(.subheadline).foregroundColor(.secondary)
                    Text(String(format: "%.1f%% of total power", pct * 100))
                        .font(.caption2).foregroundColor(dominant.color)
                }
                Spacer()
            }
            .padding(16)
            .background(dominant.color.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(dominant.color.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
    }

    private func brainState(dominant: String) -> String {
        switch dominant {
        case "delta":      return "🌙 Deep rest or unconscious state"
        case "theta":      return "😴 Drowsy or deeply relaxed"
        case "low_alpha":  return "😌 Calm and relaxed"
        case "high_alpha": return "🧘 Eyes-closed meditation"
        case "low_beta":   return "🧠 Focused and alert"
        case "high_beta":  return "⚡ Actively thinking / problem solving"
        case "low_gamma":  return "🔥 Strong cognitive engagement"
        case "high_gamma": return "🚀 Peak mental processing"
        default:           return ""
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ForEach(bands, id: \.key) { band in
                BandRingCard(label: band.label, subtitle: band.sub,
                             hz: band.hz, percent: 0, rawValue: 0, color: band.color)
            }.padding(.horizontal)
        }
    }
}

// MARK: - Band Ring Card

struct BandRingCard: View {
    let label:    String
    let subtitle: String
    let hz:       String
    let percent:  Double
    let rawValue: Double
    let color:    Color

    @State private var animated: Double = 0

    var body: some View {
        VStack(spacing: 10) {

            // Circular ring
            ZStack {
                // Background track
                Circle()
                    .stroke(color.opacity(0.12), lineWidth: 10)

                // Filled arc
                Circle()
                    .trim(from: 0, to: animated)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [color.opacity(0.5), color]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle:   .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: animated)

                // Centre content
                VStack(spacing: 2) {
                    Text(String(format: "%.1f%%", percent * 100))
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(color)
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 100, height: 100)
            .onChange(of: percent) { _, v in animated = min(v, 1) }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { animated = min(percent, 1) } }

            // Labels
            VStack(spacing: 2) {
                Text(subtitle)
                    .font(.subheadline).fontWeight(.semibold)
                Text(hz)
                    .font(.caption2).foregroundColor(.secondary)
                if rawValue > 0 {
                    Text(String(format: "%.0f", rawValue))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(color.opacity(0.7))
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(color.opacity(percent > 0.2 ? 0.4 : 0.1), lineWidth: 1)
        )
    }
}

#Preview { BrainWavesView(bt: BluetoothManager()) }
