def test_health_loads_verified_models(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {
        "status": "ok", "modelBundleVersion": "phase-a.1",
        "gasModelVersion": "1.0", "fallModelVersion": "2.0",
        "modelsLoaded": True,
    }


def test_assessment_matches_canonical_backend_contract(client, valid_payload):
    response = client.post("/v1/assess", json=valid_payload)
    assert response.status_code == 200, response.text
    body = response.json()
    assert set(body) == {
        "schemaVersion", "assessmentId", "eventId", "helmetId", "sourceSchemaVersion",
        "deviceTimestamp", "sourceServerReceivedAt", "assessedAt", "modelBundleVersion",
        "fall", "gas", "environment", "overallRisk", "reasonCodes", "recommendationCodes",
    }
    assert body["schemaVersion"] == "1.0"
    assert body["assessmentId"] == body["eventId"] == valid_payload["eventId"]
    assert body["fall"]["status"] == "evaluated"
    assert 0 <= body["fall"]["probability"] <= 1
    assert body["gas"]["status"] == "evaluated"
    assert set(body["gas"]["probabilities"]) == {"Mixture", "NoGas", "Perfume", "Smoke"}
    assert abs(sum(body["gas"]["probabilities"].values()) - 1) < 0.001


def test_warming_up_gas_is_unknown_not_safe(client, valid_payload):
    valid_payload["mq7WarmUp"] = True
    response = client.post("/v1/assess", json=valid_payload)
    assert response.status_code == 200
    body = response.json()
    assert body["gas"] == {"status": "unavailable"}
    assert body["overallRisk"] == "unknown"
    assert "GAS_SENSOR_WARMING" in body["reasonCodes"]
    assert "ALLOW_GAS_SENSOR_WARMUP" in body["recommendationCodes"]


def test_out_of_distribution_gas_is_never_safe(client, valid_payload):
    valid_payload["mq7Raw"] = 100
    valid_payload["mq135Raw"] = 100
    response = client.post("/v1/assess", json=valid_payload)
    assert response.status_code == 200
    body = response.json()
    assert body["gas"]["outOfDistribution"] is True
    assert body["overallRisk"] == "unknown"
    assert "GAS_INPUT_OUT_OF_DISTRIBUTION" in body["reasonCodes"]


def test_schema_rejects_ppm_and_wrong_fall_window(client, valid_payload):
    valid_payload["mq7Ppm"] = 35
    valid_payload["samplingRateHz"] = 100
    response = client.post("/v1/assess", json=valid_payload)
    assert response.status_code == 422
    locations = {tuple(error["loc"]) for error in response.json()["detail"]}
    assert ("body", "mq7Ppm") in locations
    assert ("body", "samplingRateHz") in locations


def test_sensor_fault_does_not_claim_safe(client, valid_payload):
    valid_payload["sensorFaults"].append("mpuReadFailed")
    response = client.post("/v1/assess", json=valid_payload)
    assert response.status_code == 200
    body = response.json()
    assert body["fall"] == {"status": "unavailable"}
    assert body["overallRisk"] != "safe"
def test_uncalibrated_gas_sensor_does_not_run_model(client, valid_payload):
    valid_payload["sensorFaults"].append("mq7Uncalibrated")
    response = client.post("/v1/assess", json=valid_payload)
    assert response.status_code == 200
    body = response.json()
    assert body["gas"] == {"status": "unavailable"}
    assert body["overallRisk"] == "unknown"
    assert "SENSOR_FAULT" in body["reasonCodes"]


def test_missing_fall_window_with_explicit_fault_is_assessed_as_unavailable(
    client, valid_payload
):
    for field in (
        "fallFeatures", "samplingRateHz", "windowSamples", "windowEndTimestamp"
    ):
        valid_payload.pop(field)
    valid_payload["sensorFaults"].append("fallWindowUnavailable")
    response = client.post("/v1/assess", json=valid_payload)
    assert response.status_code == 200
    body = response.json()
    assert body["fall"] == {"status": "unavailable"}
    assert body["overallRisk"] != "safe"
