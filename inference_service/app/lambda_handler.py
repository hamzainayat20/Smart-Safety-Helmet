"""AWS Lambda adapter for the existing pure inference service.

The adapter deliberately performs no storage and accepts only the same canonical
assessment request used by the private FastAPI endpoint. API Gateway must never
route directly to this function; only the ingestion Lambda may invoke it.
"""

from __future__ import annotations

from typing import Any

from pydantic import ValidationError

from .model_registry import get_registry
from .risk_engine import assess
from .schemas import AssessmentRequest


def handler(event: dict[str, Any], _context: Any) -> dict[str, Any]:
    """Validate one canonical request and return one canonical assessment."""

    try:
        request = AssessmentRequest.model_validate(event)
    except ValidationError:
        # Lambda's caller treats FunctionError as retryable. A validation error is
        # deterministic, so return a small typed envelope for the caller instead.
        return {
            "error": {
                "code": "INFERENCE_REQUEST_INVALID",
                "message": "The canonical assessment request is invalid.",
            }
        }

    result = assess(request, get_registry())
    return result.model_dump(mode="json")
