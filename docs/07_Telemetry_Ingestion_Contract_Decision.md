# Telemetry ingestion contract decision

## Batch 1 scope

This document describes the pure validation and canonicalization contract only.
It does not authorize a device, expose an HTTPS endpoint, write Firebase data,
generate alerts, or change firmware.

## Schema-version decision

The ingestion contract retains `schemaVersion: "1.0"`.

The additional DHT22, MPU and MQ-7 diagnostic fields were already introduced as
optional, backward-compatible schema-1.0 fields in the Flutter `SensorReading`
model. Existing schema-1.0 RTDB records and deterministic mock fixtures therefore
remain readable without migration. The strict ingestion validator narrows what
the current hardware may submit; it does not change the stored record shape.

A new schema version would be required if a later phase changes field meaning,
units, required stored fields, enum semantics, or nesting. At that point the
backend must route validation by version, Flutter must test both old and new
records during the compatibility window, and firmware rollout must be staged.

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
