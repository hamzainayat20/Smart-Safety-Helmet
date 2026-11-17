# Smart Safety Helmet firmware

> **Prototype only.** This is a final-year-project prototype, not certified
> PPE and not a medical device. Fall and gas detection are **not guaranteed**.
> Never test with a human fall, a dropped device, or exposure to a dangerous
> gas. Use controlled hand-held motion and the existing Safe/Fall simulators.

The firmware samples an MPU6050 at 50 Hz, computes the fall model's nine
window features on the ESP32, reads the MQ-7 analog output as a raw ADC count,
and uploads honest **telemetry schema 2.0** to the deployed AWS staging
endpoint with an HMAC-signed HTTPS request:

```text
ESP32 (MPU6050 + MQ-7) --HMAC/TLS--> API Gateway /staging/v1/telemetry
  --> ingestion Lambda (validate, store) --> private inference Lambda (XGBoost)
  --> Firebase RTDB /helmets/helmet001/current --> Flutter apps
```

The ESP32 never writes to Firebase directly.

## Targets

| PlatformIO env | Purpose |
|---|---|
| `esp32dev` (default) | Local only. Prints diagnostics to Serial; no network. |
| `esp32dev_staging` | Same sensing, plus HMAC-signed HTTPS upload to AWS. |
| `esp32dev_provisioner` | One-shot tool that stores the helmet credential and network settings in NVS. |

## Hardware and exact wiring

Board: 30-pin ESP32 Dev Module (CP2102 USB-UART), on `COM4`.

| Function | ESP32 pin | Notes |
|---|---|---|
| MPU6050 VCC | 3V3 | The common GY-521 module also accepts 5 V via its regulator; 3V3 is preferred. |
| MPU6050 GND | GND | Common ground with everything else. |
| MPU6050 SDA | GPIO21 | I2C, 100 kHz. |
| MPU6050 SCL | GPIO22 | |
| MPU6050 address | `0x68` | AD0 low. WHO_AM_I must read `0x68` (MPU6050) or `0x70` (MPU6500). |
| MQ-7 AO | GPIO34 via divider | **10 k from AO to GPIO34, 20 k from GPIO34 to GND.** See warning below. |
| MQ-7 DO | **not connected** | Must stay disconnected. GPIO27 is not used. |
| DHT22 data | GPIO4 | Currently **disconnected on purpose**; `kDht22Installed = false`, so it is not polled and is reported as `dhtReadFailed`. |
| MQ-135, GPS, battery monitor | none | Absent; reported as explicit faults. |
| Buzzer, LED | none | No pin is assigned; nothing is driven. |

### MQ-7 voltage-divider warning

GPIO34 must **never exceed 3.3 V**. A MQ-7 module powered from 5 V can drive
AO close to 5 V. With 10 k (top) / 20 k (bottom) the pin sees
`AO × 20/30`, so 5.0 V on AO becomes **3.33 V**: right at the limit, with no
margin for a high supply. Before connecting AO to the ESP32:

1. With the ESP32 **unplugged**, measure both resistors with a multimeter
   (expect about 10 kΩ and 20 kΩ) and confirm which one goes to GND.
2. Power only the MQ-7 module and measure AO to GND. Then measure the divider
   midpoint to GND. The midpoint must read **below 3.3 V** in all conditions
   you will test in (clean air only).
3. If the module's supply can exceed 5.0 V, or the midpoint can reach 3.3 V,
   use a larger ratio (for example 10 k / 15 k gives 3.0 V from 5 V) and
   update `FirmwareConfig.h` comments accordingly. The raw-count semantics do
   not change.
4. Leave MQ-7 DO disconnected.

The firmware reports `mq7Raw` as the **average of 8 raw 12-bit ADC conversions**
(0–4095). It never calculates CO ppm and never classifies gas. A reading at
either rail (`0` or `4095`) is reported as `mq7ReadFailed` and prints a
warning, because it means a disconnected signal or an input at or above the
ADC limit. **If you ever see the 4095 warning, unplug the board and re-check
the divider.** The ESP32 ADC is non-linear; the earlier diagnostic estimate
(raw ≈ 208, ≈ 0.17 V at the pin, ≈ 0.25 V before the divider) is approximate.

## How sensing works

### MPU6050 driver (`MpuSensor`)

- Accepts only WHO_AM_I `0x68` (MPU6050) or `0x70` (MPU6500). Anything else,
  including common clone IDs such as `0x71`, `0x72` or `0x98`, is rejected and
  reported as unavailable instead of being guessed at.
- Configures ±16 g (2048 LSB/g), ±2000 deg/s (16.4 LSB/(deg/s)), DLPF 4
  (about 20 Hz bandwidth) and a 50 Hz output rate, then reads each register
  back to verify the configuration.
  *Why the wide ranges:* the fall model's trained split thresholds go up to
  about 7.3 g and 740 deg/s. The previous ±2 g / ±250 deg/s setting would clip
  exactly the samples that matter in a fall.
- Five consecutive read failures put the driver into back-off. It re-initialises
  at most once per second, forever, so a loose wire recovers without a reset.
- Any axis at the int16 rail is flagged as saturated. A window containing a
  saturated sample is not used (no clipped features are uploaded).

### 50 Hz sampling task

Motion runs in its own FreeRTOS task (core 1, priority 3, `vTaskDelayUntil`
every 20 ms). DHT22 reads, MQ-7 reads, Serial output and telemetry building
happen in `loop()` at lower priority, and the HTTPS upload runs in a separate
task on core 0. A slow or missing DHT22 or MQ-7 therefore cannot delay or stop
motion sampling.

### Why the DHT22 is not polled while disconnected

The Adafruit DHT driver disables interrupts on the calling core while it
waits for the sensor. With no DHT22 attached, the pulled-up line never goes
low and the driver spins until its timeout, which on the ESP32 is far longer
than its nominal 1 ms (240,000 `digitalRead` iterations), with interrupts
off on core 1. That stalled the 50 Hz task every 2 s and restarted the fall
window just before it completed. `kDht22Installed = false` in
`FirmwareConfig.h` stops the polling. When you wire the DHT22 (GPIO4 with
pull-up), set it to `true`. A working DHT22 blocks for only a few
milliseconds, which the 9 ms tolerance absorbs. If it then fails 3 times in a
row, it is retried only once a minute.

### Gyro calibration

For the first 100 samples (2 s) after the IMU is ready, the firmware estimates
gyro zero-rate offsets. The attempt succeeds only if the board is still:
per-axis gyro std ≤ 1 deg/s, |a| between 0.8 and 1.2 g with std ≤ 0.03 g, and
offsets within ±30 deg/s. Up to 10 attempts (about 20 s) are made. If they
all fail, fall windows stay unavailable (`fallWindowUnavailable`) until reset.
The IMU's real readings are still reported (gyro without offset correction),
so a failed calibration is never misreported as `mpuReadFailed`.

Acceleration is **not** offset-corrected and gravity is **not** removed,
because the model was trained on raw acceleration magnitude including gravity.

### Fall feature window

- Exactly 100 contiguous samples at 50 Hz (2 s), judged against one fixed
  20 ms grid. Each sample may be up to **9 ms late** for its own grid slot
  (FreeRTOS wake-up jitter; under half a period, so every sample still belongs
  to exactly one slot). Because the grid is fixed, jitter never accumulates:
  a sample 9 ms late followed by an on-time one (gaps of 29 ms then 11 ms) is
  fine, while a missed slot, a sample 10+ ms late, or a rate that drifts off
  50 Hz (e.g. 19 or 21 ms) restarts the window. Missing samples are never
  bridged, stretched or interpolated.
- Features are evaluated when the window first fills and then every 25 samples
  (0.5 s), the model's training step.
- Between uploads (every 5 s) the firmware keeps the evaluated window with the
  **largest `acc_max`** and uploads that real window with its own
  `windowEndTimestamp`. A short event between uploads is therefore not missed.
- No window is ever invented: until a valid window exists the upload carries
  `fallWindowUnavailable` and no `fallFeatures`.

### Fall feature definitions

The model metadata (`inference_service/models/fall/fall_model_config.json`)
names the features but does not define them, and no training code is in the
repository. The definitions below were derived from the trained model itself:

| Feature | Definition | Evidence |
|---|---|---|
| `acc_mean/std/min/max` | statistics of \|a\| = √(ax²+ay²+az²) in g, gravity kept | `acc_min` splits are all ≥ 0.03 and `acc_mean` splits cluster near 1 g; single axes would go negative |
| `gyro_mean/std/max` | statistics of \|ω\| = √(gx²+gy²+gz²) in deg/s | `gyro_mean` splits are all ≥ 22, impossible for a signed axis mean |
| `jerk_mean/max` | statistics of \|Δ\|a\|\| × 50 Hz over the 99 consecutive pairs, in g/s | `jerk_max` splits reach 260; only g/s (not g/sample) is physically plausible |
| `*_std` | population standard deviation (ddof = 0) | NumPy default |

**Open assumption:** the thresholds cannot distinguish
\|Δ\|a\|\|·fs (used here) from \|Δa⃗\|·fs (vector difference), or ddof 0 from 1.
The jerk formula lives in one function, `jerkGPerSecond()` in
`src/FallFeatures.cpp`. If the training notebook shows otherwise, change it
there and update the fixture in `tests/host/test_firmware.cpp`.
Sanity check against the real model with the firmware's own feature code:
a stationary trace gives P(fall) ≈ 0.0000, a 2 Hz hand-held wobble ≈ 0.0002,
and a synthetic free-fall/impact/still trace ≈ 1.0 (threshold 0.46).

### Instantaneous axes and the deployed contract

The deployed ingestion contract accepts the instantaneous `accelXG..Z` only
within ±2 g and `gyro*DegreesPerSecond` within ±250 deg/s. If the current
sample is outside that range when an upload is due, the firmware waits up to
1 s for an in-range sample. It does not clip values or claim `mpuReadFailed`,
which would disable fall assessment. If no in-range sample arrives, that one
upload is skipped (`UPLOAD skipped ... reason=motionOutsideContractRange`)
and the fall window is kept for the next upload. The fall features themselves
use the full ±16 g / ±2000 deg/s range.

## Schema 2.0 upload body

Example from a stationary board with DHT22 disconnected (field order is fixed
and deterministic; the exact bytes are what gets signed):

```json
{"schemaVersion":"2.0","eventId":"helmet001_1a2b3c4d_7","helmetId":"helmet001","deviceTimestamp":1794927600123,"firmwareVersion":"0.3.0-staging","accelXG":0.04,"accelYG":-0.002,"accelZG":1.094,"gyroXDegreesPerSecond":0.012,"gyroYDegreesPerSecond":-0.02,"gyroZDegreesPerSecond":0.005,"mq7Raw":208,"mq7WarmUp":true,"mq135WarmUp":false,"fallFeatures":{"acc_mean":1.0948,"acc_std":0.0021,"acc_min":1.0901,"acc_max":1.0995,"gyro_mean":0.21,"gyro_std":0.08,"gyro_max":0.45,"jerk_mean":0.11,"jerk_max":0.35},"samplingRateHz":50,"windowSamples":100,"windowEndTimestamp":1794927599923,"sensorFaults":["batteryUnavailable","dhtReadFailed","gpsUnavailable","mq135HeaterStateUnknown","mq135ReadFailed","mq135Uncalibrated","mq7HeaterStateUnknown","mq7Uncalibrated"]}
```

Rules the builder enforces:

- A measurement is either real or omitted. Every omission carries its fault
  (`mpuReadFailed`, `dhtReadFailed`, `mq7ReadFailed`, `fallWindowUnavailable`).
- Always present: `mq7Uncalibrated`, `mq7HeaterStateUnknown`,
  `mq135ReadFailed`, `mq135Uncalibrated`, `mq135HeaterStateUnknown`,
  `gpsUnavailable`, `batteryUnavailable`.
- `mq7WarmUp: true`: the MQ-7 is powered, but its heater cycle is not
  verified, so it is never claimed to be ready. `mq135WarmUp: false`: MQ-135
  is absent (not warming); `mq135ReadFailed` states that. The backend
  therefore reports gas as **unavailable** and still assesses the fall window.
- No schema 1.0 fields (`gasRaw`, `gasWarmUp`, `fallStatus` ...), no
  backend-owned fields (`severity`, `connectivity`, `serverReceivedAt`), no
  `location`, `batteryPct` or `gasPpm`.
- Nothing is uploaded until SNTP time is synchronized.
- Bodies are about 750 bytes; the backend limit is 8 KiB.

Because temperature, humidity and gas are unavailable, the backend's overall
risk will show as **unknown** even when the fall component is evaluated and
non-fall. That is the honest result for this partial hardware.

## Build, upload and monitor (Windows PowerShell)

Install PlatformIO once if `pio --version` fails (one minimal path):

```powershell
py -m pip install --user platformio
py -m platformio --version
```

If `pio` is then not on `PATH`, use `py -m platformio` wherever `pio` appears.
Close any other serial monitor (Arduino IDE, PuTTY) before uploading.

```powershell
cd firmware
pio run -e esp32dev
pio run -e esp32dev_staging
pio run -e esp32dev_provisioner
pio run -e esp32dev --target upload --upload-port COM4
pio device monitor --baud 115200 --port COM4
```

## Host tests

The 28 host tests cover the MPU identity rules (0x68 accepted, 0x70 retained,
others rejected), register readback, read-failure recovery and saturation,
calibration success and bounded failure, exact 50 Hz / 100-sample behaviour,
all nine features against deterministic fixtures, jerk and first-sample
handling, partial and invalid windows, DHT absence not stopping motion, MQ-7
valid and invalid ADC values, the exact schema 2.0 payload, absence of
fabricated or forbidden fields, ingestion blocks, the canonical signing path,
and the bounded offline queue.

With CMake and a C++17 compiler:

```powershell
cmake -S firmware/tests/host -B firmware/build-host
cmake --build firmware/build-host
ctest --test-dir firmware/build-host --output-on-failure
```

Or with g++ alone (from `firmware/`):

```powershell
g++ -std=c++17 -Wall -Wextra -Wpedantic -Werror -Iinclude tests/host/test_firmware.cpp src/DHT22Sensor.cpp src/FallFeatures.cpp src/MotionPipeline.cpp src/MpuSensor.cpp src/MQ7AnalogSensor.cpp src/FallDetectionEngine.cpp src/EventIdGenerator.cpp src/TelemetryBuilder.cpp src/SensorManager.cpp src/SecureIngestionProtocol.cpp -o build-host-tests.exe
./build-host-tests.exe
```

## Secure provisioning (AWS SSM)

The deployed ingestion Lambda verifies HMAC signatures with the credential in
the encrypted SSM parameter `/smart-safety/staging/configuration`
(`helmetDeviceSecrets.helmet001`). The device must hold **the same** secret
and key version. The firmware no longer generates its own secret; the old
instruction to paste a device-generated secret into "Firebase Secret Manager"
was stale and is removed.

**Approach: import the existing SSM credential into the ESP32.** Nothing is
rotated, so the Safe/Fall simulators keep working and the Lambda's
per-execution-environment configuration cache is never out of date. The
helper script reads SSM and streams the secret over USB directly into the
provisioner firmware. It is never printed, logged, written to disk, put on a
command line, or placed in a build flag.

Requirements: the AWS CLI profile `smart-safety` must be able to call
`ssm:GetParameter` with decryption on that parameter. This is the same access
`test-staging-telemetry.ps1` already uses, so no new IAM permission is needed.

```powershell
cd firmware
pio run -e esp32dev_provisioner --target upload --upload-port COM4
cd ..
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\aws\scripts\provision-helmet-device.ps1 -Stage Credential -Port COM4
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\aws\scripts\provision-helmet-device.ps1 -Stage Network -Port COM4
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\aws\scripts\provision-helmet-device.ps1 -Stage Status -Port COM4
```

Each stage asks you to press **EN/RESET** on the ESP32 once the port is open.
`-Stage Network` asks for the Wi-Fi SSID and a hidden password (the ESP32
needs a **2.4 GHz** network), downloads Amazon Root CA 1 and Starfield
Services Root CA G2, checks that the live endpoint chain anchors to them, and
stores the bundle. TLS verification stays on in the firmware.

If `-Stage Credential` reports that a credential already exists (for example
one generated by the old provisioner), it does not match AWS. Erase it and
import again:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\aws\scripts\provision-helmet-device.ps1 -Stage Erase -ConfirmErase -Port COM4
```

**If you ever need to rotate the secret** (not needed now): generate a new
32-byte secret, write it to SSM under a **new** `keyVersion`, then re-import it
into the device. Until every warm ingestion Lambda environment has reloaded
SSM (a cold start, or a configuration update that forces new environments),
requests signed with the new key can be rejected with 401. Plan a short
overlap or force the reload, and re-run the simulator tests afterwards.

The credential is stored as plaintext in NVS. A production device would need
flash encryption and secure boot; this prototype does not enable them.

## Expected Serial output

Local build (`esp32dev`), stationary on a table, DHT22 disconnected:

```text
Smart Safety Helmet firmware 0.3.0-staging (telemetry schema 2.0).
Prototype only: not certified PPE. Fall/gas detection is not guaranteed.
Keep the board completely still for gyro calibration (about 2 s after the IMU is ready).
DHT22 marked not installed (kDht22Installed=false): not polled, reported as dhtReadFailed.
Telemetry transport disabled; local diagnostics only.
IMU ready: MPU6050 (WHO_AM_I 0x68) at I2C 0x68, +/-16 g, +/-2000 deg/s, 50 Hz.
Gyro calibration complete after 1 attempt(s): offsets x=-3.190 y=2.020 z=-0.790 deg/s. Fall windows start now.
LOCAL {"record":"local-diagnostic","schemaVersion":"2.0",...,"accelZG":1.094,...,"mq7Raw":208,"mq7Units":"raw ADC count, not ppm","fallFeatures":{"acc_mean":1.09,...},"windowEndTimestamp":null,"localFallStatus":"normal","sensorFaults":[...,"dhtReadFailed",...]}
STATUS imu=MPU6050 whoami=0x68 calibration=complete window=100/100 windowRestarts=0 saturatedWindows=0 imuReadFailures=0 imuReinit=0 maxLateMs=2 lastRestartDevMs=0 droppedSlots=0
```

`maxLateMs` is the largest wake-up lateness accepted so far (≤ 9).
`lastRestartDevMs` is what caused the most recent window restart: a large
positive value (e.g. 40–200) means samples were genuinely missed (a stall), a
negative value means samples came too fast. `droppedSlots` counts samples the
motion task could not hand over. A few restarts right after calibration or
while Wi-Fi/TLS starts are acceptable; continuing restarts are not.

On the local build `windowEndTimestamp` is `null` (no network time), so
`fallWindowUnavailable` is listed in the local faults even when features are
shown. The staging build adds:

```text
Staging telemetry transport enabled (HMAC-signed HTTPS to AWS).
UPLOAD skipped event=helmet001_xxxxxxxx_1 reason=timeUnsynchronized   (first seconds only, until SNTP)
UPLOAD queued event=helmet001_xxxxxxxx_3 bytes=749 fallWindow=included
UPLOAD accepted event=helmet001_xxxxxxxx_3 status=202 assessmentStatus=completed
```

`UPLOAD unauthorized ... status=401` means the device credential or key
version does not match SSM: re-run `-Stage Credential` (after `-Stage Erase`).
`UPLOAD rejected ... status=400` means a contract rejection; copy the Serial
output for diagnosis.

## Safe validation procedure

1. Unplug USB. Check wiring against the table above and verify the MQ-7
   divider as described. DHT22 stays disconnected; MQ-7 DO stays disconnected.
2. Plug in USB, upload `esp32dev`, open the monitor. Leave the board flat and
   still for 5 s after reset.
3. Confirm `IMU ready: MPU6050 (WHO_AM_I 0x68)` and `Gyro calibration complete`.
4. Confirm the stationary `LOCAL` line: `accelZG` near 1 g, gyro near 0,
   `acc_mean` near 1, `gyro_mean` small, `mq7Raw` between 1 and 4094 (about
   200 in clean air), `dhtReadFailed` and `mq135ReadFailed` present.
5. Gentle hand-held motion only (tilt and rotate slowly, small shakes). Expect
   `acc_std` and `gyro_mean` to rise and `windowRestarts` to stay at 0. Do not
   drop, throw or strike the board.
6. Provision (above), upload `esp32dev_staging`, keep the board still and wait
   for `UPLOAD accepted ... assessmentStatus=completed`.
7. In Firebase, check `/helmets/helmet001/current` shows the new `eventId`
   and `firmwareVersion` `0.3.0-staging`. In Flutter, check the physical event
   and its fall assessment (expected: evaluated, not a fall; gas unavailable).
8. Re-run the existing simulators to confirm nothing regressed:
   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\aws\scripts\test-staging-telemetry.ps1 -Scenario Safe`
   and `-Scenario Fall`.

**Stop immediately and unplug USB if** the Serial output shows the MQ-7 rail
warning with 4095, the board, MQ-7 module or resistors get hot or smell, any
reading looks like the board is being driven by gas you did not intend
(raw values climbing far above the clean-air baseline), the IMU reports
`unavailable` repeatedly while the wiring looks correct, or the monitor shows
repeated resets/brownouts. Do not deliberately expose the MQ-7 to CO or smoke.

## Rollback

All changes are local and uncommitted. To return the **device** to the
previous behaviour, flash the previous firmware build from version control.
To return the **source** to the last commit for the firmware only (this does
not touch the Flutter/UI work):

```powershell
git diff --stat -- firmware aws/scripts/provision-helmet-device.ps1 docs/08_STAGING_TELEMETRY_INGESTION.md
git restore --source=HEAD -- firmware docs/08_STAGING_TELEMETRY_INGESTION.md
```

Then delete the new files (`git status` lists them as untracked):
`aws/scripts/provision-helmet-device.ps1`, `firmware/include/smart_safety/FallFeatures.h`,
`MotionPipeline.h`, `MpuSensor.h`, `MQ7AnalogSensor.h` and the matching `.cpp`
files in `firmware/src/`. Restoring brings back `MPU6500Sensor.h/.cpp`.

No cloud resources were changed. The device credential in NVS can be erased
with `-Stage Erase -ConfirmErase`; the SSM credential was never modified.

## Remaining limitations

- Physical upload, Firebase update and Flutter display are not yet verified
  on hardware.
- Jerk formula and ddof are inferred, not confirmed from training code (see
  above). Training sensors were not worn on a helmet; helmet placement needs
  separate validation (model metadata limitation).
- The deployed ±2 g / ±250 deg/s instantaneous-axis contract can make an
  upload wait or be skipped during violent motion. Widening it for schema 2.0
  needs a backend change and redeploy, which was deliberately not done.
- MQ-7: no heater cycling, no calibration, no ppm, no gas classification.
- DHT22, MQ-135, GPS, battery, buzzer and LED: absent.
- The offline queue is RAM only (10 events) and is lost on power-off.
- NVS encryption and secure boot are not enabled.
