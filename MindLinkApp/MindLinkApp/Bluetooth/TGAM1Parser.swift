import Foundation
import Combine

// MARK: - Raw packet from TGAM1

struct TGAM1Packet {
    var attention:  Double = 0
    var meditation: Double = 0
    var rawEEG:     Int    = 0
    var poorSignal: Int    = 0   // 0 = good contact, 200 = electrode off
    var delta:    Double = 0; var theta:    Double = 0
    var lowAlpha: Double = 0; var highAlpha: Double = 0
    var lowBeta:  Double = 0; var highBeta:  Double = 0
    var lowGamma: Double = 0; var highGamma: Double = 0
    var hasPowerData: Bool = false

    var powerDict: [String: Double] {[
        "delta": delta, "theta": theta,
        "low_alpha": lowAlpha, "high_alpha": highAlpha,
        "low_beta":  lowBeta,  "high_beta":  highBeta,
        "low_gamma": lowGamma, "high_gamma": highGamma,
    ]}

    var signalQuality: SignalQuality {
        switch poorSignal {
        case 0:       return .excellent
        case 1..<26:  return .good
        case 26..<51: return .fair
        case 51..<200:return .poor
        default:      return .noContact
        }
    }

    enum SignalQuality: String {
        case excellent = "Excellent"
        case good      = "Good"
        case fair      = "Fair"
        case poor      = "Poor"
        case noContact = "No Contact"
    }
}

// MARK: - EEGReading (UI model)

struct EEGReading: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    var attention:    Double = 0
    var meditation:   Double = 0
    var delta: Double = 0; var theta: Double = 0
    var alpha: Double = 0; var beta:  Double = 0; var gamma: Double = 0
    var fatigueScore:   Double       = 0
    var fatigueLevel:   FatigueLevel = .low
    var cognitiveDrift: Double       = 0
    var phase: MonitoringPhase       = .calibrating
    var rawValue: Int = 0
    var signalQuality: TGAM1Packet.SignalQuality = .noContact

    static func == (lhs: EEGReading, rhs: EEGReading) -> Bool { lhs.id == rhs.id }
}

enum FatigueLevel: String, CaseIterable {
    case low = "Low"; case medium = "Medium"
    case high = "High"; case critical = "Critical"
}

enum MonitoringPhase: String {
    case calibrating = "Calibrating"
    case monitoring  = "Monitoring"
}

// MARK: - TGAM1 Binary Packet Parser

class TGAM1Parser {

    /// Called every time a complete, checksum-valid packet is fully parsed.
    var onPacket: ((TGAM1Packet) -> Void)?

    /// Called with the first ~64 raw bytes for debug display
    var onRawBytes: (([UInt8]) -> Void)?

    /// Called on EVERY raw EEG sample (0x80 code) — up to 512 Hz
    var onRawSample: ((Int) -> Void)?

    private var buffer: [UInt8] = []
    private var state  = TGAM1Packet()
    private var firstBytesReported = false

    private enum Code: UInt8 {
        case poorSignal = 0x02
        case attention  = 0x04
        case meditation = 0x05
        case raw        = 0x80
        case eegPower   = 0x81
    }

    func feed(_ bytes: [UInt8]) {
        // Report first bytes for debug
        if !firstBytesReported && !bytes.isEmpty {
            firstBytesReported = true
            onRawBytes?(Array(bytes.prefix(64)))
        }
        buffer.append(contentsOf: bytes)
        while buffer.count >= 4 {
            guard buffer[0] == 0xAA, buffer[1] == 0xAA else { buffer.removeFirst(); continue }
            let pLen = Int(buffer[2])
            guard pLen < 170 else { buffer.removeFirst(2); continue }
            guard buffer.count >= 3 + pLen + 1 else { break }
            let payload  = Array(buffer[3 ..< (3 + pLen)])
            let checksum = buffer[3 + pLen]
            var sum: UInt8 = 0
            for b in payload { sum = sum &+ b }
            if ~sum == checksum { parse(payload: payload) }
            buffer.removeFirst(3 + pLen + 1)
        }
    }

    private func parse(payload: [UInt8]) {
        var i = 0
        var gotPower = false
        var gotRaw   = false

        while i < payload.count {
            let code = payload[i]; i += 1
            if code >= 0x80 {
                guard i < payload.count else { return }
                let len = Int(payload[i]); i += 1
                guard i + len <= payload.count else { return }
                let data = Array(payload[i ..< (i + len)]); i += len
                switch code {
                case Code.raw.rawValue where data.count >= 2:
                    let r = (Int(data[0]) << 8) | Int(data[1])
                    state.rawEEG = r > 32767 ? r - 65536 : r
                    gotRaw = true
                    onRawSample?(state.rawEEG)   // ← fires at ~512 Hz

                case Code.eegPower.rawValue where data.count >= 24:
                    state.delta     = u24(data, 0)
                    state.theta     = u24(data, 3)
                    state.lowAlpha  = u24(data, 6)
                    state.highAlpha = u24(data, 9)
                    state.lowBeta   = u24(data, 12)
                    state.highBeta  = u24(data, 15)
                    state.lowGamma  = u24(data, 18)
                    state.highGamma = u24(data, 21)
                    state.hasPowerData = true
                    gotPower = true

                default: break
                }
            } else {
                guard i < payload.count else { return }
                let val = payload[i]; i += 1
                switch code {
                case Code.poorSignal.rawValue: state.poorSignal = Int(val)
                case Code.attention.rawValue:  state.attention  = Double(val)
                case Code.meditation.rawValue: state.meditation = Double(val)
                default: break
                }
            }
        }

        // Fire callback:
        // - Always fire when we get power data (most useful packet)
        // - Fire on raw-only if no power data yet (early in session)  
        if gotPower || (gotRaw && !state.hasPowerData) {
            onPacket?(state)
        }
    }

    private func u24(_ d: [UInt8], _ o: Int) -> Double {
        Double((Int(d[o]) << 16) | (Int(d[o+1]) << 8) | Int(d[o+2]))
    }

    func reset() {
        buffer.removeAll()
        state = TGAM1Packet()
        firstBytesReported = false
    }
}
