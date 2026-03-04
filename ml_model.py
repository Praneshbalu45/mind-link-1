"""
Machine Learning model for cognitive drift detection and fatigue prediction
"""

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier, GradientBoostingRegressor
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
import joblib
import os
import logging
from typing import Dict, List, Optional
from config import ML_MODEL_PATH

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class FatigueDetector:
    """
    Machine learning model for detecting mental fatigue and cognitive drift
    """
    
    def __init__(self):
        self.model = None
        self.scaler = StandardScaler()
        self.is_trained = False
        self.feature_names = [
            'attention_mean', 'attention_std', 'attention_trend', 'attention_deviation',
            'meditation_mean', 'meditation_std', 'meditation_trend', 'meditation_deviation',
            'alpha_mean', 'alpha_std', 'alpha_trend', 'alpha_deviation',
            'beta_mean', 'beta_std', 'beta_trend', 'beta_deviation',
            'theta_mean', 'theta_std', 'theta_trend', 'theta_deviation',
            'alpha_beta_ratio_mean', 'alpha_beta_ratio_trend', 'alpha_beta_deviation',
            'theta_alpha_ratio_mean', 'theta_alpha_ratio_trend',
            'cognitive_drift'
        ]
    
    def train(self, features_list: List[Dict], labels: Optional[List[float]] = None):
        """
        Train the fatigue detection model
        Args:
            features_list: List of feature dictionaries
            labels: Optional labels for supervised learning (fatigue scores)
        """
        if not features_list:
            logger.warning("No training data provided")
            return
        
        # Convert to DataFrame
        df = pd.DataFrame(features_list)
        
        # Fill missing columns with 0
        for col in self.feature_names:
            if col not in df.columns:
                df[col] = 0.0
        
        # Select only relevant features
        X = df[self.feature_names].fillna(0.0)
        
        if labels is None:
            # Unsupervised: use fatigue_score as target
            if 'fatigue_score' in df.columns:
                y = df['fatigue_score'].values
            else:
                logger.warning("No labels provided, using default fatigue scores")
                y = np.random.uniform(0, 0.5, len(X))  # Placeholder
        else:
            y = np.array(labels)
        
        # Scale features
        X_scaled = self.scaler.fit_transform(X)
        
        # Train model (using regression for continuous fatigue score)
        self.model = GradientBoostingRegressor(
            n_estimators=100,
            learning_rate=0.1,
            max_depth=5,
            random_state=42
        )
        
        self.model.fit(X_scaled, y)
        self.is_trained = True
        logger.info(f"Model trained on {len(X)} samples")
    
    def predict(self, features: Dict) -> Dict[str, float]:
        """
        Predict fatigue level and cognitive drift
        Args:
            features: Dictionary of extracted features
        Returns:
            Dictionary with predictions
        """
        if not self.is_trained:
            # Use rule-based prediction if model not trained
            return self._rule_based_predict(features)
        
        # Convert features to array
        feature_vector = []
        for name in self.feature_names:
            feature_vector.append(features.get(name, 0.0))
        
        X = np.array(feature_vector).reshape(1, -1)
        X_scaled = self.scaler.transform(X)
        
        # Predict fatigue score
        fatigue_score = self.model.predict(X_scaled)[0]
        fatigue_score = np.clip(fatigue_score, 0.0, 1.0)
        
        # Determine fatigue level
        if fatigue_score < 0.3:
            level = 'low'
        elif fatigue_score < 0.5:
            level = 'medium'
        elif fatigue_score < 0.7:
            level = 'high'
        else:
            level = 'critical'
        
        # Calculate drift severity
        cognitive_drift = features.get('cognitive_drift', 0.0)
        
        return {
            'fatigue_score': float(fatigue_score),
            'fatigue_level': level,
            'cognitive_drift': float(cognitive_drift),
            'needs_alert': fatigue_score > 0.4 or cognitive_drift > 0.15
        }
    
    def _rule_based_predict(self, features: Dict) -> Dict[str, float]:
        """
        Rule-based prediction when ML model is not trained
        """
        fatigue_score = features.get('fatigue_score', 0.0)
        cognitive_drift = features.get('cognitive_drift', 0.0)
        
        if fatigue_score < 0.3:
            level = 'low'
        elif fatigue_score < 0.5:
            level = 'medium'
        elif fatigue_score < 0.7:
            level = 'high'
        else:
            level = 'critical'
        
        return {
            'fatigue_score': float(fatigue_score),
            'fatigue_level': level,
            'cognitive_drift': float(cognitive_drift),
            'needs_alert': fatigue_score > 0.4 or cognitive_drift > 0.15
        }
    
    def save_model(self, filepath: str = ML_MODEL_PATH):
        """Save trained model to disk"""
        if not self.is_trained:
            logger.warning("Model not trained, cannot save")
            return
        
        os.makedirs(os.path.dirname(filepath), exist_ok=True)
        joblib.dump({
            'model': self.model,
            'scaler': self.scaler,
            'feature_names': self.feature_names
        }, filepath)
        logger.info(f"Model saved to {filepath}")
    
    def load_model(self, filepath: str = ML_MODEL_PATH):
        """Load trained model from disk"""
        if not os.path.exists(filepath):
            logger.warning(f"Model file not found: {filepath}")
            return False
        
        try:
            data = joblib.load(filepath)
            self.model = data['model']
            self.scaler = data['scaler']
            self.feature_names = data.get('feature_names', self.feature_names)
            self.is_trained = True
            logger.info(f"Model loaded from {filepath}")
            return True
        except Exception as e:
            logger.error(f"Error loading model: {e}")
            return False
