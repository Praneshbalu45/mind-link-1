import Foundation

// MARK: - Prediction Result

struct PredictionResult {
    var fatigueScore:   Double       = 0
    var fatigueLevel:   FatigueLevel = .low
    var cognitiveDrift: Double       = 0
    var needsAlert:     Bool         = false
}

// MARK: - FatiguePredictor (port of ml_model.py _rule_based_predict)
// No scikit-learn on iOS — uses the same rule-based logic as the Python fallback.

class FatiguePredictor {

    func predict(_ features: EEGFeatures) -> PredictionResult {
        let score = features.fatigueScore
        let drift = features.cognitiveDrift

        let level: FatigueLevel
        switch score {
        case ..<0.30:  level = .low
        case ..<0.50:  level = .medium
        case ..<0.70:  level = .high
        default:       level = .critical
        }

        return PredictionResult(
            fatigueScore:   score,
            fatigueLevel:   level,
            cognitiveDrift: drift,
            needsAlert:     score > 0.4 || drift > Config.driftThreshold
        )
    }
}
