"""
Bluetooth connectivity module for TGAM1 EEG sensor
Handles connection, data acquisition, and parsing of RAW EEG data
"""

import serial
import serial.tools.list_ports
import time
import struct
import logging
from typing import Optional, Dict, Callable
from config import BLUETOOTH_BAUD_RATE, BLUETOOTH_TIMEOUT, BLUETOOTH_RETRY_ATTEMPTS

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class TGAM1Connector:
    """
    Connector for TGAM1 EEG sensor via Bluetooth/Serial interface
    """
    
    def __init__(self, port: Optional[str] = None):
        self.port = port
        self.serial_conn: Optional[serial.Serial] = None
        self.is_connected = False
        self.data_callback: Optional[Callable] = None
        
    def find_available_ports(self) -> list:
        """Find available serial ports"""
        ports = serial.tools.list_ports.comports()
        return [port.device for port in ports]
    
    def connect(self, port: Optional[str] = None) -> bool:
        """
        Connect to TGAM1 device
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
            self.port = ports[0]
            logger.info(f"Auto-detected port: {self.port}")
        
        for attempt in range(BLUETOOTH_RETRY_ATTEMPTS):
            try:
                self.serial_conn = serial.Serial(
                    port=self.port,
                    baudrate=BLUETOOTH_BAUD_RATE,
                    timeout=BLUETOOTH_TIMEOUT,
                    bytesize=serial.EIGHTBITS,
                    parity=serial.PARITY_NONE,
                    stopbits=serial.STOPBITS_ONE
                )
                time.sleep(2)  # Wait for connection to stabilize
                self.is_connected = True
                logger.info(f"Connected to TGAM1 on {self.port}")
                return True
            except Exception as e:
                logger.warning(f"Connection attempt {attempt + 1} failed: {e}")
                if attempt < BLUETOOTH_RETRY_ATTEMPTS - 1:
                    time.sleep(1)
        
        logger.error("Failed to connect to TGAM1 device")
        return False
    
    def disconnect(self):
        """Disconnect from TGAM1 device"""
        if self.serial_conn and self.serial_conn.is_open:
            self.serial_conn.close()
            self.is_connected = False
            logger.info("Disconnected from TGAM1")
    
    def parse_packet(self, packet: bytes) -> Optional[Dict]:
        """
        Parse TGAM1 data packet
        TGAM1 protocol: [SYNC, SYNC, PLENGTH, PAYLOAD..., CHKSUM]
        """
        if len(packet) < 4:
            return None
        
        # Check for sync bytes (0xAA, 0xAA)
        if packet[0] != 0xAA or packet[1] != 0xAA:
            return None
        
        payload_length = packet[2]
        if len(packet) < 3 + payload_length + 1:
            return None
        
        payload = packet[3:3 + payload_length]
        checksum = packet[3 + payload_length]
        
        # Verify checksum
        calculated_checksum = (~sum(packet[2:3 + payload_length])) & 0xFF
        if checksum != calculated_checksum:
            return None
        
        data = {}
        i = 0
        while i < len(payload):
            code = payload[i]
            i += 1
            
            if code == 0x02:  # Poor signal quality
                if i < len(payload):
                    data['poor_signal'] = payload[i]
                    i += 1
            elif code == 0x04:  # Attention
                if i < len(payload):
                    data['attention'] = payload[i]
                    i += 1
            elif code == 0x05:  # Meditation
                if i < len(payload):
                    data['meditation'] = payload[i]
                    i += 1
            elif code == 0x80:  # Raw EEG value (2 bytes, big-endian)
                if i + 1 < len(payload):
                    raw_value = struct.unpack('>h', payload[i:i+2])[0]
                    data['raw_eeg'] = raw_value
                    i += 2
            elif code == 0x83:  # ASIC EEG power values
                if i + 24 < len(payload):
                    # 8 frequency bands, 3 bytes each
                    bands = []
                    for j in range(8):
                        band_value = struct.unpack('>I', b'\x00' + payload[i:i+3])[0]
                        bands.append(band_value)
                        i += 3
                    data['eeg_power'] = {
                        'delta': bands[0],
                        'theta': bands[1],
                        'low_alpha': bands[2],
                        'high_alpha': bands[3],
                        'low_beta': bands[4],
                        'high_beta': bands[5],
                        'low_gamma': bands[6],
                        'high_gamma': bands[7]
                    }
        
        return data if data else None
    
    def read_data(self) -> Optional[Dict]:
        """
        Read and parse data from TGAM1
        Returns:
            Dictionary containing EEG data or None if no valid data
        """
        if not self.is_connected or not self.serial_conn:
            return None
        
        try:
            if self.serial_conn.in_waiting > 0:
                data = self.serial_conn.read(self.serial_conn.in_waiting)
                parsed = self.parse_packet(data)
                if parsed and self.data_callback:
                    self.data_callback(parsed)
                return parsed
        except Exception as e:
            logger.error(f"Error reading data: {e}")
            return None
        
        return None
    
    def set_data_callback(self, callback: Callable):
        """Set callback function for received data"""
        self.data_callback = callback
    
    def __enter__(self):
        """Context manager entry"""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        self.disconnect()
