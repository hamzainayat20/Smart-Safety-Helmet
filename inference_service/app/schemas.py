from __future__ import annotations

from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


EpochMilliseconds = Annotated[int, Field(ge=0)]


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class FallFeatures(StrictModel):
    acc_mean: Annotated[float, Field(ge=0, le=100000, allow_inf_nan=False)]
    acc_std: Annotated[float, Field(ge=0, le=100000, allow_inf_nan=False)]
    acc_min: Annotated[float, Field(ge=0, le=100000, allow_inf_nan=False)]
    acc_max: Annotated[float, Field(ge=0, le=100000, allow_inf_nan=False)]
    gyro_mean: Annotated[float, Field(ge=0, le=100000, allow_inf_nan=False)]
    gyro_std: Annotated[float, Field(ge=0, le=100000, allow_inf_nan=False)]
    gyro_max: Annotated[float, Field(ge=0, le=100000, allow_inf_nan=False)]
    jerk_mean: Annotated[float, Field(ge=0, le=100000, allow_inf_nan=False)]
    jerk_max: Annotated[float, Field(ge=0, le=100000, allow_inf_nan=False)]

    @model_validator(mode="after")
    def validate_extrema(self) -> "FallFeatures":
        if self.acc_min > self.acc_max:
            raise ValueError("acc_min must not exceed acc_max")
        return self


SensorFault = Literal[
    "mpuReadFailed", "dhtReadFailed", "mq7ReadFailed", "mq7Uncalibrated",
    "mq7HeaterStateUnknown", "mq135ReadFailed", "mq135Uncalibrated",
    "mq135HeaterStateUnknown", "fallWindowUnavailable", "gpsUnavailable",
    "batteryUnavailable",
]


class AssessmentRequest(StrictModel):
    """Canonical stored telemetry-v2 fields required for inference."""

    schemaVersion: Literal["2.0"]
    eventId: Annotated[str, Field(pattern=r"^[A-Za-z0-9_-]{1,128}$")]
    helmetId: Annotated[str, Field(pattern=r"^[A-Za-z0-9_-]{1,128}$")]
    deviceTimestamp: EpochMilliseconds
    serverReceivedAt: EpochMilliseconds
    firmwareVersion: Annotated[str, Field(pattern=r"^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$")]
    sensorFaults: list[SensorFault] = Field(max_length=11)
    mq7Raw: Annotated[int | None, Field(default=None, ge=0, le=4095)]
    mq135Raw: Annotated[int | None, Field(default=None, ge=0, le=4095)]
    mq7WarmUp: bool
    mq135WarmUp: bool
    temperatureC: Annotated[float | None, Field(default=None, ge=-40, le=80, allow_inf_nan=False)]
    humidityPct: Annotated[float | None, Field(default=None, ge=0, le=100, allow_inf_nan=False)]
    heatIndexC: Annotated[float | None, Field(default=None, ge=-100, le=250, allow_inf_nan=False)]
    fallFeatures: FallFeatures | None = None
    samplingRateHz: Literal[50] | None = None
    windowSamples: Literal[100] | None = None
    windowEndTimestamp: EpochMilliseconds | None = None

    @field_validator("sensorFaults")
    @classmethod
    def unique_faults(cls, value: list[SensorFault]) -> list[SensorFault]:
        if len(value) != len(set(value)):
            raise ValueError("sensorFaults must not contain duplicates")
        return value

    @model_validator(mode="after")
    def validate_timestamps(self) -> "AssessmentRequest":
        fall_window = (
            self.fallFeatures,
            self.samplingRateHz,
            self.windowSamples,
            self.windowEndTimestamp,
        )
        supplied = sum(value is not None for value in fall_window)
        if supplied not in (0, len(fall_window)):
            raise ValueError("fall window fields must be supplied together")
        if supplied == 0 and not {
            "mpuReadFailed",
            "fallWindowUnavailable",
        }.intersection(self.sensorFaults):
            raise ValueError("a missing fall window requires an explicit fault")
        if (
            self.windowEndTimestamp is not None
            and self.windowEndTimestamp > self.deviceTimestamp
        ):
            raise ValueError("windowEndTimestamp must not exceed deviceTimestamp")
        return self


class FallUnavailable(StrictModel):
    status: Literal["unavailable"] = "unavailable"


class FallEvaluated(StrictModel):
    status: Literal["evaluated"] = "evaluated"
    probability: Annotated[float, Field(ge=0, le=1, allow_inf_nan=False)]
    threshold: Annotated[float, Field(ge=0, le=1, allow_inf_nan=False)]
    modelVersion: Annotated[str, Field(pattern=r"^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$")]


class GasUnavailable(StrictModel):
    status: Literal["unavailable"] = "unavailable"


class GasEvaluated(StrictModel):
    status: Literal["evaluated"] = "evaluated"
    classification: Literal["Mixture", "NoGas", "Perfume", "Smoke"]
    confidence: Annotated[float, Field(ge=0, le=1, allow_inf_nan=False)]
    probabilities: dict[Literal["Mixture", "NoGas", "Perfume", "Smoke"], float]
    modelVersion: Annotated[str, Field(pattern=r"^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$")]
    outOfDistribution: bool

    @model_validator(mode="after")
    def validate_probabilities(self) -> "GasEvaluated":
        expected = {"Mixture", "NoGas", "Perfume", "Smoke"}
        if set(self.probabilities) != expected:
            raise ValueError("gas probabilities must contain all four canonical classes")
        if any(not 0 <= value <= 1 for value in self.probabilities.values()):
            raise ValueError("gas probabilities must be between zero and one")
        if abs(sum(self.probabilities.values()) - 1) > 0.001:
            raise ValueError("gas probabilities must sum to one")
        return self


ComponentRisk = Literal["normal", "warning", "critical", "unavailable"]


class EnvironmentAssessment(StrictModel):
    status: Literal["evaluated", "unavailable"]
    temperatureRisk: ComponentRisk
    humidityRisk: ComponentRisk
    heatIndexRisk: ComponentRisk


class SafetyAssessment(StrictModel):
    schemaVersion: Literal["1.0"] = "1.0"
    assessmentId: str
    eventId: str
    helmetId: str
    sourceSchemaVersion: Literal["2.0"] = "2.0"
    deviceTimestamp: EpochMilliseconds
    sourceServerReceivedAt: EpochMilliseconds
    assessedAt: EpochMilliseconds
    modelBundleVersion: Annotated[str, Field(pattern=r"^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$")]
    fall: FallEvaluated | FallUnavailable
    gas: GasEvaluated | GasUnavailable
    environment: EnvironmentAssessment
    overallRisk: Literal["unknown", "safe", "warning", "critical"]
    reasonCodes: list[str]
    recommendationCodes: list[str]


class HealthResponse(StrictModel):
    status: Literal["ok"]
    modelBundleVersion: str
    gasModelVersion: str
    fallModelVersion: str
    modelsLoaded: bool
