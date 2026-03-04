import Foundation
import UserNotifications

// MARK: - Session Record

struct SessionRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let durationSeconds: Int
    let avgAttention: Double
    let avgMeditation: Double
    let avgFatigue: Double
    let maxFatigue: Double
    let wellnessScore: Double
    let alertsFired: Int

    var durationStr: String {
        let m = durationSeconds / 60; let s = durationSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
    var wellnessGrade: String {
        switch wellnessScore {
        case 80...: return "A"
        case 65...: return "B"
        case 50...: return "C"
        case 35...: return "D"
        default:    return "F"
        }
    }
}

// MARK: - Session Manager

class SessionManager: ObservableObject {

    @Published var isRecording = false
    @Published var sessionHistory: [SessionRecord] = []
    @Published var currentDuration: Int = 0   // seconds
    @Published var currentWellness: Double = 0

    private var startTime: Date?
    private var readings: [EEGReading] = []
    private var alertCount = 0
    private var durationTimer: Timer?

    // MARK: - Start / Stop

    func startSession() {
        startTime = Date()
        readings.removeAll()
        alertCount = 0
        currentDuration = 0
        isRecording = true
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let start = self.startTime else { return }
            DispatchQueue.main.async { self.currentDuration = Int(Date().timeIntervalSince(start)) }
        }
    }

    func addReading(_ r: EEGReading) {
        guard isRecording else { return }
        readings.append(r)
        currentWellness = computeWellness(readings)
    }

    func incrementAlerts() { if isRecording { alertCount += 1 } }

    func stopSession() {
        durationTimer?.invalidate(); durationTimer = nil
        guard isRecording, let start = startTime, !readings.isEmpty else {
            isRecording = false; return
        }
        let record = SessionRecord(
            id: UUID(),
            date: start,
            durationSeconds: Int(Date().timeIntervalSince(start)),
            avgAttention:  readings.map(\.attention).reduce(0,+) / Double(readings.count),
            avgMeditation: readings.map(\.meditation).reduce(0,+) / Double(readings.count),
            avgFatigue:    readings.map(\.fatigueScore).reduce(0,+) / Double(readings.count),
            maxFatigue:    readings.map(\.fatigueScore).max() ?? 0,
            wellnessScore: computeWellness(readings),
            alertsFired:   alertCount
        )
        sessionHistory.insert(record, at: 0)
        if sessionHistory.count > 50 { sessionHistory.removeLast() }
        saveHistory()
        isRecording = false
    }

    // MARK: - Wellness Score (0-100)

    func computeWellness(_ r: [EEGReading]) -> Double {
        guard !r.isEmpty else { return 0 }
        let attn  = r.map(\.attention ).reduce(0,+) / Double(r.count)
        let med   = r.map(\.meditation).reduce(0,+) / Double(r.count)
        let fatigue = r.map(\.fatigueScore).reduce(0,+) / Double(r.count)
        // weighted: attention 40%, meditation 30%, low-fatigue 30%
        let score = (attn * 0.4) + (med * 0.3) + ((1 - fatigue) * 100 * 0.3)
        return min(max(score, 0), 100)
    }

    // MARK: - Persistence

    private let historyKey = "sessionHistory"

    func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([SessionRecord].self, from: data)
        else { return }
        sessionHistory = decoded
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(sessionHistory) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
}

// MARK: - Local Notification Manager

class NotificationManager {

    static let shared = NotificationManager()

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func send(title: String, body: String, identifier: String, delay: TimeInterval = 1) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body  = body
            content.sound = .defaultCritical
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) { _ in }
        }
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
