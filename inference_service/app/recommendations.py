"""Fixed, backend-contract-compatible safety recommendation allowlist."""

RECOMMENDATION_TEXT = {
    "CHECK_WORKER_IMMEDIATELY": "Contact the worker and send the site's trained responder.",
    "FOLLOW_SITE_EMERGENCY_PROTOCOL": "Follow the approved site emergency procedure.",
    "MOVE_TO_FRESH_AIR": "Leave the affected area using the approved route.",
    "INVESTIGATE_GAS_SOURCE": "Have trained personnel check the area with calibrated equipment.",
    "VENTILATE_AREA_IF_SAFE": "Ventilate only when the approved site procedure says it is safe.",
    "MONITOR_ENVIRONMENT": "Continue monitoring and follow the site's environmental controls.",
    "VERIFY_SENSORS": "Check sensor status and use approved calibrated instruments.",
    "ALLOW_GAS_SENSOR_WARMUP": "Wait for both gas sensors to complete their approved warm-up.",
    "HYDRATE_AND_COOL_DOWN": "Use the approved work-rest and hydration procedure.",
    "MOVE_TO_SAFE_TEMPERATURE": "Move to a cooler safe area and notify the supervisor.",
    "NO_IMMEDIATE_ACTION": "Continue normal controls and monitoring; this is not a safety guarantee.",
}


def validate_recommendation_codes(codes: list[str]) -> list[str]:
    if any(code not in RECOMMENDATION_TEXT for code in codes):
        raise ValueError("Unknown recommendation code")
    return sorted(set(codes))
