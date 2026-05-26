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


_PRINTED_FONT_PATHS = (
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Times.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Supplemental/Courier New.ttf",
    "/System/Library/Fonts/Supplemental/Tahoma.ttf",
    "/Library/Fonts/Arial Unicode.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
)


def _available_printed_fonts() -> list[str]:
    from pathlib import Path as _Path

    return [path for path in _PRINTED_FONT_PATHS if _Path(path).exists()]


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


def make_printed_samples(
    count_per_digit: int,
    size: int = 32,
    seed: int = 7,
) -> tuple[np.ndarray, np.ndarray]:
    """Render printed digits 1-9 in multiple fonts with jitter + rotation.

    Returns ``(images, labels)`` shaped like the MNIST processed tensors. The
    images are foreground tensors (dark digit on light background) already
    normalised to ``[0, 1]``. This mirrors the runtime preprocessing in
    ``sudoku_vision.preprocessing.normalize_cell_for_model`` but kept inline so
    training is a single dependency-light pass.
    """

    try:
        from PIL import Image, ImageDraw, ImageFilter, ImageFont
    except ModuleNotFoundError as exc:  # pragma: no cover - import-time guard
        raise RuntimeError(
            "Pillow is required for synthetic printed-font augmentation"
        ) from exc

    fonts = _available_printed_fonts()
    if not fonts:
        raise RuntimeError(
            "No printed fonts available; install at least one of the candidates "
            "or pass --printed-ratio 0 to skip synthetic printed augmentation."
        )

    rng = np.random.default_rng(seed)
    images: list[np.ndarray] = []
    labels: list[int] = []
    for digit in range(1, 10):
        for _ in range(count_per_digit):
            font_path = fonts[int(rng.integers(0, len(fonts)))]
            point_size = int(rng.integers(18, 28))
            try:
                font = ImageFont.truetype(font_path, point_size)
            except OSError:
                continue

            canvas = Image.new("L", (size * 2, size * 2), color=255)
            draw = ImageDraw.Draw(canvas)
            text = str(digit)
            bbox = draw.textbbox((0, 0), text, font=font)
            text_w = bbox[2] - bbox[0]
            text_h = bbox[3] - bbox[1]
            cx = canvas.size[0] // 2 + int(rng.integers(-2, 3))
            cy = canvas.size[1] // 2 + int(rng.integers(-2, 3))
            draw.text(
                (cx - text_w // 2 - bbox[0], cy - text_h // 2 - bbox[1]),
                text,
                fill=int(rng.integers(0, 70)),
                font=font,
            )

            angle = float(rng.uniform(-8.0, 8.0))
            canvas = canvas.rotate(angle, fillcolor=255, resample=Image.BILINEAR)

            if rng.random() < 0.4:
                canvas = canvas.filter(ImageFilter.GaussianBlur(radius=0.6))

            # Crop centered to the target size.
            left = (canvas.size[0] - size) // 2
            top = (canvas.size[1] - size) // 2
            cropped = canvas.crop((left, top, left + size, top + size))

            arr = np.asarray(cropped, dtype=np.float32) / 255.0
            foreground = 1.0 - arr
            foreground += rng.normal(0.0, 0.02, foreground.shape).astype(np.float32)
            foreground = np.clip(foreground, 0.0, 1.0)
            images.append(foreground[..., np.newaxis])
            labels.append(digit)

    arr_images = np.asarray(images, dtype=np.float32)
    arr_labels = np.asarray(labels, dtype=np.int64)
    return arr_images, arr_labels


def load_mnist_dataset(empty_ratio: float = 1.0, printed_per_digit: int = 0):
    """Load MNIST 1-9, synthesise empties, and optionally add printed digits.

    ``printed_per_digit`` controls how many synthetic printed-font samples are
    appended per class. Setting it to 0 reproduces the MNIST-only baseline.
    """

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

    if printed_per_digit > 0:
        x_print_train, y_print_train = make_printed_samples(printed_per_digit)
        x_print_test, y_print_test = make_printed_samples(
            max(1, printed_per_digit // 4), seed=131
        )
        x_train = np.concatenate([x_train, x_print_train], axis=0)
        y_train = np.concatenate([y_train, y_print_train], axis=0)
        x_test = np.concatenate([x_test, x_print_test], axis=0)
        y_test = np.concatenate([y_test, y_print_test], axis=0)

    return (x_train, y_train), (x_test, y_test)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=int, default=5)
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--output-dir", type=Path, default=Path("artifacts/mnist"))
    parser.add_argument("--empty-ratio", type=float, default=1.0)
    parser.add_argument(
        "--printed-per-digit",
        type=int,
        default=0,
        help="Synthetic printed-font samples per digit (1-9). 0 disables.",
    )
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    import tensorflow as tf  # type: ignore

    (x_train, y_train), (x_test, y_test) = load_mnist_dataset(
        empty_ratio=args.empty_ratio,
        printed_per_digit=args.printed_per_digit,
    )

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
