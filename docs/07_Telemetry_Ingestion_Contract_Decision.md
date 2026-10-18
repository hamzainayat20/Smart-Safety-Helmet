# Telemetry ingestion contract decision

## Batch 1 scope

This document describes the pure validation and canonicalization contract only.
It does not authorize a device, expose an HTTPS endpoint, write Firebase data,
generate alerts, or change firmware.

## Schema-version decision and Phase A extension

The ingestion contract continues to accept `schemaVersion: "1.0"` without
changing its meaning. Phase A adds a separately validated
`schemaVersion: "2.0"`; it does not reinterpret old records.

The additional DHT22, MPU and MQ-7 diagnostic fields were already introduced as
optional, backward-compatible schema-1.0 fields in the Flutter `SensorReading`
model. Existing schema-1.0 RTDB records and deterministic mock fixtures therefore
remain readable without migration. The strict ingestion validator narrows what
the current hardware may submit; it does not change the stored record shape.

Version 2.0 is the model-input contract. It requires independent `mq7Raw` and
`mq135Raw` ADC readings, independent `mq7WarmUp` and `mq135WarmUp` flags, and an
exact fall feature window. The fall feature names and order are:

```text
acc_mean, acc_std, acc_min, acc_max,
gyro_mean, gyro_std, gyro_max, jerk_mean, jerk_max
```

The approved window metadata is `samplingRateHz: 50`, `windowSamples: 100`, and
`windowEndTimestamp` at or before `deviceTimestamp`. Version-1-only gas fields
are rejected on version 2.0, and version-2-only fields are rejected on version
1.0. This prevents an ambiguous payload from being interpreted two ways.

## Canonical client payload

Required fields are `schemaVersion`, `eventId`, `helmetId`, `deviceTimestamp`,
`firmwareVersion`, `gasWarmUp`, `fallStatus`, and `sensorFaults`. Only canonical
production names are accepted. The manual-sketch aliases remain confined to the
existing controlled Dart adapter and its tests.

For the current hardware contract:

- `gasPpm`, GPS/location, and battery are absent or null.
- `gasWarmUp` is true and MQ-7 data is diagnostic-only.
- `fallStatus` is `notEvaluated`.
- Severity, connectivity, and `serverReceivedAt` are backend-owned and rejected
  when supplied by a client.
- Missing DHT22, MPU, or MQ-7 measurement groups require an explicit typed fault.
- MQ-7 uncalibrated/heater-unknown and GPS/battery-unavailable faults are always
  required.

For schema 2.0, a missing MQ-7 or MQ-135 raw reading requires its own
`mq7ReadFailed` or `mq135ReadFailed` fault. Neither raw ADC reading is ppm and
neither may be presented as a calibrated concentration. Missing GPS and battery
remain explicit unavailable faults in this pre-hardware phase.
- Unknown fields are rejected. Numeric values must be finite and within the
  contract ranges.

The 3.6 V ADC and 5.5 V reconstructed-sensor ceilings are transport abuse bounds,
not calibration claims. They must be revisited after the analog divider, module
output, ADC reference, attenuation behavior, and comparator voltage are measured
on the physical hardware.

## Semantic identity

Validation normalizes unavailable nulls to absence, sorts fault values, and
normalizes negative zero. Canonical JSON recursively sorts object keys while
preserving array order after normalization. The semantic identifier is the
lowercase hexadecimal SHA-256 hash of that canonical UTF-8 JSON.

Every accepted client field participates in the hash. The only excluded values
are backend-owned `serverReceivedAt`, `severity`, and `connectivity`, which are not
part of the validated client payload. A different sensor value with the same
`eventId` therefore produces a different semantic hash.

The trusted-record hash helper removes exactly those three backend-owned fields,
then revalidates every remaining field through the strict client contract. It is
not a substitute for validating an incoming client payload.

## Safety state

The pure backend projection always sets severity to `unassessed`. This contract
contains no alert-generation operation. Existing hazard-resolution logic requires
a fresh trusted `safe` state, so an unassessed projection cannot become safe or
resolve a warning or critical incident.
