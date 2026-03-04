"""
ESP32/Arduino integration module for enhanced multi-sensor data acquisition
Supports additional sensors: Heart Rate, Temperature, Accelerometer, GSR
"""

import serial
import serial.tools.list_ports
import time
import json
import struct
import logging
from typing import Optional, Dict, Callable, List
from config import BLUETOOTH_BAUD_RATE

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class ESP32Connector:
    """
    Connector for ESP32/Arduino hub that aggregates multiple sensors
    ESP32 acts as data hub: TGAM1 + Heart Rate + Temperature + Accelerometer
    """
    
    def __init__(self, port: Optional[str] = None, baud_rate: int = 115200):
        self.port = port
        self.baud_rate = baud_rate
        self.serial_conn: Optional[serial.Serial] = None
        self.is_connected = False
        self.data_callback: Optional[Callable] = None
        
        # Sensor availability flags
        self.has_heart_rate = False
        self.has_temperature = False
        self.has_accelerometer = False
        self.has_gsr = False
        
    def find_available_ports(self) -> List[str]:
        """Find available serial ports"""
        ports = serial.tools.list_ports.comports()
        return [port.device for port in ports]
    
    def connect(self, port: Optional[str] = None) -> bool:
        """
        Connect to ESP32/Arduino device
        Args:
            port: Serial port name (e.g., 'COM3' on Windows, '/dev/ttyUSB0' on Linux)
        Returns:
            True if connection successful, False otherwise
        """
        if port:
            self.port = port
        
        if not self.port:
            # Auto-detect port
            ports = self.find_available_ports()
            if not ports:
                logger.error("No serial ports found")
                return False
            # Prefer ports that might be ESP32 (often higher COM numbers)
            self.port = ports[-1] if len(ports) > 1 else ports[0]
            logger.info(f"Auto-detected port: {self.port}")
        
        try:
            self.serial_conn = serial.Serial(
                port=self.port,
                baudrate=self.baud_rate,
                timeout=1.0,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE
            )
            time.sleep(2)  # Wait for ESP32 to initialize
            
            # Send initialization command
            self.serial_conn.write(b"INIT\n")
            time.sleep(0.5)
            
            # Read sensor configuration
            response = self._read_line()
            if response:
                config = self._parse_config(response)
                self.has_heart_rate = config.get('heart_rate', False)
                self.has_temperature = config.get('temperature', False)
                self.has_accelerometer = config.get('accelerometer', False)
                self.has_gsr = config.get('gsr', False)
                
                logger.info(f"ESP32 connected. Sensors: HR={self.has_heart_rate}, "
                          f"Temp={self.has_temperature}, Accel={self.has_accelerometer}, "
                          f"GSR={self.has_gsr}")
            
            self.is_connected = True
            return True
            
        except Exception as e:
            logger.error(f"Failed to connect to ESP32: {e}")
            return False
    
    def disconnect(self):
        """Disconnect from ESP32 device"""
        if self.serial_conn and self.serial_conn.is_open:
            self.serial_conn.write(b"STOP\n")
            time.sleep(0.5)
            self.serial_conn.close()
            self.is_connected = False
            logger.info("Disconnected from ESP32")
    
    def _read_line(self) -> Optional[str]:
        """Read a line from serial port"""
        if not self.serial_conn or not self.serial_conn.in_waiting:
            return None
        try:
            line = self.serial_conn.readline().decode('utf-8').strip()
            return line if line else None
        except:
            return None
    
    def _parse_config(self, config_str: str) -> Dict:
        """Parse sensor configuration JSON"""
        try:
            return json.loads(config_str)
        except:
            return {}
    
    def read_data(self) -> Optional[Dict]:
        """
        Read multi-sensor data from ESP32
        Expected JSON format:
        {
            "eeg": {"attention": 75, "meditation": 60, "raw": 1234, "power": {...}},
            "heart_rate": 72,
            "temperature": 36.5,
            "accelerometer": {"x": 0.1, "y": 0.2, "z": 0.9},
            "gsr": 450,
            "timestamp": 1234567890
        }
        """
        if not self.is_connected or not self.serial_conn:
            return None
        
        try:
            line = self._read_line()
            if not line:
                return None
            
            # Parse JSON data
            data = json.loads(line)
            
            # Call callback if set
            if self.data_callback:
                self.data_callback(data)
            
            return data
            
        except json.JSONDecodeError:
            logger.warning("Failed to parse JSON data")
            return None
        except Exception as e:
            logger.error(f"Error reading data: {e}")
            return None
    
    def send_command(self, command: str) -> bool:
        """Send command to ESP32"""
        if not self.is_connected or not self.serial_conn:
            return False
        try:
            self.serial_conn.write(f"{command}\n".encode('utf-8'))
            return True
        except:
            return False
    
    def set_data_callback(self, callback: Callable):
        """Set callback function for received data"""
        self.data_callback = callback
    
    def __enter__(self):
        """Context manager entry"""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        self.disconnect()


class MultiSensorFusion:
    """
    Multi-sensor fusion for improved fatigue detection accuracy
    Combines EEG, Heart Rate, Temperature, and Accelerometer data
    """
    
    def __init__(self):
        self.eeg_weight = 0.5      # EEG is primary sensor
        self.hr_weight = 0.2        # Heart rate variability
        self.temp_weight = 0.1      # Temperature changes
        self.accel_weight = 0.1     # Activity level
        self.gsr_weight = 0.1       # Stress indicator
        
    def fuse_data(self, eeg_data: Dict, sensor_data: Dict) -> Dict:
        """
        Fuse multi-sensor data for enhanced fatigue detection
        Args:
            eeg_data: EEG data from TGAM1
            sensor_data: Additional sensor data from ESP32
        Returns:
            Fused data dictionary with enhanced features
        """
        fused = {
            'eeg': eeg_data,
            'sensors': sensor_data,
            'fused_features': {}
        }
        
        # Extract features from each sensor
        features = {}
        
        # EEG features (already processed)
        if 'attention' in eeg_data:
            features['attention'] = eeg_data['attention']
        if 'meditation' in eeg_data:
            features['meditation'] = eeg_data['meditation']
        if 'frequency_bands' in eeg_data:
            features.update(eeg_data['frequency_bands'])
        
        # Heart Rate features
        if 'heart_rate' in sensor_data:
            hr = sensor_data['heart_rate']
            features['heart_rate'] = hr
            # HR variability indicates stress/fatigue
            features['hr_variability'] = self._calculate_hr_variability(hr)
        
        # Temperature features
        if 'temperature' in sensor_data:
            temp = sensor_data['temperature']
            features['temperature'] = temp
            # Temperature changes can indicate fatigue
            features['temp_deviation'] = abs(temp - 36.5)  # Normal body temp
        
        # Accelerometer features
        if 'accelerometer' in sensor_data:
            accel = sensor_data['accelerometer']
            features['activity_level'] = self._calculate_activity_level(accel)
            features['movement'] = self._detect_movement(accel)
        
        # GSR features
        if 'gsr' in sensor_data:
            gsr = sensor_data['gsr']
            features['gsr'] = gsr
            features['stress_level'] = self._gsr_to_stress(gsr)
        
        # Calculate fused fatigue score
        fused['fused_features'] = features
        fused['fused_fatigue_score'] = self._calculate_fused_fatigue(features)
        
        return fused
    
    def _calculate_hr_variability(self, hr: float) -> float:
        """Calculate heart rate variability indicator"""
        # Normal HR: 60-100 bpm
        # High variability indicates stress/fatigue
        if 60 <= hr <= 100:
            return 0.0  # Normal
        elif hr < 60 or hr > 100:
            return 0.3  # Elevated
        return 0.5  # High variability
    
    def _calculate_activity_level(self, accel: Dict) -> float:
        """Calculate activity level from accelerometer"""
        x, y, z = accel.get('x', 0), accel.get('y', 0), accel.get('z', 0)
        magnitude = (x**2 + y**2 + z**2) ** 0.5
        # Normalize to 0-1 (assuming max ~2g)
        return min(magnitude / 2.0, 1.0)
    
    def _detect_movement(self, accel: Dict) -> bool:
        """Detect if user is moving"""
        activity = self._calculate_activity_level(accel)
        return activity > 0.1
    
    def _gsr_to_stress(self, gsr: float) -> float:
        """Convert GSR to stress level (0-1)"""
        # GSR typically ranges from 200-1000
        # Higher GSR = higher stress
        normalized = (gsr - 200) / 800.0
        return min(max(normalized, 0.0), 1.0)
    
    def _calculate_fused_fatigue(self, features: Dict) -> float:
        """
        Calculate fused fatigue score using multi-sensor data
        Returns value between 0 (no fatigue) and 1 (severe fatigue)
        """
        score_components = []
        
        # EEG-based fatigue (from existing system)
        if 'attention' in features:
            attn_score = 1.0 - (features['attention'] / 100.0)
            score_components.append(attn_score * self.eeg_weight)
        
        if 'meditation' in features:
            med_score = 1.0 - (features['meditation'] / 100.0)
            score_components.append(med_score * self.eeg_weight * 0.5)
        
        # Heart rate variability
        if 'hr_variability' in features:
            score_components.append(features['hr_variability'] * self.hr_weight)
        
        # Temperature deviation
        if 'temp_deviation' in features:
            temp_score = min(features['temp_deviation'] / 2.0, 1.0)
            score_components.append(temp_score * self.temp_weight)
        
        # Activity level (low activity = potential fatigue)
        if 'activity_level' in features:
            activity_score = 1.0 - features['activity_level']
            score_components.append(activity_score * self.accel_weight)
        
        # Stress level from GSR
        if 'stress_level' in features:
            score_components.append(features['stress_level'] * self.gsr_weight)
        
        if score_components:
            fused_score = sum(score_components)
            return min(max(fused_score, 0.0), 1.0)
        
        return 0.0
