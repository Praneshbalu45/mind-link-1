import SwiftUI
import Charts

// MARK: - Raw Data & Device Test View

struct RawDataView: View {
    @ObservedObject var bt: BluetoothManager

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {

                // ── ECG Waveform ──────────────────────────────────────────
                ecgCard

                // ── Live All-Values Grid ──────────────────────────────────
                liveValuesCard

                // ── Band Powers ──────────────────────────────────────────
                if let p = bt.latestPacket, p.hasPowerData {
                    bandPowersCard(p)
                }

                // ── Device Test / Verification ────────────────────────────
                deviceTestCard
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    // MARK: - ECG Waveform

    private var ecgCard: some View {
        sectionCard(title: "Raw EEG Waveform", icon: "waveform.path.ecg") {
            if bt.rawEEGSamples.isEmpty {
                placeholderView(text: "Waiting for raw EEG signal…")
                    .frame(height: 160)
            } else {
                ecgChart
                    .frame(height: 160)

                HStack {
                    Label("512 Hz raw EEG", systemImage: "waveform")
                        .font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text("Latest: \(bt.lastRawValue)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.teal)
                }
            }
        }
    }

    private var ecgChart: some View {
        let samples = bt.rawEEGSamples
        let count   = samples.count
        // Compute y range with padding
        let yMin = (samples.min() ?? -500) * 1.1
        let yMax = (samples.max() ?? 500) * 1.1

        return Chart {
            ForEach(Array(samples.enumerated()), id: \.offset) { idx, val in
                LineMark(
                    x: .value("t", idx),
                    y: .value("µV", val)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green, .teal],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineStyle(StrokeStyle(lineWidth: 1.2))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: yMin...max(yMax, yMin + 1))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4, dash: [4]))
                    .foregroundStyle(Color.white.opacity(0.2))
                AxisValueLabel()
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.secondary)
            }
        }
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Live Values Grid

    private var liveValuesCard: some View {
        sectionCard(title: "Live Values", icon: "number.square") {
            let p = bt.latestPacket
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                valueRow("Attention",  value: p.map { "\(Int($0.attention))"  } ?? "---", unit: "/100", color: .blue)
                valueRow("Meditation", value: p.map { "\(Int($0.meditation))" } ?? "---", unit: "/100", color: .green)
                valueRow("Signal Quality", value: bt.signalQuality.rawValue, unit: "", color: signalColor)
                valueRow("Poor Signal",    value: p.map { "\($0.poorSignal)" } ?? "---", unit: "/200", color: .orange)
                valueRow("Raw EEG",   value: "\(bt.lastRawValue)",  unit: "µV", color: .teal)
                valueRow("Packet Rate", value: String(format: "%.0f", bt.packetRateHz), unit: "pkt/s", color: .purple)
                valueRow("BT Bytes",  value: "\(bt.rawBytesReceived)", unit: "B",   color: .indigo)
                valueRow("Fatigue",   value: {
                    if let r = bt.latestReading { return String(format: "%.2f", r.fatigueScore) }
                    return "---"
                }(), unit: "/1.0", color: .red)
            }
        }
    }

    @ViewBuilder
    private func valueRow(_ label: String, value: String, unit: String, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption2).foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                    Text(unit).font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Band Powers Card

    private func bandPowersCard(_ p: TGAM1Packet) -> some View {
        sectionCard(title: "EEG Band Powers", icon: "waveform") {
            let total = p.powerDict.values.reduce(0, +)
            let bands: [(String, Double, Color)] = [
                ("δ Delta",   p.delta,                        .indigo),
                ("θ Theta",   p.theta,                        .blue),
                ("α Low α",   p.lowAlpha,                     .cyan),
                ("α High α",  p.highAlpha,                    .teal),
                ("β Low β",   p.lowBeta,                      .green),
                ("β High β",  p.highBeta,                     .mint),
                ("γ Low γ",   p.lowGamma,                     .yellow),
                ("γ High γ",  p.highGamma,                    .orange),
            ]
            ForEach(bands, id: \.0) { name, val, color in
                HStack(spacing: 10) {
                    Text(name)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    GeometryReader { geo in
                        let pct = total > 0 ? val / total : 0
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(0.25))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(color)
                                    .frame(width: geo.size.width * pct, alignment: .leading),
                                alignment: .leading
                            )
                    }
                    .frame(height: 14)
                    Text(total > 0 ? String(format: "%.1f%%", val / total * 100) : "0%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Device Test / Verification Card

    private var deviceTestCard: some View {
        sectionCard(title: "Device Test", icon: "checkmark.shield") {
            VStack(spacing: 10) {

                // Test row helper
                testRow(
                    label: "Bluetooth Connected",
                    passed: {
                        if case .connected = bt.scanState { return true }
                        return false
                    }(),
                    detail: { if case .connected(let n) = bt.scanState { return n }; return "No" }()
                )
                testRow(
                    label: "Data Streaming",
                    passed: bt.rawBytesReceived > 0,
                    detail: bt.rawBytesReceived > 0 ? "\(bt.rawBytesReceived) bytes" : "No data"
                )
                testRow(
                    label: "TGAM1 Protocol",
                    passed: bt.rawPacketsReceived > 0,
                    detail: bt.rawPacketsReceived > 0 ? "\(bt.rawPacketsReceived) packets" : "No valid packets"
                )
                testRow(
                    label: "Electrode Contact",
                    passed: bt.signalQuality == .excellent || bt.signalQuality == .good || bt.signalQuality == .fair,
                    detail: bt.signalQuality.rawValue + (bt.latestPacket.map { " (code \($0.poorSignal))" } ?? "")
                )
                testRow(
                    label: "Raw EEG Signal",
                    passed: abs(bt.lastRawValue) > 10,
                    detail: abs(bt.lastRawValue) > 10 ? "Active (\(bt.lastRawValue) µV)" : "Flat / No signal"
                )
                testRow(
                    label: "Attention Data",
                    passed: (bt.latestPacket?.attention ?? 0) > 0,
                    detail: bt.latestPacket.map { "Value: \(Int($0.attention))" } ?? "No data"
                )
                testRow(
                    label: "Band Power Data",
                    passed: bt.latestPacket?.hasPowerData == true,
                    detail: bt.latestPacket?.hasPowerData == true ? "Receiving" : "Not yet"
                )
                testRow(
                    label: "Packet Rate",
                    passed: bt.packetRateHz >= 1,
                    detail: String(format: "%.0f pkt/s", bt.packetRateHz)
                )

                // Hex dump
                if !bt.rawHexPreview.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("First bytes hex:")
                            .font(.caption2).foregroundColor(.secondary)
                        Text(bt.rawHexPreview)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(bt.rawHexPreview.contains("AA AA") ? .green : .orange)
                            .lineLimit(4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func testRow(label: String, passed: Bool, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(passed ? .green : .red)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline).fontWeight(.medium)
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(
            (passed ? Color.green : Color.red).opacity(0.06)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.subheadline).fontWeight(.bold)
                .foregroundStyle(
                    LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing)
                )
            content()
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func placeholderView(text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg").font(.system(size: 36)).foregroundColor(.secondary.opacity(0.4))
            Text(text).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var signalColor: Color {
        switch bt.signalQuality {
        case .excellent: return .green
        case .good: return .mint
        case .fair: return .yellow
        case .poor: return .orange
        case .noContact: return .red
        }
    }
}

#Preview {
    RawDataView(bt: BluetoothManager())
}
