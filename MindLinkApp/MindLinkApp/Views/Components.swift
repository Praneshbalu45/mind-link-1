import SwiftUI
import Charts

// MARK: - Metric Card

struct MetricCard: View {
    let title: String
    let value: String
    let accent: Color
    let subtitle: String?

    init(title: String, value: String, accent: Color, subtitle: String? = nil) {
        self.title = title; self.value = value
        self.accent = accent; self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundColor(accent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            if let sub = subtitle {
                Text(sub)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Color(.systemGray6).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Band Bar Chart

struct BandBarChart: View {

    struct Band: Identifiable {
        let id = UUID()
        let name: String
        let symbol: String
        let value: Double
        let color: Color
    }

    let bands: [Band]

    var body: some View {
        Chart(bands) { band in
            BarMark(
                x: .value("Band", "\(band.symbol) \(band.name)"),
                y: .value("Power", band.value)
            )
            .foregroundStyle(band.color.gradient)
            .cornerRadius(6)
            .annotation(position: .top) {
                Text(String(format: "%.2f", band.value))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .chartYScale(domain: 0...1)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let s = value.as(String.self) {
                        Text(s).font(.system(size: 10))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: [0, 0.5, 1.0]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel {
                    let v = value.as(Double.self) ?? 0.0
                    Text(String(format: "%.1f", v)).font(.system(size: 9))
                }
            }
        }
    }

    static func from(reading: EEGReading) -> [Band] {[
        Band(name: "Delta", symbol: "δ", value: reading.delta, color: .purple),
        Band(name: "Theta", symbol: "θ", value: reading.theta, color: .green),
        Band(name: "Alpha", symbol: "α", value: reading.alpha, color: .red),
        Band(name: "Beta",  symbol: "β", value: reading.beta,  color: .blue),
        Band(name: "Gamma", symbol: "γ", value: reading.gamma, color: .orange),
    ]}
}

// MARK: - Trend Chart

struct TrendChart: View {
    let history: [EEGReading]
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Chart(Array(history.enumerated()), id: \.offset) { idx, r in
                LineMark(
                    x: .value("t", idx),
                    y: .value("Attention", r.attention)
                )
                .foregroundStyle(.blue.gradient)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("t", idx),
                    y: .value("Meditation", r.meditation)
                )
                .foregroundStyle(.green.gradient)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").font(.system(size: 9)) }
                }
            }
            .chartLegend(position: .top, alignment: .trailing) {
                HStack(spacing: 12) {
                    Label("Attention", systemImage: "circle.fill").foregroundColor(.blue).font(.caption2)
                    Label("Meditation", systemImage: "circle.fill").foregroundColor(.green).font(.caption2)
                }
            }
        }
    }
}

// MARK: - Fatigue Trend Chart

struct FatigueTrendChart: View {
    let history: [EEGReading]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fatigue Score")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Chart(Array(history.enumerated()), id: \.offset) { idx, r in
                AreaMark(
                    x: .value("t", idx),
                    y: .value("Fatigue", r.fatigueScore)
                )
                .foregroundStyle(
                    LinearGradient(colors: [.purple.opacity(0.4), .purple.opacity(0.05)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("t", idx),
                    y: .value("Fatigue", r.fatigueScore)
                )
                .foregroundStyle(.purple.gradient)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.catmullRom)

                // Warning lines
                RuleMark(y: .value("Warning", 0.3))
                    .foregroundStyle(.orange.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))

                RuleMark(y: .value("Critical", 0.6))
                    .foregroundStyle(.red.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
            .chartYScale(domain: 0...1)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, 0.3, 0.6, 1.0]) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel {
                        let d = v.as(Double.self) ?? 0.0
                        Text(String(format: "%.1f", d)).font(.system(size: 9))
                    }
                }
            }
        }
    }
}

// MARK: - Alert Banner

struct AlertBanner: View {
    let message: String
    let onDismiss: () -> Void

    private var isCritical: Bool { message.contains("\u{1F6A8}") }
    private var iconName: String {
        isCritical ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill"
    }
    private var bgColor: Color  { isCritical ? Color.red    : Color.orange }
    private var iconColor: Color { isCritical ? Color.red   : Color.orange }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 22))
                .foregroundColor(iconColor)

            Text(message)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(bgColor.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(bgColor.opacity(0.5), lineWidth: 1.5)
                )
        )
        .shadow(color: bgColor.opacity(0.3), radius: 12)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        ))
    }
}
