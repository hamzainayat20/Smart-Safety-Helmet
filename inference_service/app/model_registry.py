from __future__ import annotations

import hashlib
import json
import threading
from functools import lru_cache
from pathlib import Path

import numpy as np
import xgboost as xgb

from .schemas import FallFeatures


ROOT = Path(__file__).resolve().parents[1]
MODELS_DIR = ROOT / "models"
MANIFEST_PATH = MODELS_DIR / "checksums.json"


class ModelIntegrityError(RuntimeError):
    pass


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


class ModelRegistry:
    """Verified, process-wide model bundle loaded once and used read-only."""

    bundle_version = "phase-a.1"

    def __init__(self) -> None:
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        for relative_path, expected in manifest["files"].items():
            path = MODELS_DIR / relative_path
            if not path.is_file():
                raise ModelIntegrityError(f"Required model artifact is missing: {relative_path}")
            actual = _sha256(path)
            if actual.lower() != expected.lower():
                raise ModelIntegrityError(f"Checksum mismatch for model artifact: {relative_path}")

        self.gas_config = json.loads(
            (MODELS_DIR / "gas" / "mq7_mq135_model_config.json").read_text(encoding="utf-8")
        )
        self.fall_config = json.loads(
            (MODELS_DIR / "fall" / "fall_model_config.json").read_text(encoding="utf-8")
        )
        self.gas_features = tuple(self.gas_config["featureOrder"])
        self.fall_features = tuple(self.fall_config["featureOrder"])
        if self.gas_features != ("MQ7", "MQ135"):
            raise ModelIntegrityError("Unexpected gas model feature order")
        expected_fall = tuple(FallFeatures.model_fields)
        if self.fall_features != expected_fall:
            raise ModelIntegrityError("Fall schema and model feature order do not match")

        self.gas_model = xgb.Booster()
        self.gas_model.load_model(MODELS_DIR / "gas" / "mq7_mq135_grouped_model.json")
        self.fall_model = xgb.Booster()
        self.fall_model.load_model(MODELS_DIR / "fall" / "fall_xgboost_50hz.json")
        self._gas_lock = threading.Lock()
        self._fall_lock = threading.Lock()

    @property
    def gas_model_version(self) -> str:
        return str(self.gas_config["modelVersion"])

    @property
    def fall_model_version(self) -> str:
        return str(self.fall_config["modelVersion"])

    @property
    def fall_threshold(self) -> float:
        return float(self.fall_config["decisionThreshold"])

    def predict_gas(self, mq7_raw: float, mq135_raw: float) -> tuple[str, float, dict[str, float]]:
        matrix = xgb.DMatrix(
            np.asarray([[mq7_raw, mq135_raw]], dtype=np.float32),
            feature_names=list(self.gas_features),
        )
        with self._gas_lock:
            raw = np.asarray(self.gas_model.predict(matrix))[0]
        probabilities = np.asarray(raw, dtype=float).reshape(-1)
        classes = [self.gas_config["classMapping"][str(index)] for index in range(len(probabilities))]
        if len(classes) != 4:
            raise ModelIntegrityError("Gas model returned an unexpected class count")
        by_class = {label: float(probabilities[index]) for index, label in enumerate(classes)}
        winning_index = int(np.argmax(probabilities))
        return classes[winning_index], float(probabilities[winning_index]), by_class

    def predict_fall(self, features: FallFeatures) -> float:
        values = [getattr(features, name) for name in self.fall_features]
        matrix = xgb.DMatrix(
            np.asarray([values], dtype=np.float32),
            feature_names=list(self.fall_features),
        )
        with self._fall_lock:
            raw = np.asarray(self.fall_model.predict(matrix)).reshape(-1)
        if raw.size != 1:
            raise ModelIntegrityError("Fall model returned an unexpected output shape")
        return float(raw[0])

    def gas_is_out_of_distribution(self, mq7_raw: float, mq135_raw: float) -> bool:
        ranges = self.gas_config["sensorRanges"]
        return not (
            float(ranges["MQ7"]["minimum"]) <= mq7_raw <= float(ranges["MQ7"]["maximum"])
            and float(ranges["MQ135"]["minimum"])
            <= mq135_raw
            <= float(ranges["MQ135"]["maximum"])
        )


@lru_cache(maxsize=1)
def get_registry() -> ModelRegistry:
    return ModelRegistry()
