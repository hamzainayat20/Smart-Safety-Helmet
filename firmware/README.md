# Smart Safety firmware foundation

The default `esp32dev` target is deliberately local-only. The opt-in
`esp32dev_staging` target adds helmet-bound, HMAC-signed HTTPS telemetry through
the trusted Cloud Function. It never writes Realtime Database directly. See
`../docs/08_STAGING_TELEMETRY_INGESTION.md` for the deployment and one-time NVS
provisioning boundary.

The original manual sketch remains at
`tests/manual/mq7_multi_sensor_test/mq7_multi_sensor_test.ino` and is not part of
this production-style firmware target.

## Directory structure

```text
firmware/
  platformio.ini
  include/smart_safety/
    ArduinoAdapters.h
    DHT22Sensor.h
    DisabledHardware.h
    EventIdGenerator.h
    FallDetectionEngine.h
    FirmwareConfig.h
    HardwareInterfaces.h
    MPU6500Sensor.h
    NonBlockingScheduler.h
    SensorManager.h
    SensorTypes.h
    SecureIngestionClient.h
    SecureIngestionProtocol.h
    TelemetryBuilder.h
  src/
    DHT22Sensor.cpp
    EventIdGenerator.cpp
    FallDetectionEngine.cpp
    MPU6500Sensor.cpp
    SensorManager.cpp
    SecureIngestionClient.cpp
    SecureIngestionProtocol.cpp
    TelemetryBuilder.cpp
    main.cpp
    provision_device.cpp
  tests/
    host/
      CMakeLists.txt
      test_firmware.cpp
    manual/mq7_multi_sensor_test/  # preserved reference sketch
```

## Verified pin map used by this firmware

| Function | ESP32 pin | State |
|---|---:|---|
| DHT22 data | GPIO 4 | Enabled |
| MPU I2C SDA | GPIO 21 | Enabled |
| MPU I2C SCL | GPIO 22 | Enabled |
| MPU I2C address | `0x68` | Enabled; WHO_AM_I must be `0x70` |
| MQ-7 analog | Not defined | Disabled pending divider verification |
| MQ-7 digital | Not defined | Disabled; GPIO 27 is not used |
| GPS | Not defined | Unavailable stub |
| Battery | Not defined | Unavailable stub |
| Buzzer | Not defined | Unconfigured stub |
| LED | Not defined | Unconfigured stub |

## Scheduling and behavior

- MPU acquisition is scheduled every 20 ms (approximately 50 Hz).
- DHT22 acquisition is scheduled every 2000 ms.
- Serial telemetry summaries are scheduled every 5000 ms.
- The 100 ms MPU wake interval is a nonblocking initialization state; `loop()`
  continues to run while it elapses.
- Sensor failure clears that sensor's last values and adds a typed fault without
  stopping other sensors.
- MPU configuration is fixed at ±2 g and ±250 degrees/second. WHO_AM_I `0x68`
  is rejected because the verified MPU6500 identity is `0x70`.
- Fall detection uses acceleration magnitude, a free-fall candidate below 0.5 g,
  impact at or above 2.0 g, continuous post-impact stillness, and a 30-second
  duplicate cooldown. It is diagnostic, deterministic prototype logic—not
  certified or medical-grade detection—and activates no physical output.

## Dependencies

- PlatformIO Core or PlatformIO IDE extension
- Espressif 32 PlatformIO platform
- Arduino framework for ESP32
- Adafruit DHT Sensor Library 1.4.x
- Adafruit Unified Sensor 1.1.x
- A C++17 compiler and CMake 3.16+ for host tests

Versions for Arduino libraries are constrained in `platformio.ini`. PlatformIO
will download them when the developer explicitly runs a build with network
access.

## ESP32 build and upload

From `firmware/`:

```text
pio run
pio run --target upload --upload-port COMx
pio device monitor --baud 115200 --port COMx
```

Replace `COMx` with the locally observed serial port. Do not upload until DHT22
and MPU wiring and power are checked. MQ-7 DO must remain disconnected from GPIO
27, and its analog output must remain disconnected from GPIO 34 for this build.

No physical ESP32 build or upload is claimed until PlatformIO and hardware are
available and the commands succeed.

## Host tests

With a native C++17 compiler and CMake:

```text
cmake -S firmware/tests/host -B firmware/build-host
cmake --build firmware/build-host
ctest --test-dir firmware/build-host --output-on-failure
```

The suite covers DHT success/failure, strict MPU identity and register writes,
20 ms scheduling, three-phase fall transitions, normal-motion fixtures, stable
event IDs, null serialization, MQ-7/GPS/battery exclusions, and disabled network
and output interfaces.

## Configuration

`FirmwareConfig.h` contains only non-secret compile-time settings. The default
target uses the explicit placeholder `UNPROVISIONED_HELMET`. Staging identity,
Wi-Fi, endpoint, TLS CA, and the unique device secret are read from ESP32 NVS;
none are accepted from committed source or build flags. Provisioner stage 1
creates identity/secret once and refuses overwrite; stage 2 updates only
endpoint/TLS/Wi-Fi configuration.

Changing the placeholder is not provisioning. The HMAC key is plaintext inside
ESP32 storage and Google Secret Manager because both sides must compute HMAC; it
is not a one-way stored hash. It is never committed or logged. Production use
additionally requires verified NVS/flash encryption and secure boot.

## Example Serial JSON

The exact readings vary; unavailable values remain null:

```json
{"schemaVersion":"1.0","eventId":"UNPROVISIONED_HELMET_a1b2c3d4_1","helmetId":"UNPROVISIONED_HELMET","deviceTimestamp":null,"deviceTimeStatus":"unsynchronized","firmwareVersion":"0.1.0-local","temperatureC":26.4,"humidityPct":54.2,"heatIndexC":26.8,"gasPpm":null,"gasWarmUp":true,"gasRaw":null,"gasAdcVoltage":null,"gasSensorVoltage":null,"gasDigitalThreshold":null,"accelXG":0.01,"accelYG":-0.02,"accelZG":0.99,"gyroXDegreesPerSecond":1.1,"gyroYDegreesPerSecond":-0.8,"gyroZDegreesPerSecond":0.2,"fallStatus":"normal","location":null,"gpsStatus":"invalid","batteryPct":null,"severity":"unassessed","sensorFaults":["batteryUnavailable","gpsUnavailable","mq7HeaterStateUnknown","mq7ReadFailed","mq7Uncalibrated"]}
```

This is local diagnostic JSON, not the upload body. The staging transport builds
a separate strict payload only after time synchronization; it removes
`deviceTimeStatus`, GPS status, severity, and connectivity because those are
unavailable or backend-owned. The default transport prevents accidental upload.

## Manual hardware checklist

1. Confirm the ESP32 is unpowered while wiring.
2. Confirm DHT22 data is on GPIO 4 and that the module/bare sensor has the
   required pull-up appropriate to the actual board.
3. Confirm MPU SDA/SCL are GPIO 21/22, address is `0x68`, supply voltage is
   compatible, and grounds are common.
4. Confirm Serial reports WHO_AM_I `0x70` through a controlled diagnostic before
   treating the MPU as valid. This firmware rejects `0x68`.
5. Leave MQ-7 AO and DO disconnected from the ESP32 for this build.
6. Do not attach any buzzer or LED to an assumed pin.
7. Observe at least ten minutes of stationary and normal-motion Serial output;
   record sensor faults and fall-state changes.
8. Exercise only safe hand-held motion fixtures. Do not perform human falls or
   treat the result as safety certification.

## Deliberately disabled functionality

- Network and backend activity in the default target
- Wi-Fi provisioning and device credentials
- MQ-7 analog and digital acquisition
- MQ-7 ppm conversion and gas alerting
- Heater-cycle control
- GPS and location coordinates
- Battery readings
- Buzzer and LED activation
- Physical fall alerts
- Power-persistent offline upload buffering (staging has a ten-record RAM queue)
- Remote configuration

## Remaining prerequisites

- Confirm the MQ-7 module model, supply voltage, AO divider wiring/measurements,
  DO voltage levels, heater circuit, heater timing, and calibration method.
- Confirm GPS, battery, buzzer, and LED parts and wiring before assigning pins.
- Implement and approve synchronized time behavior.
- Complete the separately approved backend authentication, provisioning,
  ingestion, configuration, nonce, rate-limit, and storage batches.
- Calibrate and physically test fall thresholds using a documented fixture set.
- Install PlatformIO, compile the ESP32 target, upload it, and perform hardware
  tests before claiming physical success.
