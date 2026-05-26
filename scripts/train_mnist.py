#!/usr/bin/env python3
"""Train the Tiny CNN with MNIST digits 1-9 plus synthetic empty cells."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from sudoku_vision.model import build_tiny_cnn


def make_empty_samples(count: int, size: int = 32, seed: int = 42) -> np.ndarray:
    rng = np.random.default_rng(seed)
    samples = np.full((count, size, size, 1), 0.0, dtype=np.float32)
    noise = rng.normal(loc=0.0, scale=0.018, size=samples.shape).astype(np.float32)
    samples = np.clip(samples + noise, 0.0, 1.0)

    # Add occasional faint gridline residue so "empty" learns camera artifacts.
    for idx in range(count):
        if rng.random() < 0.35:
            x = int(rng.integers(0, size))
            samples[idx, :, x : min(size, x + 1), 0] = rng.uniform(0.03, 0.12)
        if rng.random() < 0.35:
            y = int(rng.integers(0, size))
            samples[idx, y : min(size, y + 1), :, 0] = rng.uniform(0.03, 0.12)
    return samples


def load_mnist_dataset(empty_ratio: float = 1.0):
    import tensorflow as tf  # type: ignore

    (x_train, y_train), (x_test, y_test) = tf.keras.datasets.mnist.load_data()

    def convert(images: np.ndarray, labels: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        keep = labels != 0
        images = images[keep]
        labels = labels[keep]
        images = tf.image.resize(images[..., np.newaxis], (32, 32)).numpy()
        images = images.astype(np.float32) / 255.0
        labels = labels.astype(np.int64)
        return images, labels

    x_train, y_train = convert(x_train, y_train)
    x_test, y_test = convert(x_test, y_test)

    empty_train_count = int(len(x_train) / 9 * empty_ratio)
    empty_test_count = int(len(x_test) / 9 * empty_ratio)
    x_empty_train = make_empty_samples(empty_train_count)
    y_empty_train = np.zeros((empty_train_count,), dtype=np.int64)
    x_empty_test = make_empty_samples(empty_test_count, seed=99)
    y_empty_test = np.zeros((empty_test_count,), dtype=np.int64)

    x_train = np.concatenate([x_train, x_empty_train], axis=0)
    y_train = np.concatenate([y_train, y_empty_train], axis=0)
    x_test = np.concatenate([x_test, x_empty_test], axis=0)
    y_test = np.concatenate([y_test, y_empty_test], axis=0)
    return (x_train, y_train), (x_test, y_test)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=int, default=5)
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--output-dir", type=Path, default=Path("artifacts/mnist"))
    parser.add_argument("--empty-ratio", type=float, default=1.0)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    import tensorflow as tf  # type: ignore

    (x_train, y_train), (x_test, y_test) = load_mnist_dataset(empty_ratio=args.empty_ratio)

    model = build_tiny_cnn()
    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_accuracy",
            patience=2,
            restore_best_weights=True,
        )
    ]
    model.fit(
        x_train,
        y_train,
        validation_data=(x_test, y_test),
        epochs=args.epochs,
        batch_size=args.batch_size,
        callbacks=callbacks,
    )
    metrics = model.evaluate(x_test, y_test, verbose=0)
    print({"test_loss": float(metrics[0]), "test_accuracy": float(metrics[1])})
    model.save(args.output_dir / "model.keras")


if __name__ == "__main__":
    main()
