cmake_minimum_required(VERSION 3.16)
project(smart_safety_firmware_host_tests LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(
  firmware_host_tests
  test_firmware.cpp
  ../../src/DHT22Sensor.cpp
  ../../src/MPU6500Sensor.cpp
  ../../src/FallDetectionEngine.cpp
  ../../src/EventIdGenerator.cpp
  ../../src/TelemetryBuilder.cpp
  ../../src/SensorManager.cpp
  ../../src/SecureIngestionProtocol.cpp
)

target_include_directories(firmware_host_tests PRIVATE ../../include)

if(MSVC)
  target_compile_options(firmware_host_tests PRIVATE /W4 /WX)
else()
  target_compile_options(
    firmware_host_tests PRIVATE -Wall -Wextra -Wpedantic -Werror
  )
endif()

enable_testing()
add_test(NAME firmware_host_tests COMMAND firmware_host_tests)
