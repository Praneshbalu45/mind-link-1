import Foundation

// MARK: - Feature Set

struct EEGFeatures {
    // Attention stats
    var attentionMean:      Double = 0
    var attentionStd:       Double = 0
    var attentionMin:       Double = 0
    var attentionTrend:     Double = 0
    var attentionDeviation: Double = 0

    // Meditation stats
    var meditationMean:      Double = 0
    var meditationStd:       Double = 0
    var meditationMin:       Double = 0
    var meditationTrend:     Double = 0
    var meditationDeviation: Double = 0

    // Band stats
    var alphaMean: Double = 0; var alphaStd: Double = 0; var alphaTrend: Double = 0
    var betaMean:  Double = 0; var betaStd:  Double = 0; var betaTrend:  Double = 0
    var thetaMean: Double = 0; var thetaStd: Double = 0; var thetaTrend: Double = 0

    // Ratios
    var alphaBetaRatioMean:  Double = 0; var alphaBetaRatioTrend: Double = 0
    var thetaAlphaRatioMean: Double = 0; var thetaAlphaRatioTrend: Double = 0

    // Composite
    var cognitiveDrift: Double = 0
    var fatigueScore:   Double = 0
}

// MARK: - FeatureExtractor (port of feature_extractor.py)

class FeatureExtractor {

    private let windowSize: Int
    private let baselineSamples: Int

    // Rolling windows (capped at windowSize)
    private var attention:      [Double] = []
    private var meditation:     [Double] = []
    private var alphas:         [Double] = []
    private var betas:          [Double] = []
    private var thetas:         [Double] = []
    private var alphaBetaRatio: [Double] = []
    private var thetaAlpha:     [Double] = []

    // Baseline
    private var baseAttn:     Double?
    private var baseMed:      Double?
    private var baseAlpha:    Double?
    private var baseBeta:     Double?
    private var baseTheta:    Double?
    private var baseABRatio:  Double?
    private(set) var baselineEstablished = false

    init(windowSize: Int = Config.featureWindowSize,
         baselineSamples: Int = Config.baselineSamples) {
        self.windowSize     = windowSize
        self.baselineSamples = baselineSamples
    }

    // Counts total packets received — not capped, used for baseline trigger
    private(set) var totalSamples: Int = 0
    var calibrationProgress: Double {
        guard !baselineEstablished else { return 1.0 }
        return min(Double(totalSamples) / Double(baselineSamples), 1.0)
    }

    // MARK: - Add sample

    func addSample(attention attn: Double?, meditation med: Double?,
                   bands: BandPowers, ratios: BandRatios) {
        totalSamples += 1
        append(to: &self.attention,  value: attn ?? 0)
        append(to: &self.meditation, value: med  ?? 0)
        append(to: &alphas,         value: bands.alpha)
        append(to: &betas,          value: bands.beta)
        append(to: &thetas,         value: bands.theta)
        append(to: &alphaBetaRatio, value: ratios.alphaBeta)
        append(to: &thetaAlpha,     value: ratios.thetaAlpha)

        if !baselineEstablished && totalSamples >= baselineSamples {
            establishBaseline()
        }
    }

    private func append(to arr: inout [Double], value: Double) {
        arr.append(value)
        if arr.count > windowSize { arr.removeFirst() }
    }

    // MARK: - Baseline

    private func establishBaseline() {
        baseAttn    = mean(attention)
        baseMed     = mean(meditation)
        baseAlpha   = mean(alphas)
        baseBeta    = mean(betas)
        baseTheta   = mean(thetas)
        baseABRatio = mean(alphaBetaRatio)
        baselineEstablished = true
    }

    // MARK: - Extract Features

    func extractFeatures() -> EEGFeatures {
        var f = EEGFeatures()

        if !attention.isEmpty {
            f.attentionMean  = mean(attention)
            f.attentionStd   = std(attention)
            f.attentionMin   = attention.min() ?? 0
            f.attentionTrend = trend(attention)
            if let b = baseAttn, b != 0 {
                f.attentionDeviation = (f.attentionMean - b) / b
            }
        }

        if !meditation.isEmpty {
            f.meditationMean  = mean(meditation)
            f.meditationStd   = std(meditation)
            f.meditationMin   = meditation.min() ?? 0
            f.meditationTrend = trend(meditation)
            if let b = baseMed, b != 0 {
                f.meditationDeviation = (f.meditationMean - b) / b
            }
        }

        if !alphas.isEmpty {
            f.alphaMean  = mean(alphas)
            f.alphaStd   = std(alphas)
            f.alphaTrend = trend(alphas)
        }
        if !betas.isEmpty {
            f.betaMean  = mean(betas)
            f.betaStd   = std(betas)
            f.betaTrend = trend(betas)
        }
        if !thetas.isEmpty {
            f.thetaMean  = mean(thetas)
            f.thetaStd   = std(thetas)
            f.thetaTrend = trend(thetas)
        }
        if !alphaBetaRatio.isEmpty {
            f.alphaBetaRatioMean  = mean(alphaBetaRatio)
            f.alphaBetaRatioTrend = trend(alphaBetaRatio)
        }
        if !thetaAlpha.isEmpty {
            f.thetaAlphaRatioMean  = mean(thetaAlpha)
            f.thetaAlphaRatioTrend = trend(thetaAlpha)
        }

        f.cognitiveDrift = cognitiveDrift()
        f.fatigueScore   = fatigueScore(f)
        return f
    }

    // MARK: - Cognitive Drift

    private func cognitiveDrift() -> Double {
        guard baselineEstablished else { return 0 }
        var components: [Double] = []

        let recentCount = min(10, attention.count)
        if let b = baseAttn, b > 0, recentCount > 0 {
            let recent = mean(Array(attention.suffix(recentCount)))
            components.append(abs(recent - b) / 100.0)
        }
        let recentMed = min(10, meditation.count)
        if let b = baseMed, b > 0, recentMed > 0 {
            let recent = mean(Array(meditation.suffix(recentMed)))
            components.append(abs(recent - b) / 100.0)
        }
        let recentA = min(10, alphas.count)
        if let b = baseAlpha, b > 0, recentA > 0 {
            let recent = mean(Array(alphas.suffix(recentA)))
            components.append(abs(recent - b) / b)
        }
        return components.isEmpty ? 0 : mean(components)
    }

    // MARK: - Fatigue Score (matches _calculate_fatigue_score in Python)

    private func fatigueScore(_ f: EEGFeatures) -> Double {
        var components: [Double] = []

        // Low attention → fatigue
        if f.attentionMean > 0 {
            components.append((1.0 - f.attentionMean / 100.0) * 0.30)
        }
        // Low meditation → fatigue
        if f.meditationMean > 0 {
            components.append((1.0 - f.meditationMean / 100.0) * 0.20)
        }
        // High alpha (relaxation/drowsiness) → fatigue
        if f.alphaMean > 0 {
            components.append(min(f.alphaMean * 2.0, 1.0) * 0.20)
        }
        // Low beta (reduced alertness) → fatigue
        if f.betaMean > 0 {
            components.append((1.0 - min(f.betaMean * 3.0, 1.0)) * 0.15)
        }
        // High theta (drowsiness) → fatigue
        if f.thetaMean > 0 {
            components.append(min(f.thetaMean * 3.0, 1.0) * 0.15)
        }

        guard !components.isEmpty else { return 0 }
        return min(max(mean(components), 0), 1)
    }

    // MARK: - Statistics helpers

    private func mean(_ arr: [Double]) -> Double {
        guard !arr.isEmpty else { return 0 }
        return arr.reduce(0, +) / Double(arr.count)
    }

    private func std(_ arr: [Double]) -> Double {
        guard arr.count > 1 else { return 0 }
        let m = mean(arr)
        let variance = arr.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(arr.count)
        return sqrt(variance)
    }

    /// Linear regression slope — equivalent to np.polyfit(x, y, 1)[0]
    private func trend(_ arr: [Double]) -> Double {
        guard arr.count >= 2 else { return 0 }
        let n = Double(arr.count)
        let xs = (0..<arr.count).map { Double($0) }
        let xMean = (n - 1) / 2.0
        let yMean = mean(arr)
        let num = zip(xs, arr).map { ($0 - xMean) * ($1 - yMean) }.reduce(0, +)
        let den = xs.map { ($0 - xMean) * ($0 - xMean) }.reduce(0, +)
        return den > 0 ? num / den : 0
    }

    func reset() {
        attention.removeAll(); meditation.removeAll()
        alphas.removeAll(); betas.removeAll(); thetas.removeAll()
        alphaBetaRatio.removeAll(); thetaAlpha.removeAll()
        baseAttn = nil; baseMed = nil; baseAlpha = nil
        baseBeta = nil; baseTheta = nil; baseABRatio = nil
        baselineEstablished = false
    }
}
