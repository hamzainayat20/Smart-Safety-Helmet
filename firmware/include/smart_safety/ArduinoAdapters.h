#pragma once

#ifdef ARDUINO

#include <Arduino.h>
#include <DHT.h>
#include <Wire.h>

#include "smart_safety/HardwareInterfaces.h"

namespace smart_safety {

class ArduinoDht22Reader final : public Dht22Reader {
 public:
  explicit ArduinoDht22Reader(DHT& dht) : dht_(dht) {}

  bool read(Dht22RawReading& reading) override {
    const float humidity = dht_.readHumidity();
    const float temperature = dht_.readTemperature();
    if (!isfinite(humidity) || !isfinite(temperature)) return false;
    const float heatIndex = dht_.computeHeatIndex(temperature, humidity, false);
    if (!isfinite(heatIndex)) return false;
    reading = Dht22RawReading{temperature, humidity, heatIndex};
    return true;
  }

 private:
  DHT& dht_;
};

// ADC1 input (GPIO32-39). 11 dB attenuation gives the widest input span the
// ESP32 ADC supports (about 0-3.1 V usable); the pin itself must never see
// more than 3.3 V, which the external divider has to guarantee.
class ArduinoAnalogInput final : public AnalogInput {
 public:
  explicit ArduinoAnalogInput(int pin) : pin_(pin) {}

  void begin() {
    analogReadResolution(12);
    analogSetPinAttenuation(pin_, ADC_11db);
  }

  bool read(int& raw) override {
    raw = analogRead(pin_);
    return raw >= 0 && raw <= 4095;
  }

 private:
  int pin_;
};

class ArduinoTwoWireBus final : public I2cBus {
 public:
  explicit ArduinoTwoWireBus(TwoWire& wire) : wire_(wire) {}

  void setTimeoutMs(std::uint32_t timeoutMs) override {
    wire_.setTimeOut(timeoutMs);
  }

  bool readRegister(std::uint8_t deviceAddress,
                    std::uint8_t registerAddress,
                    std::uint8_t& value) override {
    return readRegisters(deviceAddress, registerAddress, &value, 1);
  }

  bool writeRegister(std::uint8_t deviceAddress,
                     std::uint8_t registerAddress,
                     std::uint8_t value) override {
    wire_.beginTransmission(deviceAddress);
    wire_.write(registerAddress);
    wire_.write(value);
    return wire_.endTransmission(true) == 0;
  }

  bool readRegisters(std::uint8_t deviceAddress,
                     std::uint8_t startRegister,
                     std::uint8_t* output,
                     std::size_t length) override {
    wire_.beginTransmission(deviceAddress);
    wire_.write(startRegister);
    if (wire_.endTransmission(false) != 0) return false;

    const auto requested = wire_.requestFrom(
        static_cast<int>(deviceAddress), static_cast<int>(length),
        static_cast<int>(true));
    if (requested != length || wire_.available() < static_cast<int>(length)) {
      while (wire_.available() > 0) wire_.read();
      return false;
    }
    for (std::size_t index = 0; index < length; ++index) {
      output[index] = static_cast<std::uint8_t>(wire_.read());
    }
    return true;
  }

 private:
  TwoWire& wire_;
};

}  // namespace smart_safety

#endif

