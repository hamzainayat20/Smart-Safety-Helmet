#pragma once

#include <cstddef>
#include <cstdint>

namespace smart_safety {

struct Dht22RawReading {
  double temperatureC;
  double humidityPct;
  double heatIndexC;
};

class Dht22Reader {
 public:
  virtual ~Dht22Reader() = default;
  virtual bool read(Dht22RawReading& reading) = 0;
};

class I2cBus {
 public:
  virtual ~I2cBus() = default;
  virtual void setTimeoutMs(std::uint32_t timeoutMs) = 0;
  virtual bool readRegister(std::uint8_t deviceAddress,
                            std::uint8_t registerAddress,
                            std::uint8_t& value) = 0;
  virtual bool writeRegister(std::uint8_t deviceAddress,
                             std::uint8_t registerAddress,
                             std::uint8_t value) = 0;
  virtual bool readRegisters(std::uint8_t deviceAddress,
                             std::uint8_t startRegister,
                             std::uint8_t* output,
                             std::size_t length) = 0;
};

}  // namespace smart_safety

