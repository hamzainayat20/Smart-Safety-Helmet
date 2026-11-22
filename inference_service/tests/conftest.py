from __future__ import annotations

import copy

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture(scope="session")
def client() -> TestClient:
    return TestClient(app)


@pytest.fixture
def valid_payload() -> dict:
    payload = {
        "schemaVersion": "2.0",
        "eventId": "event_simulated_0001",
        "helmetId": "helmet001",
        "deviceTimestamp": 1_800_000_000_000,
        "serverReceivedAt": 1_800_000_000_100,
        "firmwareVersion": "phase-a-simulator.1",
        "sensorFaults": ["gpsUnavailable", "batteryUnavailable"],
        "mq7Raw": 610,
        "mq135Raw": 470,
        "mq7WarmUp": False,
        "mq135WarmUp": False,
        "gasInputMode": "baselineMapped",
        "mq7Ratio": 1.0,
        "mq135Ratio": 1.0,
        "gasThresholdConsecutive": 0,
        "temperatureC": 27.0,
        "humidityPct": 55.0,
        "heatIndexC": 28.0,
        "fallFeatures": {
            "acc_mean": 1.0, "acc_std": 0.05, "acc_min": 0.9, "acc_max": 1.1,
            "gyro_mean": 1.0, "gyro_std": 0.2, "gyro_max": 2.0,
            "jerk_mean": 0.1, "jerk_max": 0.3,
        },
        "samplingRateHz": 50,
        "windowSamples": 100,
        "windowEndTimestamp": 1_800_000_000_000,
    }
    return copy.deepcopy(payload)
