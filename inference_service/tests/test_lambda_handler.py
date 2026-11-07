from inference_service.app.lambda_handler import handler


def test_lambda_handler_matches_http_assessment_contract(valid_payload):
    body = handler(valid_payload, None)
    assert body["schemaVersion"] == "1.0"
    assert body["assessmentId"] == valid_payload["eventId"]
    assert body["helmetId"] == valid_payload["helmetId"]
    assert body["overallRisk"] in {"unknown", "safe", "warning", "critical"}


def test_lambda_handler_returns_safe_validation_envelope(valid_payload):
    valid_payload["schemaVersion"] = "99.0"
    body = handler(valid_payload, None)
    assert body["error"]["code"] == "INFERENCE_REQUEST_INVALID"
    assert "input" not in str(body)
