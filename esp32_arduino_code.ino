/*
 * ESP32/Arduino Code for Multi-Sensor EEG Fatigue Detection System
 * 
 * This code runs on ESP32/Arduino to:
 * 1. Connect to TGAM1 EEG sensor via Bluetooth/Serial
 * 2. Read additional sensors (Heart Rate, Temperature, GSR)
 * 3. Perform edge computing/preprocessing
 * 4. Send fused data to Python application
 * 
 * Hardware Connections:
 * - TGAM1: Connected via Bluetooth Serial (or wired Serial)
 * - Heart Rate Sensor (MAX30102): I2C (SDA, SCL)
 * - Temperature Sensor (DS18B20): Digital Pin 4
 * - GSR Sensor: Analog Pin A0
 * - Accelerometer (MPU6050): I2C (SDA, SCL)
 */

#include <Wire.h>
#include <SoftwareSerial.h>
#include <OneWire.h>
#include <DallasTemperature.h>

// Pin Definitions
#define GSR_PIN A0
#define TEMP_PIN 4
#define TGAM_RX 2  // For SoftwareSerial if needed
#define TGAM_TX 3

// I2C Addresses
#define MAX30102_ADDRESS 0x57
#define MPU6050_ADDRESS 0x68

// Sensor Objects
OneWire oneWire(TEMP_PIN);
DallasTemperature tempSensor(&oneWire);
SoftwareSerial tgamSerial(TGAM_RX, TGAM_TX);  // If using SoftwareSerial

// Data Structures
struct SensorData {
  float heartRate;
  float temperature;
  int gsr;
  float accelX, accelY, accelZ;
  String eegData;
  unsigned long timestamp;
};

SensorData currentData;

void setup() {
  Serial.begin(115200);  // Communication with Python
  tgamSerial.begin(57600);  // TGAM1 baud rate
  
  // Initialize I2C
  Wire.begin();
  
  // Initialize sensors
  tempSensor.begin();
  initMAX30102();
  initMPU6050();
  
  delay(1000);
  Serial.println("ESP32 Multi-Sensor Hub Ready");
}

void loop() {
  // Read all sensors
  readHeartRate();
  readTemperature();
  readGSR();
  readAccelerometer();
  readTGAM1();
  
  // Create JSON payload
  String jsonData = createJSON();
  
  // Send to Python application
  Serial.println(jsonData);
  
  delay(100);  // 10 Hz sampling rate
}

void readHeartRate() {
  // MAX30102 Heart Rate Reading
  // Simplified version - implement full MAX30102 library for production
  Wire.beginTransmission(MAX30102_ADDRESS);
  Wire.write(0x07);  // FIFO_WR_PTR
  Wire.endTransmission();
  
  Wire.requestFrom(MAX30102_ADDRESS, 1);
  if (Wire.available()) {
    // Read heart rate data
    // This is simplified - use proper MAX30102 library
    currentData.heartRate = 72.0;  // Placeholder
  }
}

void readTemperature() {
  tempSensor.requestTemperatures();
  currentData.temperature = tempSensor.getTempCByIndex(0);
}

void readGSR() {
  int gsrValue = analogRead(GSR_PIN);
  currentData.gsr = gsrValue;
}

void readAccelerometer() {
  // MPU6050 Accelerometer Reading
  Wire.beginTransmission(MPU6050_ADDRESS);
  Wire.write(0x3B);  // ACCEL_XOUT_H register
  Wire.endTransmission(false);
  Wire.requestFrom(MPU6050_ADDRESS, 6, true);
  
  if (Wire.available() >= 6) {
    int16_t accelX_raw = (Wire.read() << 8) | Wire.read();
    int16_t accelY_raw = (Wire.read() << 8) | Wire.read();
    int16_t accelZ_raw = (Wire.read() << 8) | Wire.read();
    
    currentData.accelX = accelX_raw / 16384.0;  // Convert to g
    currentData.accelY = accelY_raw / 16384.0;
    currentData.accelZ = accelZ_raw / 16384.0;
  }
}

void readTGAM1() {
  // Read TGAM1 data from Serial/Bluetooth
  if (tgamSerial.available()) {
    currentData.eegData = tgamSerial.readStringUntil('\n');
  }
}

String createJSON() {
  String json = "{";
  json += "\"heart_rate\":" + String(currentData.heartRate) + ",";
  json += "\"temperature\":" + String(currentData.temperature) + ",";
  json += "\"gsr\":" + String(currentData.gsr) + ",";
  json += "\"accelerometer\":{";
  json += "\"x\":" + String(currentData.accelX) + ",";
  json += "\"y\":" + String(currentData.accelY) + ",";
  json += "\"z\":" + String(currentData.accelZ);
  json += "},";
  json += "\"eeg_data\":\"" + currentData.eegData + "\",";
  json += "\"timestamp\":" + String(millis());
  json += "}";
  
  return json;
}

void initMAX30102() {
  // Initialize MAX30102 heart rate sensor
  Wire.beginTransmission(MAX30102_ADDRESS);
  Wire.write(0x09);  // MODE_CONFIG
  Wire.write(0x02);  // SpO2 mode
  Wire.endTransmission();
  
  Wire.beginTransmission(MAX30102_ADDRESS);
  Wire.write(0x0A);  // SPO2_CONFIG
  Wire.write(0x27);  // Sample rate 100Hz, LED pulse width 411us
  Wire.endTransmission();
}

void initMPU6050() {
  // Initialize MPU6050 accelerometer
  Wire.beginTransmission(MPU6050_ADDRESS);
  Wire.write(0x6B);  // PWR_MGMT_1
  Wire.write(0x00);  // Wake up
  Wire.endTransmission();
  
  Wire.beginTransmission(MPU6050_ADDRESS);
  Wire.write(0x1C);  // ACCEL_CONFIG
  Wire.write(0x00);  // ±2g range
  Wire.endTransmission();
}
