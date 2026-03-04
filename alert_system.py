"""
Early warning alert system for mental fatigue and micro-burnout detection
"""

import logging
import time
from typing import Dict, Optional, Callable
from config import ALERT_COOLDOWN, ALERT_LEVELS, FATIGUE_THRESHOLDS

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class AlertSystem:
    """
    Manages early warning alerts for fatigue and cognitive drift
    """
    
    def __init__(self):
        self.last_alert_time = {}
        self.alert_cooldown = ALERT_COOLDOWN
        self.alert_callback: Optional[Callable] = None
        self.alert_history = []
        
    def set_alert_callback(self, callback: Callable):
        """Set callback function for alerts"""
        self.alert_callback = callback
    
    def check_alerts(self, features: Dict, predictions: Dict) -> Optional[Dict]:
        """
        Check if alerts should be triggered based on current state
        Args:
            features: Extracted features
            predictions: ML model predictions
        Returns:
            Alert dictionary if alert triggered, None otherwise
        """
        fatigue_score = predictions.get('fatigue_score', 0.0)
        cognitive_drift = predictions.get('cognitive_drift', 0.0)
        fatigue_level = predictions.get('fatigue_level', 'low')
        
        # Determine alert level
        alert_level = None
        alert_message = None
        
        # Check fatigue thresholds
        if fatigue_score >= ALERT_LEVELS['critical']:
            alert_level = 'critical'
            alert_message = "CRITICAL: Severe mental fatigue detected! Immediate rest recommended."
        elif fatigue_score >= ALERT_LEVELS['high']:
            alert_level = 'high'
            alert_message = "HIGH: Significant mental fatigue detected. Consider taking a break."
        elif fatigue_score >= ALERT_LEVELS['medium']:
            alert_level = 'medium'
            alert_message = "MEDIUM: Moderate fatigue detected. Monitor your cognitive state."
        elif fatigue_score >= ALERT_LEVELS['low']:
            alert_level = 'low'
            alert_message = "LOW: Early signs of fatigue detected. Stay aware."
        
        # Check cognitive drift
        if cognitive_drift > FATIGUE_THRESHOLDS['drift_threshold']:
            if alert_level != 'critical':
                alert_level = 'high' if alert_level != 'high' else alert_level
            if alert_message:
                alert_message += f" Cognitive drift: {cognitive_drift:.2f}"
            else:
                alert_message = f"Warning: Significant cognitive drift detected ({cognitive_drift:.2f})"
        
        # Check attention threshold
        attention = features.get('attention_mean', 100)
        if attention < FATIGUE_THRESHOLDS['attention_low']:
            if alert_level != 'critical' and alert_level != 'high':
                alert_level = 'medium' if alert_level != 'medium' else alert_level
            if alert_message:
                alert_message += f" Low attention: {attention:.1f}"
        
        # Check meditation threshold
        meditation = features.get('meditation_mean', 100)
        if meditation < FATIGUE_THRESHOLDS['meditation_low']:
            if alert_level != 'critical' and alert_level != 'high':
                alert_level = 'medium' if alert_level != 'medium' else alert_level
            if alert_message:
                alert_message += f" Low meditation: {meditation:.1f}"
        
        # Trigger alert if needed
        if alert_level and self._should_trigger_alert(alert_level):
            alert = {
                'level': alert_level,
                'message': alert_message,
                'fatigue_score': fatigue_score,
                'cognitive_drift': cognitive_drift,
                'timestamp': time.time()
            }
            
            self.last_alert_time[alert_level] = time.time()
            self.alert_history.append(alert)
            
            # Keep only last 100 alerts
            if len(self.alert_history) > 100:
                self.alert_history.pop(0)
            
            # Call callback if set
            if self.alert_callback:
                self.alert_callback(alert)
            
            logger.warning(f"ALERT [{alert_level.upper()}]: {alert_message}")
            return alert
        
        return None
    
    def _should_trigger_alert(self, alert_level: str) -> bool:
        """
        Check if alert should be triggered based on cooldown
        """
        if alert_level not in self.last_alert_time:
            return True
        
        time_since_last = time.time() - self.last_alert_time[alert_level]
        
        # Critical alerts bypass cooldown
        if alert_level == 'critical':
            return time_since_last > 60  # 1 minute cooldown for critical
        
        # Other alerts respect full cooldown
        return time_since_last > self.alert_cooldown
    
    def get_alert_summary(self) -> Dict:
        """Get summary of recent alerts"""
        if not self.alert_history:
            return {
                'total_alerts': 0,
                'critical_count': 0,
                'high_count': 0,
                'medium_count': 0,
                'low_count': 0,
                'last_alert': None
            }
        
        summary = {
            'total_alerts': len(self.alert_history),
            'critical_count': sum(1 for a in self.alert_history if a['level'] == 'critical'),
            'high_count': sum(1 for a in self.alert_history if a['level'] == 'high'),
            'medium_count': sum(1 for a in self.alert_history if a['level'] == 'medium'),
            'low_count': sum(1 for a in self.alert_history if a['level'] == 'low'),
            'last_alert': self.alert_history[-1] if self.alert_history else None
        }
        
        return summary
    
    def reset(self):
        """Reset alert system"""
        self.last_alert_time = {}
        self.alert_history = []
