from dataclasses import dataclass

from app.risk_engine import assess
from app.schemas import AssessmentRequest


@dataclass
class StubRegistry:
    gas_class: str = "NoGas"
    gas_confidence: float = 0.95
    fall_probability: float = 0.05
    gas_ood: bool = False
    bundle_version: str = "test.1"
    gas_model_version: str = "1.0"
    fall_model_version: str = "2.0"
    fall_threshold: float = 0.46
    last_gas_input: tuple[int, int] | None = None

    def predict_gas(self, mq7_raw, mq135_raw):
        self.last_gas_input = (mq7_raw, mq135_raw)
        probabilities = {"Mixture": 0.01, "NoGas": 0.01, "Perfume": 0.01, "Smoke": 0.01}
        probabilities[self.gas_class] = self.gas_confidence
        remainder = 1 - self.gas_confidence
        other = remainder / 3
        probabilities = {key: (self.gas_confidence if key == self.gas_class else other) for key in probabilities}
        return self.gas_class, self.gas_confidence, probabilities

    def predict_fall(self, features): return self.fall_probability
    def gas_is_out_of_distribution(self, mq7_raw, mq135_raw): return self.gas_ood


def _request(payload): return AssessmentRequest.model_validate(payload)


def test_confirmed_fall_is_critical(valid_payload):
    result = assess(_request(valid_payload), StubRegistry(fall_probability=0.8))
    assert result.overallRisk == "critical"
    assert "FALL_DETECTED" in result.reasonCodes
    assert "CHECK_WORKER_IMMEDIATELY" in result.recommendationCodes


def test_perfume_alone_is_not_a_hazard(valid_payload):
    result = assess(_request(valid_payload), StubRegistry(gas_class="Perfume", gas_confidence=0.9))
    assert result.gas.classification == "Perfume"
    assert result.overallRisk == "safe"
    assert "GAS_PERFUME" in result.reasonCodes


def test_smoke_pattern_uses_fixed_recommendation(valid_payload):
    result = assess(_request(valid_payload), StubRegistry(gas_class="Smoke", gas_confidence=0.9))
    assert result.overallRisk == "critical"
    assert "MOVE_TO_FRESH_AIR" in result.recommendationCodes


def test_humidity_rule_is_explicit(valid_payload):
    valid_payload["humidityPct"] = 86
    result = assess(_request(valid_payload), StubRegistry())
    assert result.environment.humidityRisk == "warning"
    assert "HUMIDITY_WARNING" in result.reasonCodes


def test_low_confidence_never_becomes_safe(valid_payload):
    result = assess(_request(valid_payload), StubRegistry(gas_class="NoGas", gas_confidence=0.4))
    assert result.overallRisk == "unknown"
    assert "GAS_MODEL_UNAVAILABLE" in result.reasonCodes


def test_baseline_learning_is_unknown_without_calling_gas_model(valid_payload):
    valid_payload.update({
        "gasInputMode": "baselineLearning",
        "mq7Ratio": None,
        "mq135Ratio": None,
        "gasThresholdConsecutive": 0,
    })
    registry = StubRegistry()
    result = assess(_request(valid_payload), registry)
    assert result.overallRisk == "unknown"
    assert result.gasThresholdRisk == "unknown"
    assert "GAS_BASELINE_LEARNING" in result.reasonCodes
    assert registry.last_gas_input is None


def test_smoke_ratios_are_immediately_critical(valid_payload):
    valid_payload.update({"mq7Ratio": 1.22, "mq135Ratio": 1.40, "gasThresholdConsecutive": 1})
    result = assess(_request(valid_payload), StubRegistry())
    assert result.gasThresholdRisk == "critical"
    assert result.overallRisk == "critical"
    assert "GAS_RISE_CRITICAL" in result.reasonCodes


def test_sanitiser_warning_requires_two_consecutive_readings(valid_payload):
    valid_payload.update({"mq7Ratio": 1.17, "mq135Ratio": 1.21, "gasThresholdConsecutive": 1})
    first = assess(_request(valid_payload), StubRegistry())
    assert first.gasThresholdRisk == "safe"
    valid_payload["gasThresholdConsecutive"] = 2
    second = assess(_request(valid_payload), StubRegistry())
    assert second.gasThresholdRisk == "warning"
    assert second.overallRisk == "warning"
    assert "GAS_RISE_WARNING" in second.reasonCodes


def test_measured_sanitiser_ratios_are_critical(valid_payload):
    valid_payload.update({"mq7Ratio": 1.17, "mq135Ratio": 1.42, "gasThresholdConsecutive": 1})
    result = assess(_request(valid_payload), StubRegistry())
    assert result.gasThresholdRisk == "critical"
    assert result.overallRisk == "critical"
    assert "GAS_RISE_CRITICAL" in result.reasonCodes


def test_clean_air_mapping_is_safe_and_reaches_model_as_610_470(valid_payload):
    registry = StubRegistry(gas_class="NoGas", gas_confidence=0.95)
    result = assess(_request(valid_payload), registry)
    assert registry.last_gas_input == (610, 470)
    assert result.gas.classification == "NoGas"
    assert result.gasThresholdRisk == "safe"
    assert result.overallRisk == "safe"
