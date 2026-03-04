"""
ESP32/Arduino Integration Module for Enhanced EEG Fatigue Detection
Adds multi-sensor fusion and edge computing capabilities
"""

import serial
import json
import time
import logging
from typing import Optional, Dict, List
from config import BLUETOOTH_BAUD_RATE

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class ESP32Connector:
    """
    Connector for ESP32/Arduino-based sensor hub
    Enables multi-sensor data fusion for improved accuracy
    """
    
    def __init__(self, port: Optional[str] = None, baud_rate: int = 115200):
        self.port = port
        self.baud_rate = baud_rate
        self.serial_conn: Optional[serial.Serial] = None
        self.is_connected = False
        
    def connect(self, port: Optional[str] = None) -> bool:
        """Connect to ESP32/Arduino device"""
        if port:
            self.port = port
        
        try:
            self.serial_conn = serial.Serial(
                port=self.port,
                baudrate=self.baud_rate,
                timeout=1.0
            )
            time.sleep(2)  # Wait for ESP32 to initialize
            self.is_connected = True
            logger.info(f"Connected to ESP32 on {self.port}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to ESP32: {e}")
            return False
    
    def read_sensor_data(self) -> Optional[Dict]:
        """
        Read multi-sensor data from ESP32
        Expected JSON format:
        {
            "eeg": {...},           # TGAM1 data forwarded by ESP32
            "heart_rate": 72,       # BPM from heart rate sensor
            "temperature": 36.5,    # Body temperature
            "gsr": 450,             # Galvanic Skin Response (stress)
            "accelerometer": {...}, # Movement data
            "timestamp": 1234567890
        }
        """
        if not self.is_connected or not self.serial_conn:
            return None
        
        try:
            if self.serial_conn.in_waiting > 0:
                line = self.serial_conn.readline().decode('utf-8').strip()
                if line:
                    data = json.loads(line)
                    return data
        except json.JSONDecodeError:
            logger.warning("Invalid JSON received from ESP32")
        except Exception as e:
            logger.error(f"Error reading ESP32 data: {e}")
        
        return None
    
    def disconnect(self):
        """Disconnect from ESP32"""
        if self.serial_conn and self.serial_conn.is_open:
            self.serial_conn.close()
            self.is_connected = False
            logger.info("Disconnected from ESP32")


class MultiSensorFusion:
    """
    Multi-sensor data fusion for enhanced fatigue detection accuracy
    Combines EEG, heart rate, temperature, GSR, and movement data
    """
    
    def __init__(self):
        self.sensor_history = {
            'heart_rate': [],
            'temperature': [],
            'gsr': [],
            'movement': []
        }
        self.baseline_values = {}
        self.baseline_established = False
    
    def add_sensor_data(self, sensor_data: Dict):
        """Add multi-sensor data sample"""
        if 'heart_rate' in sensor_data:
            self.sensor_history['heart_rate'].append(sensor_data['heart_rate'])
            if len(self.sensor_history['heart_rate']) > 100:
                self.sensor_history['heart_rate'].pop(0)
        
        if 'temperature' in sensor_data:
            self.sensor_history['temperature'].append(sensor_data['temperature'])
            if len(self.sensor_history['temperature']) > 100:
                self.sensor_history['temperature'].pop(0)
        
        if 'gsr' in sensor_data:
            self.sensor_history['gsr'].append(sensor_data['gsr'])
            if len(self.sensor_history['gsr']) > 100:
                self.sensor_history['gsr'].pop(0)
        
        # Establish baseline
        if not self.baseline_established and all(
            len(history) >= 30 for history in self.sensor_history.values()
        ):
            self._establish_baseline()
    
    def _establish_baseline(self):
        """Establish baseline values for physiological sensors"""
        if self.sensor_history['heart_rate']:
            self.baseline_values['heart_rate'] = sum(
                self.sensor_history['heart_rate']) / len(self.sensor_history['heart_rate'])
        if self.sensor_history['temperature']:
            self.baseline_values['temperature'] = sum(
                self.sensor_history['temperature']) / len(self.sensor_history['temperature'])
        if self.sensor_history['gsr']:
            self.baseline_values['gsr'] = sum(
                self.sensor_history['gsr']) / len(self.sensor_history['gsr'])
        
        self.baseline_established = True
        logger.info("Multi-sensor baseline established")
    
    def extract_physiological_features(self) -> Dict[str, float]:
        """
        Extract features from physiological sensors
        Returns enhanced features for fatigue detection
        """
        features = {}
        
        # Heart Rate Variability (HRV) - indicator of stress/fatigue
        if len(self.sensor_history['heart_rate']) >= 10:
            hr_values = self.sensor_history['heart_rate'][-10:]
            features['hr_mean'] = sum(hr_values) / len(hr_values)
            features['hr_std'] = self._calculate_std(hr_values)
            features['hr_variability'] = features['hr_std'] / features['hr_mean'] if features['hr_mean'] > 0 else 0
            
            # HR deviation from baseline
            if 'heart_rate' in self.baseline_values:
                features['hr_deviation'] = abs(
                    features['hr_mean'] - self.baseline_values['heart_rate']
                ) / self.baseline_values['heart_rate']
        
        # Temperature features
        if len(self.sensor_history['temperature']) >= 10:
            temp_values = self.sensor_history['temperature'][-10:]
            features['temp_mean'] = sum(temp_values) / len(temp_values)
            features['temp_trend'] = self._calculate_trend(temp_values)
            
            # Temperature elevation can indicate stress
            if 'temperature' in self.baseline_values:
                features['temp_elevation'] = (
                    features['temp_mean'] - self.baseline_values['temperature']
                )
        
        # Galvanic Skin Response (GSR) - stress indicator
        if len(self.sensor_history['gsr']) >= 10:
            gsr_values = self.sensor_history['gsr'][-10:]
            features['gsr_mean'] = sum(gsr_values) / len(gsr_values)
            features['gsr_std'] = self._calculate_std(gsr_values)
            
            # High GSR indicates stress/fatigue
            if 'gsr' in self.baseline_values:
                features['gsr_increase'] = (
                    features['gsr_mean'] - self.baseline_values['gsr']
                ) / self.baseline_values['gsr']
        
        # Composite physiological stress score
        stress_indicators = []
        if 'hr_deviation' in features:
            stress_indicators.append(min(features['hr_deviation'], 1.0))
        if 'gsr_increase' in features:
            stress_indicators.append(min(features['gsr_increase'], 1.0))
        if 'temp_elevation' in features and features['temp_elevation'] > 0.5:
            stress_indicators.append(0.3)  # Moderate contribution
        
        if stress_indicators:
            features['physiological_stress'] = sum(stress_indicators) / len(stress_indicators)
        else:
            features['physiological_stress'] = 0.0
        
        return features
    
    def _calculate_std(self, values: List[float]) -> float:
        """Calculate standard deviation"""
        if len(values) < 2:
            return 0.0
        mean = sum(values) / len(values)
        variance = sum((x - mean) ** 2 for x in values) / len(values)
        return variance ** 0.5
    
    def _calculate_trend(self, values: List[float]) -> float:
        """Calculate linear trend"""
        if len(values) < 2:
            return 0.0
        n = len(values)
        x = list(range(n))
        x_mean = sum(x) / n
        y_mean = sum(values) / n
        
        numerator = sum((x[i] - x_mean) * (values[i] - y_mean) for i in range(n))
        denominator = sum((x[i] - x_mean) ** 2 for i in range(n))
        
        return numerator / denominator if denominator != 0 else 0.0
    
    def fuse_with_eeg_features(self, eeg_features: Dict, 
                               physiological_features: Dict) -> Dict:
        """
        Fuse EEG features with physiological sensor features
        Creates comprehensive feature vector for improved accuracy
        """
        fused_features = eeg_features.copy()
        fused_features.update(physiological_features)
        
        # Cross-modal correlations
        if 'attention_mean' in eeg_features and 'hr_mean' in physiological_features:
            # Attention-Heart Rate correlation
            fused_features['attention_hr_correlation'] = (
                eeg_features['attention_mean'] / 100.0
            ) * (1.0 - abs(physiological_features['hr_mean'] - 72) / 72.0)
        
        if 'fatigue_score' in eeg_features and 'physiological_stress' in physiological_features:
            # Combined fatigue score (EEG + physiological)
            eeg_fatigue = eeg_features.get('fatigue_score', 0.0)
            physio_stress = physiological_features.get('physiological_stress', 0.0)
            
            # Weighted combination (60% EEG, 40% physiological)
            fused_features['combined_fatigue_score'] = (
                0.6 * eeg_fatigue + 0.4 * physio_stress
            )
        
        return fused_features
