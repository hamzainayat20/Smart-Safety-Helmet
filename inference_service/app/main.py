from __future__ import annotations

from fastapi import Depends, FastAPI

from .model_registry import ModelRegistry, get_registry
from .risk_engine import assess
from .schemas import AssessmentRequest, HealthResponse, SafetyAssessment


app = FastAPI(
    title="Smart Safety Inference Service",
    version="0.2.0",
    description=(
        "Private Phase B service for fall and gas-condition model inference. "
        "It is not a certified safety system."
    ),
)


@app.get("/health", response_model=HealthResponse)
def health(registry: ModelRegistry = Depends(get_registry)) -> HealthResponse:
    return HealthResponse(
        status="ok",
        modelBundleVersion=registry.bundle_version,
        gasModelVersion=registry.gas_model_version,
        fallModelVersion=registry.fall_model_version,
        modelsLoaded=True,
    )


@app.post("/v1/assess", response_model=SafetyAssessment)
def create_assessment(
    request: AssessmentRequest,
    registry: ModelRegistry = Depends(get_registry),
) -> SafetyAssessment:
    return assess(request, registry)
