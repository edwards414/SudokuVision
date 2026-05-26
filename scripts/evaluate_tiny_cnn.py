#!/usr/bin/env python3
"""Evaluate TinyCNN accuracy, model size, and single-cell inference latency."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import platform
import statistics
import sys
import time
from typing import Any

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from train_mnist import load_mnist_dataset


def file_metrics(path: Path) -> dict[str, float | int | str]:
    size = path.stat().st_size
    return {
        "path": str(path),
        "model_size_bytes": size,
        "model_size_mib": round(size / (1024 * 1024), 4),
    }


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, round((pct / 100.0) * (len(ordered) - 1))))
    return ordered[index]


def latency_summary_ms(samples: list[float]) -> dict[str, float]:
    return {
        "latency_mean_ms": round(statistics.fmean(samples), 4),
        "latency_p50_ms": round(percentile(samples, 50), 4),
        "latency_p95_ms": round(percentile(samples, 95), 4),
        "latency_min_ms": round(min(samples), 4),
        "latency_max_ms": round(max(samples), 4),
        "latency_samples": len(samples),
    }


def evaluate_keras(
    model_path: Path,
    *,
    empty_ratio: float,
    max_eval_samples: int | None,
    warmup: int,
    runs: int,
) -> dict[str, Any]:
    import tensorflow as tf  # type: ignore

    model = tf.keras.models.load_model(model_path)
    _, (x_test, y_test) = load_mnist_dataset(empty_ratio=empty_ratio)
    if max_eval_samples is not None:
        x_test = x_test[:max_eval_samples]
        y_test = y_test[:max_eval_samples]

    loss, accuracy = model.evaluate(x_test, y_test, verbose=0)

    sample = x_test[:1].astype(np.float32)
    for _ in range(warmup):
        model(sample, training=False)

    samples_ms: list[float] = []
    for _ in range(runs):
        start = time.perf_counter()
        model(sample, training=False)
        samples_ms.append((time.perf_counter() - start) * 1000.0)

    return {
        **file_metrics(model_path),
        "accuracy": round(float(accuracy), 6),
        "loss": round(float(loss), 6),
        **latency_summary_ms(samples_ms),
    }


def _load_tflite_interpreter(model_path: Path):
    try:
        from tflite_runtime.interpreter import Interpreter  # type: ignore
    except ModuleNotFoundError:
        try:
            import tensorflow as tf  # type: ignore
        except ModuleNotFoundError as exc:
            raise RuntimeError("TFLite evaluation requires tensorflow or tflite-runtime") from exc
        return tf.lite.Interpreter(model_path=str(model_path))
    return Interpreter(model_path=str(model_path))


def _quantize_input(input_tensor: np.ndarray, input_details: dict[str, Any]) -> np.ndarray:
    input_dtype = input_details["dtype"]
    if not np.issubdtype(input_dtype, np.integer):
        return input_tensor.astype(input_dtype)

    scale, zero_point = input_details["quantization"]
    if scale == 0:
        raise ValueError("Quantized TFLite input has zero scale")
    quantized = np.round(input_tensor / scale + zero_point)
    return np.clip(quantized, np.iinfo(input_dtype).min, np.iinfo(input_dtype).max).astype(input_dtype)


def _dequantize_output(output: np.ndarray, output_details: dict[str, Any]) -> np.ndarray:
    output_dtype = output_details["dtype"]
    if not np.issubdtype(output_dtype, np.integer):
        return output.astype(np.float32)

    scale, zero_point = output_details["quantization"]
    return (output.astype(np.float32) - zero_point) * scale


def evaluate_tflite(
    model_path: Path,
    *,
    empty_ratio: float,
    max_eval_samples: int | None,
    warmup: int,
    runs: int,
) -> dict[str, Any]:
    interpreter = _load_tflite_interpreter(model_path)
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()[0]
    output_details = interpreter.get_output_details()[0]

    _, (x_test, y_test) = load_mnist_dataset(empty_ratio=empty_ratio)
    if max_eval_samples is not None:
        x_test = x_test[:max_eval_samples]
        y_test = y_test[:max_eval_samples]

    correct = 0
    for sample, label in zip(x_test, y_test, strict=False):
        interpreter.set_tensor(input_details["index"], _quantize_input(sample[np.newaxis, ...], input_details))
        interpreter.invoke()
        probabilities = _dequantize_output(interpreter.get_tensor(output_details["index"])[0], output_details)
        if int(np.argmax(probabilities)) == int(label):
            correct += 1

    sample = x_test[:1].astype(np.float32)
    quantized_sample = _quantize_input(sample, input_details)
    for _ in range(warmup):
        interpreter.set_tensor(input_details["index"], quantized_sample)
        interpreter.invoke()

    samples_ms: list[float] = []
    for _ in range(runs):
        start = time.perf_counter()
        interpreter.set_tensor(input_details["index"], quantized_sample)
        interpreter.invoke()
        samples_ms.append((time.perf_counter() - start) * 1000.0)

    accuracy = correct / max(1, len(y_test))
    return {
        **file_metrics(model_path),
        "accuracy": round(float(accuracy), 6),
        "evaluated_samples": int(len(y_test)),
        **latency_summary_ms(samples_ms),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--keras-model", type=Path, help="Path to trained Keras .keras model")
    parser.add_argument("--tflite-model", type=Path, help="Path to exported .tflite model")
    parser.add_argument("--output", type=Path, default=Path("artifacts/mnist/tiny_cnn_metrics.json"))
    parser.add_argument("--empty-ratio", type=float, default=1.0)
    parser.add_argument("--max-eval-samples", type=int, default=None)
    parser.add_argument("--warmup", type=int, default=20)
    parser.add_argument("--runs", type=int, default=200)
    args = parser.parse_args()

    if args.keras_model is None and args.tflite_model is None:
        raise SystemExit("Provide --keras-model, --tflite-model, or both")

    payload: dict[str, Any] = {
        "model": "TinyCNN",
        "dataset": "MNIST digits 1-9 + synthetic empty class",
        "input_shape": [32, 32, 1],
        "classes": ["empty", "1", "2", "3", "4", "5", "6", "7", "8", "9"],
        "environment": {
            "python": sys.version.split()[0],
            "platform": platform.platform(),
            "processor": platform.processor(),
        },
        "metrics": {},
    }

    if args.keras_model is not None:
        payload["metrics"]["keras"] = evaluate_keras(
            args.keras_model,
            empty_ratio=args.empty_ratio,
            max_eval_samples=args.max_eval_samples,
            warmup=args.warmup,
            runs=args.runs,
        )

    if args.tflite_model is not None:
        payload["metrics"]["tflite"] = evaluate_tflite(
            args.tflite_model,
            empty_ratio=args.empty_ratio,
            max_eval_samples=args.max_eval_samples,
            warmup=args.warmup,
            runs=args.runs,
        )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(payload, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
