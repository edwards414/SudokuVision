"""Cell and grid recognition using TFLite or an injected classifier."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Protocol

import numpy as np

from sudoku_vision.errors import OptionalDependencyError
from sudoku_vision.model import CLASS_NAMES
from sudoku_vision.preprocessing import estimate_empty_cell, normalize_cell_for_model

LOW_CONFIDENCE_THRESHOLD = 0.85


class CellClassifier(Protocol):
    """Protocol for model backends used by DigitRecognizer."""

    def predict_proba(self, model_input: np.ndarray) -> np.ndarray:
        """Return class probabilities for one input of shape ``(32, 32, 1)``."""


@dataclass(frozen=True)
class CellPrediction:
    row: int
    col: int
    predicted: int
    confidence: float
    empty_candidate: bool
    black_pixel_ratio: float
    largest_component_ratio: float


@dataclass(frozen=True)
class RecognitionResult:
    grid: list[list[int]]
    confidence: list[list[float]]
    low_confidence_cells: list[dict[str, int | float]]
    cells: list[CellPrediction]

    def to_dict(self) -> dict[str, object]:
        return {
            "grid": self.grid,
            "confidence": self.confidence,
            "low_confidence_cells": self.low_confidence_cells,
            "cells": [asdict(cell) for cell in self.cells],
        }


class TFLiteCellClassifier:
    """TFLite runtime wrapper for the Tiny CNN."""

    def __init__(self, model_path: str | Path) -> None:
        self.model_path = Path(model_path)
        self.interpreter = self._load_interpreter(self.model_path)
        self.interpreter.allocate_tensors()
        self.input_details = self.interpreter.get_input_details()[0]
        self.output_details = self.interpreter.get_output_details()[0]

    @staticmethod
    def _load_interpreter(model_path: Path):
        try:
            from tflite_runtime.interpreter import Interpreter  # type: ignore
        except ModuleNotFoundError:
            try:
                import tensorflow as tf  # type: ignore
            except ModuleNotFoundError as exc:
                raise OptionalDependencyError(
                    "tensorflow or tflite-runtime",
                    "TFLite digit inference",
                ) from exc
            return tf.lite.Interpreter(model_path=str(model_path))
        return Interpreter(model_path=str(model_path))

    def predict_proba(self, model_input: np.ndarray) -> np.ndarray:
        tensor = np.asarray(model_input)
        if tensor.shape != (32, 32, 1):
            raise ValueError(f"Expected model input shape (32, 32, 1), got {tensor.shape}")

        input_tensor = tensor[np.newaxis, ...]
        input_dtype = self.input_details["dtype"]

        if np.issubdtype(input_dtype, np.integer):
            scale, zero_point = self.input_details["quantization"]
            if scale == 0:
                raise ValueError("Quantized TFLite input has zero scale")
            input_tensor = np.round(input_tensor / scale + zero_point)
            input_tensor = np.clip(
                input_tensor,
                np.iinfo(input_dtype).min,
                np.iinfo(input_dtype).max,
            ).astype(input_dtype)
        else:
            input_tensor = input_tensor.astype(input_dtype)

        self.interpreter.set_tensor(self.input_details["index"], input_tensor)
        self.interpreter.invoke()
        output = self.interpreter.get_tensor(self.output_details["index"])[0]

        output_dtype = self.output_details["dtype"]
        if np.issubdtype(output_dtype, np.integer):
            scale, zero_point = self.output_details["quantization"]
            output = (output.astype(np.float32) - zero_point) * scale

        output = np.asarray(output, dtype=np.float32)
        total = float(output.sum())
        if total > 0:
            output = output / total
        return output


class DigitRecognizer:
    """Recognize a 9x9 matrix of Sudoku cells."""

    def __init__(
        self,
        classifier: CellClassifier | None = None,
        model_path: str | Path | None = None,
        low_confidence_threshold: float = LOW_CONFIDENCE_THRESHOLD,
    ) -> None:
        if classifier is None and model_path is None:
            raise ValueError("Provide either classifier or model_path")
        self.classifier = classifier if classifier is not None else TFLiteCellClassifier(model_path)  # type: ignore[arg-type]
        self.low_confidence_threshold = low_confidence_threshold

    def predict_cell(self, cell_image: np.ndarray, row: int = 0, col: int = 0) -> CellPrediction:
        features = estimate_empty_cell(cell_image)
        model_input = normalize_cell_for_model(cell_image)
        probabilities = np.asarray(self.classifier.predict_proba(model_input), dtype=np.float32)
        if probabilities.shape != (len(CLASS_NAMES),):
            raise ValueError(
                f"Classifier must return {len(CLASS_NAMES)} probabilities, got {probabilities.shape}"
            )

        predicted_class = int(np.argmax(probabilities))
        confidence = float(probabilities[predicted_class])

        # CV can confidently identify obvious blank cells. The model still runs so
        # confidence stays tied to the learned classifier when the cell is ambiguous.
        if features.is_empty_candidate and predicted_class != 0:
            empty_confidence = float(probabilities[0])
            if confidence < self.low_confidence_threshold or empty_confidence >= 0.35:
                predicted_class = 0
                confidence = max(empty_confidence, 1.0 - features.black_pixel_ratio)

        return CellPrediction(
            row=row,
            col=col,
            predicted=predicted_class,
            confidence=confidence,
            empty_candidate=features.is_empty_candidate,
            black_pixel_ratio=features.black_pixel_ratio,
            largest_component_ratio=features.largest_component_ratio,
        )

    def recognize(self, cells: list[list[np.ndarray]]) -> RecognitionResult:
        if len(cells) != 9 or any(len(row) != 9 for row in cells):
            raise ValueError("cells must be a 9x9 matrix")

        grid = [[0 for _ in range(9)] for _ in range(9)]
        confidence = [[0.0 for _ in range(9)] for _ in range(9)]
        low_confidence_cells: list[dict[str, int | float]] = []
        predictions: list[CellPrediction] = []

        for row_idx, row in enumerate(cells):
            for col_idx, cell in enumerate(row):
                prediction = self.predict_cell(cell, row=row_idx, col=col_idx)
                predictions.append(prediction)
                grid[row_idx][col_idx] = prediction.predicted
                confidence[row_idx][col_idx] = round(prediction.confidence, 4)
                if prediction.confidence < self.low_confidence_threshold:
                    low_confidence_cells.append(
                        {
                            "row": row_idx,
                            "col": col_idx,
                            "predicted": prediction.predicted,
                            "confidence": round(prediction.confidence, 4),
                        }
                    )

        return RecognitionResult(
            grid=grid,
            confidence=confidence,
            low_confidence_cells=low_confidence_cells,
            cells=predictions,
        )
