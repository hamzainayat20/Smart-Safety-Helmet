#include <Wire.h>
#include <DHT.h>

// =====================================================
// Pin definitions
// =====================================================

#define I2C_SDA_PIN 21
#define I2C_SCL_PIN 22

#define DHT_PIN 4
#define DHT_TYPE DHT22

// MQ-7 carbon-monoxide sensor module.
#define MQ7_ANALOG_PIN 34
#define MQ7_DIGITAL_PIN 27

// =====================================================
// MPU6500-compatible sensor configuration
// =====================================================

#define MPU_ADDRESS 0x68
#define MPU_WHO_AM_I 0x75
#define MPU_PWR_MGMT_1 0x6B
#define MPU_CONFIG 0x1A
#define MPU_GYRO_CONFIG 0x1B
#define MPU_ACCEL_CONFIG 0x1C
#define MPU_DATA_START 0x3B

DHT dht(DHT_PIN, DHT_TYPE);

struct SensorData {
  float accelerationX;
  float accelerationY;
  float accelerationZ;

  float gyroX;
  float gyroY;
  float gyroZ;

  float mpuTemperature;

  float temperature;
  float humidity;
  float heatIndex;

  // These are raw MQ-7/module values, not calibrated CO ppm.
  int mq7Raw;
  int mq7Digital;
  float mq7AdcVoltage;
  float mq7SensorVoltage;

  bool mpuValid;
  bool dhtValid;
  bool mq7Valid;
};

SensorData sensorData;

unsigned long previousMPUTime = 0;
unsigned long previousDHTTime = 0;
unsigned long previousMQ7Time = 0;
unsigned long previousPrintTime = 0;

const unsigned long MPU_INTERVAL = 200;
const unsigned long DHT_INTERVAL = 2000;
const unsigned long MQ7_INTERVAL = 500;
const unsigned long PRINT_INTERVAL = 2000;

bool writeMPURegister(uint8_t registerAddress, uint8_t value) {
  Wire.beginTransmission(MPU_ADDRESS);
  Wire.write(registerAddress);
  Wire.write(value);
  return Wire.endTransmission() == 0;
}

bool readMPURegister(uint8_t registerAddress, uint8_t &value) {
  Wire.beginTransmission(MPU_ADDRESS);
  Wire.write(registerAddress);

  if (Wire.endTransmission(false) != 0) {
    return false;
  }

  Wire.requestFrom(MPU_ADDRESS, 1);
  if (Wire.available() < 1) {
    return false;
  }

  value = Wire.read();
  return true;
}

bool initializeMPU() {
  uint8_t deviceID = 0;

  if (!readMPURegister(MPU_WHO_AM_I, deviceID)) {
    Serial.println("Could not communicate with MPU sensor.");
    return false;
  }

  Serial.print("MPU WHO_AM_I value: 0x");
  Serial.println(deviceID, HEX);

  if (deviceID != 0x70 && deviceID != 0x68) {
    Serial.println("Unexpected MPU device ID.");
    return false;
  }

  if (!writeMPURegister(MPU_PWR_MGMT_1, 0x00)) {
    return false;
  }

  delay(100);
  writeMPURegister(MPU_CONFIG, 0x03);
  writeMPURegister(MPU_GYRO_CONFIG, 0x00);
  writeMPURegister(MPU_ACCEL_CONFIG, 0x00);
  return true;
}

bool readMPUData() {
  Wire.beginTransmission(MPU_ADDRESS);
  Wire.write(MPU_DATA_START);

  if (Wire.endTransmission(false) != 0) {
    return false;
  }

  Wire.requestFrom(MPU_ADDRESS, 14);
  if (Wire.available() < 14) {
    return false;
  }

  int16_t rawAx = (Wire.read() << 8) | Wire.read();
  int16_t rawAy = (Wire.read() << 8) | Wire.read();
  int16_t rawAz = (Wire.read() << 8) | Wire.read();
  int16_t rawTemperature = (Wire.read() << 8) | Wire.read();
  int16_t rawGx = (Wire.read() << 8) | Wire.read();
  int16_t rawGy = (Wire.read() << 8) | Wire.read();
  int16_t rawGz = (Wire.read() << 8) | Wire.read();

  sensorData.accelerationX = rawAx / 16384.0;
  sensorData.accelerationY = rawAy / 16384.0;
  sensorData.accelerationZ = rawAz / 16384.0;

  sensorData.gyroX = rawGx / 131.0;
  sensorData.gyroY = rawGy / 131.0;
  sensorData.gyroZ = rawGz / 131.0;

  sensorData.mpuTemperature = (rawTemperature / 333.87) + 21.0;
  return true;
}

void readDHT22() {
  const float humidity = dht.readHumidity();
  const float temperature = dht.readTemperature();

  if (isnan(humidity) || isnan(temperature)) {
    sensorData.dhtValid = false;
    return;
  }

  sensorData.humidity = humidity;
  sensorData.temperature = temperature;
  sensorData.heatIndex = dht.computeHeatIndex(temperature, humidity, false);
  sensorData.dhtValid = true;
}

void readMQ7() {
  sensorData.mq7Raw = analogRead(MQ7_ANALOG_PIN);
  sensorData.mq7Digital = digitalRead(MQ7_DIGITAL_PIN);

  // Approximate voltage present at the ESP32 ADC pin.
  sensorData.mq7AdcVoltage = sensorData.mq7Raw * (3.3 / 4095.0);

  // Analog divider: upper 10k, lower 20k.
  // Divider factor = 20 / (10 + 20) = 0.6667.
  sensorData.mq7SensorVoltage = sensorData.mq7AdcVoltage * 1.5;
  sensorData.mq7Valid = true;
}

void printNullableFloat(float value, bool valid, int decimalPlaces) {
  if (valid) {
    Serial.print(value, decimalPlaces);
  } else {
    Serial.print("null");
  }
}

void printSensorData() {
  Serial.println();
  Serial.println("========================================");
  Serial.println("          ALL SENSOR READINGS");
  Serial.println("========================================");

  Serial.println();
  Serial.println("MPU MOTION SENSOR");

  if (sensorData.mpuValid) {
    Serial.print("Acceleration X: ");
    Serial.print(sensorData.accelerationX, 3);
    Serial.println(" g");
    Serial.print("Acceleration Y: ");
    Serial.print(sensorData.accelerationY, 3);
    Serial.println(" g");
    Serial.print("Acceleration Z: ");
    Serial.print(sensorData.accelerationZ, 3);
    Serial.println(" g");
    Serial.print("Gyroscope X: ");
    Serial.print(sensorData.gyroX, 2);
    Serial.println(" deg/s");
    Serial.print("Gyroscope Y: ");
    Serial.print(sensorData.gyroY, 2);
    Serial.println(" deg/s");
    Serial.print("Gyroscope Z: ");
    Serial.print(sensorData.gyroZ, 2);
    Serial.println(" deg/s");
    Serial.print("MPU temperature: ");
    Serial.print(sensorData.mpuTemperature, 2);
    Serial.println(" C");
  } else {
    Serial.println("MPU reading failed.");
  }

  Serial.println();
  Serial.println("DHT22");

  if (sensorData.dhtValid) {
    Serial.print("Temperature: ");
    Serial.print(sensorData.temperature, 2);
    Serial.println(" C");
    Serial.print("Humidity: ");
    Serial.print(sensorData.humidity, 2);
    Serial.println(" %");
    Serial.print("Heat index: ");
    Serial.print(sensorData.heatIndex, 2);
    Serial.println(" C");
  } else {
    Serial.println("DHT22 reading failed.");
  }

  Serial.println();
  Serial.println("MQ-7 CARBON MONOXIDE SENSOR");
  Serial.println("Values are raw/module voltages, not calibrated ppm.");

  if (sensorData.mq7Valid) {
    Serial.print("Raw analog value: ");
    Serial.println(sensorData.mq7Raw);
    Serial.print("ESP32 ADC voltage: ");
    Serial.print(sensorData.mq7AdcVoltage, 2);
    Serial.println(" V");
    Serial.print("Estimated sensor output: ");
    Serial.print(sensorData.mq7SensorVoltage, 2);
    Serial.println(" V");
    Serial.print("Digital output: ");
    Serial.println(sensorData.mq7Digital);

    if (sensorData.mq7Digital == LOW) {
      Serial.println("MQ-7 module comparator threshold exceeded.");
    } else {
      Serial.println("MQ-7 module comparator below configured threshold.");
    }
  } else {
    Serial.println("MQ-7 reading unavailable.");
  }

  Serial.println();
  Serial.println("APP-READY DATA:");
  Serial.print("{");

  Serial.print("\"temperature\":");
  printNullableFloat(sensorData.temperature, sensorData.dhtValid, 2);
  Serial.print(",\"humidity\":");
  printNullableFloat(sensorData.humidity, sensorData.dhtValid, 2);
  Serial.print(",\"heatIndex\":");
  printNullableFloat(sensorData.heatIndex, sensorData.dhtValid, 2);

  Serial.print(",\"accelX\":");
  printNullableFloat(sensorData.accelerationX, sensorData.mpuValid, 3);
  Serial.print(",\"accelY\":");
  printNullableFloat(sensorData.accelerationY, sensorData.mpuValid, 3);
  Serial.print(",\"accelZ\":");
  printNullableFloat(sensorData.accelerationZ, sensorData.mpuValid, 3);
  Serial.print(",\"gyroX\":");
  printNullableFloat(sensorData.gyroX, sensorData.mpuValid, 2);
  Serial.print(",\"gyroY\":");
  printNullableFloat(sensorData.gyroY, sensorData.mpuValid, 2);
  Serial.print(",\"gyroZ\":");
  printNullableFloat(sensorData.gyroZ, sensorData.mpuValid, 2);

  Serial.print(",\"mq7Raw\":");
  if (sensorData.mq7Valid) {
    Serial.print(sensorData.mq7Raw);
  } else {
    Serial.print("null");
  }
  Serial.print(",\"mq7Voltage\":");
  printNullableFloat(sensorData.mq7SensorVoltage, sensorData.mq7Valid, 2);
  Serial.print(",\"mq7Digital\":");
  if (sensorData.mq7Valid) {
    Serial.print(sensorData.mq7Digital);
  } else {
    Serial.print("null");
  }

  Serial.print(",\"mpuValid\":");
  Serial.print(sensorData.mpuValid ? "true" : "false");
  Serial.print(",\"dhtValid\":");
  Serial.print(sensorData.dhtValid ? "true" : "false");
  Serial.print(",\"mq7Valid\":");
  Serial.print(sensorData.mq7Valid ? "true" : "false");
  Serial.println("}");

  Serial.println("========================================");
}

void setup() {
  Serial.begin(115200);
  delay(2000);

  Serial.println();
  Serial.println("Starting multi-sensor system...");

  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
  Wire.setClock(100000);

  dht.begin();

  // Confirm that the module's digital output is 3.3V-safe before connecting
  // it directly to GPIO 27. Use a divider/level shifter if it outputs 5V.
  pinMode(MQ7_DIGITAL_PIN, INPUT);
  analogSetPinAttenuation(MQ7_ANALOG_PIN, ADC_11db);

  sensorData.mpuValid = initializeMPU();
  sensorData.dhtValid = false;
  sensorData.mq7Valid = false;

  Serial.println(sensorData.mpuValid
                     ? "MPU initialized successfully."
                     : "MPU initialization failed.");
  Serial.println("DHT22 initialized.");
  Serial.println("MQ-7 initialized for raw/module-level testing.");
  Serial.println("Multi-sensor system started.");
}

void loop() {
  const unsigned long currentTime = millis();

  if (currentTime - previousMPUTime >= MPU_INTERVAL) {
    previousMPUTime = currentTime;
    sensorData.mpuValid = readMPUData();
  }

  if (currentTime - previousDHTTime >= DHT_INTERVAL) {
    previousDHTTime = currentTime;
    readDHT22();
  }

  if (currentTime - previousMQ7Time >= MQ7_INTERVAL) {
    previousMQ7Time = currentTime;
    readMQ7();
  }

  if (currentTime - previousPrintTime >= PRINT_INTERVAL) {
    previousPrintTime = currentTime;
    printSensorData();
  }
}
