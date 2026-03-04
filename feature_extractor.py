"""
Feature extraction module for mental fatigue detection
Extracts features from EEG signals, attention, and meditation metrics
"""

import numpy as np
from typing import Dict, List, Optional
from collections import deque
import logging
from config import FEATURE_WINDOW_SIZE, BASELINE_SAMPLES

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class FeatureExtractor:
    """
    Extracts features for mental fatigue and cognitive drift detection
    """
    
    def __init__(self, window_size: int = FEATURE_WINDOW_SIZE):
        self.window_size = window_size
        
        # Feature history buffers
        self.attention_history = deque(maxlen=window_size)
        self.meditation_history = deque(maxlen=window_size)
        self.alpha_history = deque(maxlen=window_size)
        self.beta_history = deque(maxlen=window_size)
        self.theta_history = deque(maxlen=window_size)
        self.delta_history = deque(maxlen=window_size)
        self.gamma_history = deque(maxlen=window_size)
        self.alpha_beta_ratio_history = deque(maxlen=window_size)
        self.theta_alpha_ratio_history = deque(maxlen=window_size)
        
        # Baseline values
        self.baseline_attention = None
        self.baseline_meditation = None
        self.baseline_alpha = None
        self.baseline_beta = None
        self.baseline_theta = None
        self.baseline_alpha_beta = None
        
        self.baseline_samples = []
        self.baseline_established = False
        
    def add_sample(self, attention: Optional[float], meditation: Optional[float],
                   frequency_bands: Dict[str, float], band_ratios: Dict[str, float]):
        """
        Add a new sample to feature history
        """
        if attention is not None:
            self.attention_history.append(attention)
        if meditation is not None:
            self.meditation_history.append(meditation)
        
        self.alpha_history.append(frequency_bands.get('alpha', 0.0))
        self.beta_history.append(frequency_bands.get('beta', 0.0))
        self.theta_history.append(frequency_bands.get('theta', 0.0))
        self.delta_history.append(frequency_bands.get('delta', 0.0))
        self.gamma_history.append(frequency_bands.get('gamma', 0.0))
        
        self.alpha_beta_ratio_history.append(band_ratios.get('alpha_beta', 0.0))
        self.theta_alpha_ratio_history.append(band_ratios.get('theta_alpha', 0.0))
        
        # Collect baseline samples
        if not self.baseline_established and len(self.attention_history) >= BASELINE_SAMPLES:
            self._establish_baseline()
    
    def _establish_baseline(self):
        """Establish baseline values from initial samples"""
        if len(self.attention_history) < BASELINE_SAMPLES:
            return
        
        self.baseline_attention = np.mean(list(self.attention_history))
        self.baseline_meditation = np.mean(list(self.meditation_history))
        self.baseline_alpha = np.mean(list(self.alpha_history))
        self.baseline_beta = np.mean(list(self.beta_history))
        self.baseline_theta = np.mean(list(self.theta_history))
        self.baseline_alpha_beta = np.mean(list(self.alpha_beta_ratio_history))
        
        self.baseline_established = True
        logger.info("Baseline established for fatigue detection")
    
    def extract_features(self) -> Dict[str, float]:
        """
        Extract comprehensive feature set for fatigue detection
        Returns:
            Dictionary of extracted features
        """
        features = {}
        
        # Statistical features from attention
        if self.attention_history:
            attn_array = np.array(list(self.attention_history))
            features['attention_mean'] = np.mean(attn_array)
            features['attention_std'] = np.std(attn_array)
            features['attention_min'] = np.min(attn_array)
            features['attention_trend'] = self._calculate_trend(attn_array)
            
            # Deviation from baseline
            if self.baseline_attention:
                features['attention_deviation'] = (features['attention_mean'] - 
                                                   self.baseline_attention) / self.baseline_attention
        
        # Statistical features from meditation
        if self.meditation_history:
            med_array = np.array(list(self.meditation_history))
            features['meditation_mean'] = np.mean(med_array)
            features['meditation_std'] = np.std(med_array)
            features['meditation_min'] = np.min(med_array)
            features['meditation_trend'] = self._calculate_trend(med_array)
            
            if self.baseline_meditation:
                features['meditation_deviation'] = (features['meditation_mean'] - 
                                                   self.baseline_meditation) / self.baseline_meditation
        
        # Frequency band features
        if self.alpha_history:
            alpha_array = np.array(list(self.alpha_history))
            features['alpha_mean'] = np.mean(alpha_array)
            features['alpha_std'] = np.std(alpha_array)
            features['alpha_trend'] = self._calculate_trend(alpha_array)
            
            if self.baseline_alpha:
                features['alpha_deviation'] = (features['alpha_mean'] - 
                                             self.baseline_alpha) / self.baseline_alpha
        
        if self.beta_history:
            beta_array = np.array(list(self.beta_history))
            features['beta_mean'] = np.mean(beta_array)
            features['beta_std'] = np.std(beta_array)
            features['beta_trend'] = self._calculate_trend(beta_array)
            
            if self.baseline_beta:
                features['beta_deviation'] = (features['beta_mean'] - 
                                             self.baseline_beta) / self.baseline_beta
        
        if self.theta_history:
            theta_array = np.array(list(self.theta_history))
            features['theta_mean'] = np.mean(theta_array)
            features['theta_std'] = np.std(theta_array)
            features['theta_trend'] = self._calculate_trend(theta_array)
            
            if self.baseline_theta:
                features['theta_deviation'] = (features['theta_mean'] - 
                                              self.baseline_theta) / self.baseline_theta
        
        # Ratio features
        if self.alpha_beta_ratio_history:
            ab_ratio_array = np.array(list(self.alpha_beta_ratio_history))
            features['alpha_beta_ratio_mean'] = np.mean(ab_ratio_array)
            features['alpha_beta_ratio_trend'] = self._calculate_trend(ab_ratio_array)
            
            if self.baseline_alpha_beta:
                features['alpha_beta_deviation'] = (features['alpha_beta_ratio_mean'] - 
                                                   self.baseline_alpha_beta) / self.baseline_alpha_beta
        
        if self.theta_alpha_ratio_history:
            ta_ratio_array = np.array(list(self.theta_alpha_ratio_history))
            features['theta_alpha_ratio_mean'] = np.mean(ta_ratio_array)
            features['theta_alpha_ratio_trend'] = self._calculate_trend(ta_ratio_array)
        
        # Cognitive drift indicator
        features['cognitive_drift'] = self._calculate_cognitive_drift()
        
        # Fatigue score (0-1, higher = more fatigued)
        features['fatigue_score'] = self._calculate_fatigue_score(features)
        
        return features
    
    def _calculate_trend(self, values: np.ndarray) -> float:
        """Calculate linear trend (slope) of values"""
        if len(values) < 2:
            return 0.0
        x = np.arange(len(values))
        slope = np.polyfit(x, values, 1)[0]
        return slope
    
    def _calculate_cognitive_drift(self) -> float:
        """
        Calculate cognitive drift from baseline
        Returns normalized drift value (0-1)
        """
        if not self.baseline_established:
            return 0.0
        
        drift_components = []
        
        # Attention drift
        if self.attention_history and self.baseline_attention:
            current_attn = np.mean(list(self.attention_history[-10:]))  # Recent average
            attn_drift = abs(current_attn - self.baseline_attention) / 100.0
            drift_components.append(attn_drift)
        
        # Meditation drift
        if self.meditation_history and self.baseline_meditation:
            current_med = np.mean(list(self.meditation_history[-10:]))
            med_drift = abs(current_med - self.baseline_meditation) / 100.0
            drift_components.append(med_drift)
        
        # Frequency band drift
        if self.alpha_history and self.baseline_alpha:
            current_alpha = np.mean(list(self.alpha_history[-10:]))
            alpha_drift = abs(current_alpha - self.baseline_alpha) / self.baseline_alpha
            drift_components.append(alpha_drift)
        
        if drift_components:
            return np.mean(drift_components)
        return 0.0
    
    def _calculate_fatigue_score(self, features: Dict[str, float]) -> float:
        """
        Calculate composite fatigue score based on multiple indicators
        Returns value between 0 (no fatigue) and 1 (severe fatigue)
        """
        score_components = []
        
        # Low attention contributes to fatigue
        if 'attention_mean' in features:
            attn_score = 1.0 - (features['attention_mean'] / 100.0)
            score_components.append(attn_score * 0.3)
        
        # Low meditation contributes to fatigue
        if 'meditation_mean' in features:
            med_score = 1.0 - (features['meditation_mean'] / 100.0)
            score_components.append(med_score * 0.2)
        
        # High alpha (relaxation/drowsiness) contributes to fatigue
        if 'alpha_mean' in features:
            alpha_score = min(features['alpha_mean'] * 2.0, 1.0)  # Normalize
            score_components.append(alpha_score * 0.2)
        
        # Low beta (reduced alertness) contributes to fatigue
        if 'beta_mean' in features:
            beta_score = 1.0 - min(features['beta_mean'] * 3.0, 1.0)
            score_components.append(beta_score * 0.15)
        
        # High theta (drowsiness) contributes to fatigue
        if 'theta_mean' in features:
            theta_score = min(features['theta_mean'] * 3.0, 1.0)
            score_components.append(theta_score * 0.15)
        
        if score_components:
            fatigue_score = np.mean(score_components)
            return min(max(fatigue_score, 0.0), 1.0)  # Clamp between 0 and 1
        
        return 0.0
    
    def reset(self):
        """Reset feature extractor"""
        self.attention_history.clear()
        self.meditation_history.clear()
        self.alpha_history.clear()
        self.beta_history.clear()
        self.theta_history.clear()
        self.delta_history.clear()
        self.gamma_history.clear()
        self.alpha_beta_ratio_history.clear()
        self.theta_alpha_ratio_history.clear()
        self.baseline_established = False
        self.baseline_attention = None
        self.baseline_meditation = None
        self.baseline_alpha = None
        self.baseline_beta = None
        self.baseline_theta = None
        self.baseline_alpha_beta = None
