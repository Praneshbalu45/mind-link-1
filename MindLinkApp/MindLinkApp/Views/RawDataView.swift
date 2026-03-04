import SwiftUI
import Charts

// MARK: - Raw Data & Device Test View

struct RawDataView: View {
    @ObservedObject var bt: BluetoothManager

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ecgCard
                liveValuesCard
                if let p = bt.latestPacket, p.hasPowerData {
                    bandPowersCard(p)
                } else {
                    noBandPowerCard
                }
                deviceTestCard
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    // MARK: - ECG Waveform

    private var ecgCard: some View {
        card(title: "Raw EEG Waveform", icon: "waveform.path.ecg") {
            if bt.rawEEGSamples.isEmpty {
                Text("Waiting for raw EEG signal…")
                    .foregroundColor(.secondary).font(.caption)
                    .frame(height: 150)
            } else {
                ecgChart.frame(height: 150)
                HStack {
                    Label("512 Hz", systemImage: "waveform").font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text("Latest: \(bt.lastRawValue) µV")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AppTheme.accent)
                }
            }
        }
    }

    private var ecgChart: some View {
        let samples = bt.rawEEGSamples
        let yMin = (samples.min() ?? -500) * 1.2
        let yMax = (samples.max() ?? 500)  * 1.2
        return Chart {
            ForEach(Array(samples.enumerated()), id: \.offset) { idx, val in
                LineMark(x: .value("t", idx), y: .value("µV", val))
                    .foregroundStyle(AppTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: min(yMin, -1)...max(yMax, 1))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3)).foregroundStyle(Color.secondary.opacity(0.3))
                AxisValueLabel().font(.system(size: 8, design: .monospaced)).foregroundStyle(Color.secondary)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Live Values Grid

    private var liveValuesCard: some View {
        card(title: "Live Values", icon: "number.square") {
            let p = bt.latestPacket
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                valueCell("Attention",    "\(Int(p?.attention ?? 0))",           "/100")
                valueCell("Meditation",   "\(Int(p?.meditation ?? 0))",          "/100")
                valueCell("Signal",       bt.signalQuality.rawValue,             "")
                valueCell("Poor Signal",  "\(p?.poorSignal ?? 0)",               "/200")
                valueCell("Raw EEG",      "\(bt.lastRawValue)",                  "µV")
                valueCell("Packet Rate",  String(format: "%.0f", bt.packetRateHz), "pkt/s")
                valueCell("BT Bytes",     "\(bt.rawBytesReceived)",              "B")
                valueCell("Fatigue",      bt.latestReading.map { String(format: "%.2f", $0.fatigueScore) } ?? "—", "/1.0")
            }
        }
    }

    @ViewBuilder
    private func valueCell(_ label: String, _ value: String, _ unit: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption2).foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.accent)
                    Text(unit).font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Band Powers

    private func bandPowersCard(_ p: TGAM1Packet) -> some View {
        card(title: "EEG Band Powers", icon: "waveform") {
            let total = max(p.powerDict.values.reduce(0, +), 1)
            let bands: [(String, Double)] = [
                ("δ Delta",   p.delta),
                ("θ Theta",   p.theta),
                ("α Low",     p.lowAlpha),
                ("α High",    p.highAlpha),
                ("β Low",     p.lowBeta),
                ("β High",    p.highBeta),
                ("γ Low",     p.lowGamma),
                ("γ High",    p.highGamma),
            ]
            ForEach(bands, id: \.0) { name, val in
                HStack(spacing: 8) {
                    Text(name)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 72, alignment: .leading)
                    GeometryReader { geo in
                        let pct = total > 0 ? val / total : 0
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(AppTheme.accentDim)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.accent)
                                .frame(width: geo.size.width * pct)
                        }
                    }
                    .frame(height: 12)
                    Text(total > 0 ? String(format: "%.1f%%", val / total * 100) : "0%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AppTheme.accent)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }

    private var noBandPowerCard: some View {
        card(title: "EEG Band Powers", icon: "waveform") {
            HStack(spacing: 10) {
                Image(systemName: "hourglass").foregroundColor(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Waiting for band power packet")
                        .font(.subheadline).fontWeight(.semibold)
                    Text("The device sends EEG band powers (code 0x83) about once per second. Ensure electrodes have good contact.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Device Test

    private var deviceTestCard: some View {
        card(title: "Device Test", icon: "checkmark.shield") {
            let connected: Bool = { if case .connected = bt.scanState { return true }; return false }()
            Group {
                testRow("Bluetooth Connected",  passed: connected,
                        detail: { if case .connected(let n) = bt.scanState { return n }; return "No" }())
                testRow("Data Streaming",       passed: bt.rawBytesReceived > 0,
                        detail: bt.rawBytesReceived > 0 ? "\(bt.rawBytesReceived) bytes" : "No data")
                testRow("TGAM1 Protocol (0xAA)", passed: bt.rawPacketsReceived > 0,
                        detail: bt.rawPacketsReceived > 0 ? "\(bt.rawPacketsReceived) packets" : "No valid packets")
                testRow("Electrode Contact",    passed: bt.signalQuality != .noContact && bt.signalQuality != .poor,
                        detail: bt.signalQuality.rawValue)
                testRow("Raw EEG Active",       passed: abs(bt.lastRawValue) > 10,
                        detail: abs(bt.lastRawValue) > 10 ? "\(bt.lastRawValue) µV" : "Flat / no signal")
                testRow("Attention Data",       passed: (bt.latestPacket?.attention ?? 0) > 0,
                        detail: bt.latestPacket.map { "Value: \(Int($0.attention))" } ?? "None")
                testRow("Band Powers (0x83)",   passed: bt.latestPacket?.hasPowerData == true,
                        detail: bt.latestPacket?.hasPowerData == true ? "Receiving" : "Not yet received")
                testRow("Packet Rate",          passed: bt.packetRateHz >= 1,
                        detail: String(format: "%.0f pkt/s", bt.packetRateHz))
            }
            if !bt.rawHexPreview.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("First bytes hex:").font(.caption2).foregroundColor(.secondary)
                    Text(bt.rawHexPreview)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(bt.rawHexPreview.contains("AA AA") ? AppTheme.accent : AppTheme.warn)
                        .lineLimit(3)
                }
            }
        }
    }

    @ViewBuilder
    private func testRow(_ label: String, passed: Bool, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(passed ? AppTheme.accent : AppTheme.danger)
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.subheadline).fontWeight(.medium)
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(passed ? AppTheme.accentDim : AppTheme.danger.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Card Helper

    @ViewBuilder
    private func card<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.subheadline).fontWeight(.bold)
                .foregroundColor(AppTheme.accent)
            content()
        }
        .padding(14)
        .background(AppTheme.cardBG)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview { RawDataView(bt: BluetoothManager()) }
