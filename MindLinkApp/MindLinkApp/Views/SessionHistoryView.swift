import SwiftUI
import Charts

// MARK: - Session History + Wellness View

struct SessionHistoryView: View {
    @ObservedObject var session: SessionManager
    @ObservedObject var bt: BluetoothManager

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {

                    // ── Live Wellness Card ─────────────────────────────────
                    if session.isRecording {
                        liveWellnessCard
                            .padding(.horizontal)
                    }

                    // ── Session History List ───────────────────────────────
                    if session.sessionHistory.isEmpty {
                        emptyState
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Past Sessions")
                                .font(.headline).fontWeight(.bold)
                                .padding(.horizontal)
                            ForEach(session.sessionHistory) { s in
                                sessionCard(s)
                                    .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if session.isRecording {
                        Button(role: .destructive) { session.stopSession() } label: {
                            Label("Stop", systemImage: "stop.circle.fill")
                        }
                    } else if case .connected = bt.scanState {
                        Button { session.startSession() } label: {
                            Label("Record", systemImage: "record.circle")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Live Wellness Card

    private var liveWellnessCard: some View {
        VStack(spacing: 16) {
            // Row 1: Recording status
            HStack {
                Label("Recording…", systemImage: "record.circle.fill")
                    .foregroundColor(.red).font(.subheadline)
                    .symbolEffect(.pulse)
                Spacer()
                Text(formatDuration(session.currentDuration))
                    .font(.system(.title2, design: .monospaced)).fontWeight(.bold)
            }

            // Row 2: Wellness ring + metrics
            HStack(spacing: 20) {
                // Wellness ring
                ZStack {
                    Circle()
                        .stroke(Color.purple.opacity(0.15), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: session.currentWellness / 100)
                        .stroke(
                            AngularGradient(colors: [.purple, .blue, .teal],
                                            center: .center,
                                            startAngle: .degrees(-90),
                                            endAngle:   .degrees(270)),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.8), value: session.currentWellness)
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f", session.currentWellness))
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(.purple)
                        Text("Wellness").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
                .frame(width: 100, height: 100)

                // Live metrics
                VStack(alignment: .leading, spacing: 8) {
                    if let r = bt.latestReading {
                        miniStat("Attention",  "\(Int(r.attention))",  .blue)
                        miniStat("Meditation", "\(Int(r.meditation))", .green)
                        miniStat("Fatigue",    String(format: "%.2f", r.fatigueScore), .orange)
                    }
                    miniStat("Duration", formatDuration(session.currentDuration), .secondary)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.red.opacity(0.4), lineWidth: 1.5)
        )
    }

    // MARK: - Session Card

    @ViewBuilder
    private func sessionCard(_ s: SessionRecord) -> some View {
        HStack(spacing: 14) {
            // Grade circle
            ZStack {
                Circle()
                    .fill(gradeColor(s.wellnessGrade).opacity(0.15))
                    .frame(width: 52, height: 52)
                Text(s.wellnessGrade)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(gradeColor(s.wellnessGrade))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(s.date, style: .date)
                    .font(.subheadline).fontWeight(.bold)
                HStack(spacing: 12) {
                    Label(s.durationStr, systemImage: "clock")
                        .font(.caption).foregroundColor(.secondary)
                    Label("\(Int(s.avgAttention)) attn", systemImage: "eye")
                        .font(.caption).foregroundColor(.blue)
                    Label("\(Int(s.avgMeditation)) med", systemImage: "waveform")
                        .font(.caption).foregroundColor(.green)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.0f", s.wellnessScore))
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(gradeColor(s.wellnessGrade))
                Text("wellness")
                    .font(.caption2).foregroundColor(.secondary)
                if s.alertsFired > 0 {
                    Label("\(s.alertsFired)", systemImage: "bell.fill")
                        .font(.caption2).foregroundColor(.orange)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 52)).foregroundColor(.secondary.opacity(0.4))
            Text("No sessions yet").font(.headline).foregroundColor(.secondary)
            Text("Connect MindLink and tap Record\nto start tracking your session.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func miniStat(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label + ":")
                .font(.caption2).foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }

    private func gradeColor(_ g: String) -> Color {
        switch g {
        case "A": return .green; case "B": return .teal
        case "C": return .yellow; case "D": return .orange
        default:  return .red
        }
    }

    private func formatDuration(_ s: Int) -> String {
        String(format: "%02d:%02d", s / 60, s % 60)
    }
}

#Preview { SessionHistoryView(session: SessionManager(), bt: BluetoothManager()) }
