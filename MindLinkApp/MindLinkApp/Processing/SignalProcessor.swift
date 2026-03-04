import Foundation
import Accelerate

// MARK: - Band Powers Result

struct BandPowers {
    var delta: Double = 0
    var theta: Double = 0
    var alpha: Double = 0
    var beta:  Double = 0
    var gamma: Double = 0

    var ratios: BandRatios {
        BandRatios(
            alphaBeta:       beta  > 0 ? alpha / beta  : 0,
            thetaAlpha:      alpha > 0 ? theta / alpha : 0,
            betaDelta:       delta > 0 ? beta  / delta : 0,
            alphaThetaBeta:  beta  > 0 ? (alpha + theta) / beta : 0
        )
    }
}

struct BandRatios {
    var alphaBeta:      Double = 0
    var thetaAlpha:     Double = 0
    var betaDelta:      Double = 0
    var alphaThetaBeta: Double = 0
}

// MARK: - SignalProcessor (port of signal_processor.py)

class SignalProcessor {

    private let sampleRate: Double
    private var rawBuffer: [Double] = []
    private let bufferSize = 512

    init(sampleRate: Double = Config.sampleRate) {
        self.sampleRate = sampleRate
    }

    // MARK: - Add raw EEG sample

    func addRawSample(_ value: Double) {
        rawBuffer.append(value)
        if rawBuffer.count > bufferSize { rawBuffer.removeFirst() }
    }

    // MARK: - Process raw buffer → frequency bands

    func processRawEEG(_ rawValue: Double? = nil) -> BandPowers {
        if let v = rawValue { addRawSample(v) }
        guard rawBuffer.count >= Config.windowSize else { return BandPowers() }

        var signal = Array(rawBuffer.suffix(Config.windowSize))

        // Remove DC
        let mean = signal.reduce(0, +) / Double(signal.count)
        signal = signal.map { $0 - mean }

        // Hann window to reduce spectral leakage
        var window = [Double](repeating: 0, count: signal.count)
        vDSP_hann_windowD(&window, vDSP_Length(signal.count), Int32(vDSP_HANN_NORM))
        vDSP_vmulD(signal, 1, window, 1, &signal, 1, vDSP_Length(signal.count))

        return extractBands(from: signal)
    }

    // MARK: - Process TGAM1 pre-computed band powers (from TGAM1 chip)

    func processTGAMPowerData(_ eegPower: [String: Double]) -> BandPowers {
        let total = eegPower.values.reduce(0, +)
        guard total > 0 else { return BandPowers() }

        return BandPowers(
            delta: (eegPower["delta"] ?? 0) / total,
            theta: (eegPower["theta"] ?? 0) / total,
            alpha: ((eegPower["low_alpha"] ?? 0) + (eegPower["high_alpha"] ?? 0)) / total,
            beta:  ((eegPower["low_beta"]  ?? 0) + (eegPower["high_beta"]  ?? 0)) / total,
            gamma: ((eegPower["low_gamma"] ?? 0) + (eegPower["high_gamma"] ?? 0)) / total
        )
    }

    // MARK: - FFT + Band Extraction

    private func extractBands(from samples: [Double]) -> BandPowers {
        let n = samples.count
        guard n >= 2 else { return BandPowers() }

        // Next power of 2 for FFT
        let fftSize = nextPowerOf2(n)
        var padded = samples + [Double](repeating: 0, count: fftSize - n)

        // Split-complex FFT via vDSP
        let log2n = vDSP_Length(log2(Double(fftSize)))
        guard let setup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else {
            return BandPowers()
        }
        defer { vDSP_destroy_fftsetupD(setup) }

        var splitR = [Double](repeating: 0, count: fftSize / 2)
        var splitI = [Double](repeating: 0, count: fftSize / 2)
        padded.withUnsafeBytes { ptrRaw in
            let ptr = ptrRaw.bindMemory(to: DSPDoubleComplex.self)
            var split = DSPDoubleSplitComplex(realp: &splitR, imagp: &splitI)
            vDSP_ctozD(ptr.baseAddress!, 2, &split, 1, vDSP_Length(fftSize / 2))
            vDSP_fft_zripD(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
        }

        // Compute power spectrum
        var power = [Double](repeating: 0, count: fftSize / 2)
        for i in 0 ..< fftSize / 2 {
            power[i] = splitR[i] * splitR[i] + splitI[i] * splitI[i]
        }
        let totalPower = power.reduce(0, +)
        guard totalPower > 0 else { return BandPowers() }

        let freqRes = sampleRate / Double(fftSize)   // Hz per bin

        func bandPower(low: Double, high: Double) -> Double {
            let loIdx = Int(low  / freqRes)
            let hiIdx = min(Int(high / freqRes), fftSize / 2 - 1)
            guard loIdx <= hiIdx else { return 0 }
            return power[loIdx...hiIdx].reduce(0, +) / totalPower
        }

        return BandPowers(
            delta: bandPower(low: 0.5,  high: 4.0),
            theta: bandPower(low: 4.0,  high: 8.0),
            alpha: bandPower(low: 8.0,  high: 13.0),
            beta:  bandPower(low: 13.0, high: 30.0),
            gamma: bandPower(low: 30.0, high: 100.0)
        )
    }

    func reset() { rawBuffer.removeAll() }

    // MARK: - Helpers

    private func nextPowerOf2(_ n: Int) -> Int {
        var p = 1
        while p < n { p <<= 1 }
        return p
    }
}
