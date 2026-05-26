#!/usr/bin/env python3
"""Export a trained Keras Tiny CNN to an int8 TFLite model."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from train_mnist import load_mnist_dataset


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("artifacts/mnist/digit_classifier_int8.tflite"))
    parser.add_argument("--representative-samples", type=int, default=256)
    args = parser.parse_args()

    import tensorflow as tf  # type: ignore

    model = tf.keras.models.load_model(args.model)
    (x_train, _), _ = load_mnist_dataset()

    def representative_dataset():
        for sample in x_train[: args.representative_samples]:
            yield [sample[np.newaxis, ...].astype(np.float32)]

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.representative_dataset = representative_dataset
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    converter.inference_input_type = tf.int8
    converter.inference_output_type = tf.int8
    tflite_model = converter.convert()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(tflite_model)
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
