"""
Demo mode for testing the EEG fatigue detection system without hardware
Simulates EEG data to test visualization and processing pipeline
"""

import numpy as np
import time
import random
from signal_processor import SignalProcessor
from feature_extractor import FeatureExtractor
from ml_model import FatigueDetector
from alert_system import AlertSystem
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class DemoDataGenerator:
    """
    Generates simulated EEG data for testing
    """
    
    def __init__(self):
        self.time = 0.0
        self.base_attention = 70.0
        self.base_meditation = 60.0
        self.fatigue_level = 0.0  # Gradually increases
        
    def generate_sample(self) -> dict:
        """
        Generate a simulated EEG data sample
        """
        self.time += 0.1
        
        # Simulate gradual fatigue increase
        if self.time > 30:  # Start showing fatigue after 30 seconds
            self.fatigue_level = min(0.6, (self.time - 30) / 100.0)
        
        # Simulate attention (decreases with fatigue)
        attention = max(20, self.base_attention - self.fatigue_level * 50 + 
                       random.gauss(0, 5))
        
        # Simulate meditation (decreases with fatigue)
        meditation = max(15, self.base_meditation - self.fatigue_level * 40 + 
                        random.gauss(0, 5))
        
        # Simulate frequency bands (change with fatigue)
        # More fatigue = more alpha/theta, less beta
        alpha = 0.2 + self.fatigue_level * 0.3 + random.gauss(0, 0.05)
        beta = 0.3 - self.fatigue_level * 0.2 + random.gauss(0, 0.05)
        theta = 0.15 + self.fatigue_level * 0.2 + random.gauss(0, 0.05)
        delta = 0.1 + random.gauss(0, 0.03)
        gamma = 0.25 - self.fatigue_level * 0.1 + random.gauss(0, 0.05)
        
        # Normalize
        total = alpha + beta + theta + delta + gamma
        if total > 0:
            alpha /= total
            beta /= total
            theta /= total
            delta /= total
            gamma /= total
        
        return {
            'attention': attention,
            'meditation': meditation,
            'frequency_bands': {
                'alpha': alpha,
                'beta': beta,
                'theta': theta,
                'delta': delta,
                'gamma': gamma
            },
            'eeg_power': {
                'delta': int(delta * 1000000),
                'theta': int(theta * 1000000),
                'low_alpha': int(alpha * 500000),
                'high_alpha': int(alpha * 500000),
                'low_beta': int(beta * 500000),
                'high_beta': int(beta * 500000),
                'low_gamma': int(gamma * 500000),
                'high_gamma': int(gamma * 500000)
            }
        }


def run_demo():
    """
    Run demo mode with simulated data
    """
    print("=" * 60)
    print("EEG Fatigue Detection System - DEMO MODE")
    print("=" * 60)
    print("\nThis demo simulates EEG data to test the system.")
    print("You can observe how the system detects fatigue over time.")
    print("\nStarting demo...\n")
    
    # Initialize components
    signal_processor = SignalProcessor()
    feature_extractor = FeatureExtractor()
    ml_model = FatigueDetector()
    alert_system = AlertSystem()
    data_generator = DemoDataGenerator()
    
    # Set alert callback
    def on_alert(alert):
        print(f"\n🚨 ALERT [{alert['level'].upper()}]: {alert['message']}")
        print(f"   Fatigue Score: {alert['fatigue_score']:.3f}")
        print(f"   Cognitive Drift: {alert['cognitive_drift']:.3f}\n")
    
    alert_system.set_alert_callback(on_alert)
    
    print("Collecting baseline data (60 seconds)...")
    baseline_start = time.time()
    sample_count = 0
    
    try:
        while True:
            # Generate sample
            data = data_generator.generate_sample()
            
            # Process frequency bands
            frequency_bands = signal_processor.process_tgam_power_data(
                data['eeg_power']
            )
            band_ratios = signal_processor.calculate_band_ratios(frequency_bands)
            
            # Extract features
            feature_extractor.add_sample(
                data['attention'],
                data['meditation'],
                frequency_bands,
                band_ratios
            )
            
            sample_count += 1
            elapsed = time.time() - baseline_start
            
            # Check if baseline is established
            if elapsed >= 60 and feature_extractor.baseline_established:
                if sample_count == int(elapsed * 10) + 1:  # Print once
                    print("✓ Baseline established! Starting fatigue detection...\n")
                    print("Monitoring in progress... (Press Ctrl+C to stop)\n")
                    print("-" * 60)
            
            # After baseline, run predictions
            if feature_extractor.baseline_established and elapsed >= 60:
                features = feature_extractor.extract_features()
                predictions = ml_model.predict(features)
                
                # Check alerts
                alert_system.check_alerts(features, predictions)
                
                # Print status every 5 seconds
                if sample_count % 50 == 0:
                    print(f"\nTime: {elapsed:.1f}s")
                    print(f"  Attention: {data['attention']:.1f}")
                    print(f"  Meditation: {data['meditation']:.1f}")
                    print(f"  Fatigue Score: {predictions['fatigue_score']:.3f} "
                          f"({predictions['fatigue_level']})")
                    print(f"  Cognitive Drift: {predictions['cognitive_drift']:.3f}")
                    print(f"  Alpha: {frequency_bands['alpha']:.3f}, "
                          f"Beta: {frequency_bands['beta']:.3f}, "
                          f"Theta: {frequency_bands['theta']:.3f}")
            
            time.sleep(0.1)  # 10 Hz sampling rate
            
    except KeyboardInterrupt:
        print("\n\nDemo stopped by user.")
        print("\nSummary:")
        summary = alert_system.get_alert_summary()
        print(f"  Total Alerts: {summary['total_alerts']}")
        print(f"  Critical: {summary['critical_count']}")
        print(f"  High: {summary['high_count']}")
        print(f"  Medium: {summary['medium_count']}")
        print(f"  Low: {summary['low_count']}")
        print("\nThank you for using the EEG Fatigue Detection System!")


if __name__ == "__main__":
    run_demo()
