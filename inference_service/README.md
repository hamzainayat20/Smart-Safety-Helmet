# Smart Safety private inference service (Phase B)

This FastAPI service loads the verified fall and gas-condition XGBoost models once per process and converts canonical telemetry schema `2.0` into canonical assessment schema `1.0`. In staging it is deployed privately and invoked only by the `assessTelemetry` Firebase database trigger. Local simulation does not validate physical hardware.

## Safety and interpretation limits

- `mq7Raw` and `mq135Raw` are raw, ADC-like dataset readings, **not calibrated ppm**. The API deliberately rejects invented fields such as `mq7Ppm`.
- The gas model classifies `Mixture`, `NoGas`, `Perfume`, and `Smoke`. Perfume alone is not considered hazardous.
- Warm-up, faults, missing data, low confidence, or readings outside the training ranges can never produce an overall `safe` result.
- The fall model requires the exact nine feature fields derived from 100 samples at 50 Hz. Helmet placement still requires physical validation.
- Recommendation codes come from a fixed allowlist in `app/recommendations.py`; no model generates free-form safety instructions.
- Temperature, humidity, and heat-index rules are isolated in `config/environment_thresholds.json`. They are explicitly marked as prototype defaults and are **not approved for production**; replace them with supervisor-approved site values before physical deployment.
- This prototype is not a certified safety system and does not replace site procedures, trained responders, or calibrated instruments.

## Install, run, and test

From `inference_service`:

```powershell
python -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements.txt
.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8080
.venv\Scripts\python.exe -m pytest -q
```

Endpoints:

- `GET /health` verifies checksums and loads both XGBoost JSON models.
- `POST /v1/assess` validates one stored telemetry-v2 reading and returns the exact assessment object accepted by `functions/src/assessment_contract.js`.

Example simulated input:

```json
{
  "schemaVersion": "2.0",
  "eventId": "event_simulated_0001",
  "helmetId": "helmet001",
  "deviceTimestamp": 1800000000000,
  "serverReceivedAt": 1800000000100,
  "firmwareVersion": "phase-a-simulator.1",
  "sensorFaults": ["gpsUnavailable", "batteryUnavailable"],
  "mq7Raw": 575,
  "mq135Raw": 443,
  "mq7WarmUp": false,
  "mq135WarmUp": false,
  "temperatureC": 27,
  "humidityPct": 55,
  "heatIndexC": 28,
  "fallFeatures": {
    "acc_mean": 1.0,
    "acc_std": 0.05,
    "acc_min": 0.9,
    "acc_max": 1.1,
    "gyro_mean": 1.0,
    "gyro_std": 0.2,
    "gyro_max": 2.0,
    "jerk_mean": 0.1,
    "jerk_max": 0.3
  },
  "samplingRateHz": 50,
  "windowSamples": 100,
  "windowEndTimestamp": 1800000000000
}
```

The returned object uses epoch-millisecond timestamps, `assessmentId == eventId`, the backend reason/recommendation code allowlists, and exact evaluated/unavailable component shapes. The private Phase B backend validates it and stores it under `/assessments/{helmetId}/{eventId}` plus `/helmets/{helmetId}/currentAssessment` without permitting client writes. Identical immutable events produce byte-identical assessments, including a deterministic `assessedAt`, so retries remain idempotent.

## Container boundary

`Dockerfile` packages the service for a private Cloud Run deployment. Do not enable unauthenticated access. Grant Cloud Run Invoker only to the service account used by the `assessTelemetry` function. Cloud Run performs Google identity-token verification before requests reach FastAPI; the application endpoint must not be exposed directly.

## Artifact provenance

`models/checksums.json` records SHA-256 checksums for both source archives and every included artifact. Only XGBoost JSON, JSON config/evaluation, and CSV evaluation files were copied. The provided `joblib` file was deliberately excluded because pickle-compatible artifacts must not be loaded from untrusted sources.
