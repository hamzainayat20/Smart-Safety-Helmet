from __future__ import annotations

import json
from pathlib import Path
from typing import Literal

from .model_registry import ModelRegistry
from .recommendations import validate_recommendation_codes
from .schemas import (
    AssessmentRequest, EnvironmentAssessment, FallEvaluated, FallUnavailable,
    GasEvaluated, GasUnavailable, SafetyAssessment,
)


Risk = Literal["unknown", "safe", "warning", "critical"]
ComponentRisk = Literal["normal", "warning", "critical", "unavailable"]


_THRESHOLD_PATH = Path(__file__).resolve().parents[1] / "config" / "environment_thresholds.json"
_ENVIRONMENT_THRESHOLDS = json.loads(_THRESHOLD_PATH.read_text(encoding="utf-8"))


def _thresholds(name: str) -> tuple[float, float]:
    values = _ENVIRONMENT_THRESHOLDS[name]
    warning_at = float(values["warningAt"])
    critical_at = float(values["criticalAt"])
    if warning_at >= critical_at:
        raise RuntimeError(f"Invalid environment thresholds for {name}")
    return warning_at, critical_at


def _fall(request: AssessmentRequest, registry: ModelRegistry):
    if "mpuReadFailed" in request.sensorFaults or "fallWindowUnavailable" in request.sensorFaults:
        return FallUnavailable(), "unknown", ["FALL_MODEL_UNAVAILABLE", "SENSOR_FAULT"]
    if request.fallFeatures is None:
        return FallUnavailable(), "unknown", ["FALL_MODEL_UNAVAILABLE", "SENSOR_FAULT"]
    probability = registry.predict_fall(request.fallFeatures)
    result = FallEvaluated(
        probability=probability,
        threshold=registry.fall_threshold,
        modelVersion=registry.fall_model_version,
    )
    if probability >= registry.fall_threshold:
        return result, "critical", ["FALL_DETECTED"]
    return result, "safe", []


def _gas(request: AssessmentRequest, registry: ModelRegistry):
    gas_faults = {
        "mq7ReadFailed", "mq7Uncalibrated", "mq7HeaterStateUnknown",
        "mq135ReadFailed", "mq135Uncalibrated", "mq135HeaterStateUnknown",
    }
    gas_fault = any(fault in gas_faults for fault in request.sensorFaults)
    if gas_fault or request.mq7WarmUp or request.mq135WarmUp:
        reasons = ["GAS_MODEL_UNAVAILABLE"]
        if gas_fault:
            reasons.append("SENSOR_FAULT")
        if request.mq7WarmUp or request.mq135WarmUp:
            reasons.append("GAS_SENSOR_WARMING")
        return GasUnavailable(), "unknown", reasons
    if request.mq7Raw is None or request.mq135Raw is None:
        return GasUnavailable(), "unknown", ["GAS_MODEL_UNAVAILABLE"]

    classification, confidence, probabilities = registry.predict_gas(request.mq7Raw, request.mq135Raw)
    out_of_distribution = registry.gas_is_out_of_distribution(request.mq7Raw, request.mq135Raw)
    result = GasEvaluated(
        classification=classification,
        confidence=confidence,
        probabilities=probabilities,
        modelVersion=registry.gas_model_version,
        outOfDistribution=out_of_distribution,
    )
    if out_of_distribution:
        return result, "unknown", ["GAS_INPUT_OUT_OF_DISTRIBUTION"]
    code = {
        "Smoke": "GAS_SMOKE", "Mixture": "GAS_MIXTURE",
        "Perfume": "GAS_PERFUME", "NoGas": "GAS_NO_GAS",
    }[classification]
    if confidence < 0.55:
        return result, "unknown", ["GAS_MODEL_UNAVAILABLE", code]
    if classification == "Smoke":
        return result, "critical" if confidence >= 0.8 else "warning", [code]
    if classification == "Mixture":
        return result, "warning", [code]
    # Perfume is retained for traceability but is not considered dangerous alone.
    return result, "safe", [code]


def _component_risk(value: float | None, *, warning_at: float, critical_at: float) -> ComponentRisk:
    if value is None:
        return "unavailable"
    if value >= critical_at:
        return "critical"
    if value >= warning_at:
        return "warning"
    return "normal"


def _environment(request: AssessmentRequest):
    if "dhtReadFailed" in request.sensorFaults:
        assessment = EnvironmentAssessment(
            status="unavailable", temperatureRisk="unavailable",
            humidityRisk="unavailable", heatIndexRisk="unavailable",
        )
        return assessment, "unknown", ["SENSOR_FAULT"]

    temperature_warning, temperature_critical = _thresholds("temperatureC")
    humidity_warning, humidity_critical = _thresholds("humidityPct")
    heat_index_warning, heat_index_critical = _thresholds("heatIndexC")
    temperature = _component_risk(
        request.temperatureC,
        warning_at=temperature_warning,
        critical_at=temperature_critical,
    )
    humidity = _component_risk(
        request.humidityPct,
        warning_at=humidity_warning,
        critical_at=humidity_critical,
    )
    heat_index = _component_risk(
        request.heatIndexC,
        warning_at=heat_index_warning,
        critical_at=heat_index_critical,
    )
    risks = [temperature, humidity, heat_index]
    status = "unavailable" if "unavailable" in risks else "evaluated"
    reasons: list[str] = []
    if temperature == "critical": reasons.append("TEMPERATURE_CRITICAL")
    elif temperature == "warning": reasons.append("TEMPERATURE_WARNING")
    if humidity == "critical": reasons.append("HUMIDITY_CRITICAL")
    elif humidity == "warning": reasons.append("HUMIDITY_WARNING")
    if heat_index == "critical": reasons.append("HEAT_INDEX_CRITICAL")
    elif heat_index == "warning": reasons.append("HEAT_INDEX_WARNING")
    if status == "unavailable": reasons.append("SENSOR_FAULT")
    overall: Risk = (
        "critical" if "critical" in risks else
        "warning" if "warning" in risks else
        "unknown" if "unavailable" in risks else "safe"
    )
    return EnvironmentAssessment(
        status=status, temperatureRisk=temperature,
        humidityRisk=humidity, heatIndexRisk=heat_index,
    ), overall, reasons


def _combine(risks: list[Risk]) -> Risk:
    if "critical" in risks: return "critical"
    if "warning" in risks: return "warning"
    if "unknown" in risks: return "unknown"
    return "safe"


def _recommendations(overall: Risk, reasons: list[str]) -> list[str]:
    codes: list[str] = []
    if "FALL_DETECTED" in reasons:
        codes += ["CHECK_WORKER_IMMEDIATELY", "FOLLOW_SITE_EMERGENCY_PROTOCOL"]
    if "GAS_SMOKE" in reasons:
        codes += ["MOVE_TO_FRESH_AIR", "FOLLOW_SITE_EMERGENCY_PROTOCOL"]
    elif "GAS_MIXTURE" in reasons:
        codes += ["INVESTIGATE_GAS_SOURCE", "VENTILATE_AREA_IF_SAFE"]
    if "GAS_SENSOR_WARMING" in reasons:
        codes.append("ALLOW_GAS_SENSOR_WARMUP")
    if any(code.endswith("_CRITICAL") for code in reasons):
        codes += ["MOVE_TO_SAFE_TEMPERATURE", "HYDRATE_AND_COOL_DOWN"]
    elif any(code.endswith("_WARNING") for code in reasons):
        codes += ["HYDRATE_AND_COOL_DOWN", "MONITOR_ENVIRONMENT"]
    if overall == "unknown": codes.append("VERIFY_SENSORS")
    elif overall == "safe": codes.append("NO_IMMEDIATE_ACTION")
    return validate_recommendation_codes(codes)


def assess(request: AssessmentRequest, registry: ModelRegistry) -> SafetyAssessment:
    fall, fall_risk, fall_reasons = _fall(request, registry)
    gas, gas_risk, gas_reasons = _gas(request, registry)
    environment, environment_risk, environment_reasons = _environment(request)
    overall = _combine([fall_risk, gas_risk, environment_risk])
    reasons = sorted(set(fall_reasons + gas_reasons + environment_reasons))
    return SafetyAssessment(
        assessmentId=request.eventId, eventId=request.eventId,
        helmetId=request.helmetId, deviceTimestamp=request.deviceTimestamp,
        sourceServerReceivedAt=request.serverReceivedAt,
        # A retry of the same immutable event must produce byte-identical output.
        # The trusted backend receipt timestamp is stable across ingestion repair.
        assessedAt=request.serverReceivedAt,
        modelBundleVersion=registry.bundle_version,
        fall=fall, gas=gas, environment=environment, overallRisk=overall,
        reasonCodes=reasons,
        recommendationCodes=_recommendations(overall, reasons),
    )
