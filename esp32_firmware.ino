/*
 * ESP32 Firmware for Multi-Sensor EEG Fatigue Detection System
 * 
 * This firmware runs on ESP32 to:
 * 1. Connect to TGAM1 EEG sensor via Bluetooth
 * 2. Read additional sensors (Heart Rate, Temperature, Accelerometer)
 * 3. Aggregate and send data to PC via Serial/USB
 * 
 * Hardware Connections:
 * - MAX30102 (Heart Rate): SDA=21, SCL=22
 * - DS18B20 (Temperature): GPIO 4
 * - MPU6050 (Accelerometer): SDA=21, SCL=22
 * - GSR Sensor: GPIO 34 (ADC)
 * 
 * Libraries Required:
 * - Wire.h (I2C)
 * - MAX30102 library
 * - OneWire.h, DallasTemperature.h
 * - MPU6050 library
 * - BluetoothSerial.h (for TGAM1)
 */

#include <Wire.h>
#include <BluetoothSerial.h>
#include <OneWire.h>
#include <DallasTemperature.h>

// Pin definitions
#define TEMP_PIN 4
#define GSR_PIN 34

// Sensor objects
BluetoothSerial SerialBT;
OneWire oneWire(TEMP_PIN);
DallasTemperature tempSensor(&oneWire);

// Sensor availability flags
bool hasHeartRate = false;
bool hasTemperature = true;
bool hasAccelerometer = false;
bool hasGSR = true;

// Data structures
struct SensorData {
  float heartRate = 0;
  float temperature = 0;
  float accelX = 0, accelY = 0, accelZ = 0;
  float gsr = 0;
  unsigned long timestamp = 0;
};

SensorData sensorData;

// TGAM1 data structure
struct EEGData {
  int attention = 0;
  int meditation = 0;
  int rawEEG = 0;
  // Add frequency bands if available
  unsigned long timestamp = 0;
};

EEGData eegData;

void setup() {
  Serial.begin(115200);
  Wire.begin();
  
  // Initialize Bluetooth for TGAM1
  SerialBT.begin("ESP32_EEG_Hub");
  
  // Initialize temperature sensor
  tempSensor.begin();
  
  // Initialize ADC for GSR
  pinMode(GSR_PIN, INPUT);
  
  // Send configuration to PC
  sendConfig();
  
  delay(1000);
  Serial.println("ESP32 Multi-Sensor Hub Ready");
}

void loop() {
  unsigned long currentTime = millis();
  
  // Read all sensors
  readTemperature();
  readGSR();
  // readHeartRate();  // Uncomment if MAX30102 connected
  // readAccelerometer();  // Uncomment if MPU6050 connected
  
  // Read TGAM1 data via Bluetooth
  readTGAM1();
  
  // Send aggregated data to PC
  sendAggregatedData();
  
  delay(100);  // 10 Hz update rate
}

void sendConfig() {
  // Send sensor configuration as JSON
  Serial.print("CONFIG:");
  Serial.print("{");
  Serial.print("\"heart_rate\":");
  Serial.print(hasHeartRate ? "true" : "false");
  Serial.print(",\"temperature\":");
  Serial.print(hasTemperature ? "true" : "false");
  Serial.print(",\"accelerometer\":");
  Serial.print(hasAccelerometer ? "true" : "false");
  Serial.print(",\"gsr\":");
  Serial.print(hasGSR ? "true" : "false");
  Serial.println("}");
}

void readTemperature() {
  if (hasTemperature) {
    tempSensor.requestTemperatures();
    sensorData.temperature = tempSensor.getTempCByIndex(0);
  }
}

void readGSR() {
  if (hasGSR) {
    int rawValue = analogRead(GSR_PIN);
    // Convert ADC value (0-4095) to GSR reading
    sensorData.gsr = map(rawValue, 0, 4095, 200, 1000);
  }
}

void readHeartRate() {
  // Implement MAX30102 reading
  // This is a placeholder - implement based on your MAX30102 library
  if (hasHeartRate) {
    // sensorData.heartRate = readMAX30102();
  }
}

void readAccelerometer() {
  // Implement MPU6050 reading
  // This is a placeholder - implement based on your MPU6050 library
  if (hasAccelerometer) {
    // Read MPU6050 data
    // sensorData.accelX = ...
    // sensorData.accelY = ...
    // sensorData.accelZ = ...
  }
}

void readTGAM1() {
  // Read TGAM1 data from Bluetooth
  if (SerialBT.available()) {
    // Parse TGAM1 packets
    // This is simplified - implement full TGAM1 protocol parsing
    byte data[32];
    int bytesRead = SerialBT.readBytes(data, 32);
    
    if (bytesRead > 0) {
      // Parse TGAM1 packet (simplified)
      // Full implementation needed based on TGAM1 protocol
      // eegData.attention = parseAttention(data);
      // eegData.meditation = parseMeditation(data);
      // eegData.rawEEG = parseRawEEG(data);
    }
  }
}

void sendAggregatedData() {
  // Send JSON formatted data to PC
  Serial.print("{");
  
  // EEG data
  Serial.print("\"eeg\":{");
  Serial.print("\"attention\":");
  Serial.print(eegData.attention);
  Serial.print(",\"meditation\":");
  Serial.print(eegData.meditation);
  Serial.print(",\"raw\":");
  Serial.print(eegData.rawEEG);
  Serial.print("}");
  
  // Heart Rate
  if (hasHeartRate) {
    Serial.print(",\"heart_rate\":");
    Serial.print(sensorData.heartRate);
  }
  
  // Temperature
  if (hasTemperature) {
    Serial.print(",\"temperature\":");
    Serial.print(sensorData.temperature);
  }
  
  // Accelerometer
  if (hasAccelerometer) {
    Serial.print(",\"accelerometer\":{");
    Serial.print("\"x\":");
    Serial.print(sensorData.accelX);
    Serial.print(",\"y\":");
    Serial.print(sensorData.accelY);
    Serial.print(",\"z\":");
    Serial.print(sensorData.accelZ);
    Serial.print("}");
  }
  
  // GSR
  if (hasGSR) {
    Serial.print(",\"gsr\":");
    Serial.print(sensorData.gsr);
  }
  
  // Timestamp
  Serial.print(",\"timestamp\":");
  Serial.print(millis());
  
  Serial.println("}");
}

// Handle commands from PC
void handleCommand(String command) {
  if (command == "INIT") {
    sendConfig();
  } else if (command == "STOP") {
    // Stop data transmission
  }
}

void serialEvent() {
  if (Serial.available()) {
    String command = Serial.readStringUntil('\n');
    command.trim();
    handleCommand(command);
  }
}
