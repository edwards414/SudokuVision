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
    # Regular-weight macOS fonts (covers thin-stroke screen-printed digits
    # like the ones Sudoku.com / printed-book screenshots use).
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/HelveticaNeue.ttc",
    "/System/Library/Fonts/Times.ttc",
    "/System/Library/Fonts/Courier.ttc",
    "/System/Library/Fonts/Geneva.ttf",
    "/System/Library/Fonts/Avenir.ttc",
    "/System/Library/Fonts/Avenir Next.ttc",
    "/System/Library/Fonts/Avenir Next Condensed.ttc",
    "/System/Library/Fonts/Palatino.ttc",
    "/System/Library/Fonts/Menlo.ttc",
    "/System/Library/Fonts/Futura.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial Narrow.ttf",
    "/System/Library/Fonts/Supplemental/Verdana.ttf",
    "/System/Library/Fonts/Supplemental/Verdana Bold.ttf",
    "/System/Library/Fonts/Supplemental/Georgia.ttf",
    "/System/Library/Fonts/Supplemental/Georgia Bold.ttf",
    "/System/Library/Fonts/Supplemental/Trebuchet MS.ttf",
    "/System/Library/Fonts/Supplemental/Trebuchet MS Bold.ttf",
    "/System/Library/Fonts/Supplemental/Tahoma.ttf",
    "/System/Library/Fonts/Supplemental/Courier New.ttf",
    "/System/Library/Fonts/Supplemental/Courier New Bold.ttf",
    "/Library/Fonts/Arial Unicode.ttf",
    # Common Linux fallbacks so the same pipeline works on the CI/Docker host.
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf",
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
    images are foreground tensors (dark digit on light background) and are
    pushed through the same ``normalize_cell_for_model`` pipeline that the
    runtime cell preprocessor uses, so train and inference distributions line
    up: digit-fills-cell ratio, crop margin and resize all match.
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

    # Use the shared preprocessing path so a sample emitted here matches what
    # DigitRecognizer.predict_cell sees at inference time.
    from sudoku_vision.preprocessing import normalize_cell_for_model

    rng = np.random.default_rng(seed)
    images: list[np.ndarray] = []
    labels: list[int] = []
    # The synthesis canvas matches a warped Sudoku cell (~80-110 px square).
    # `normalize_cell_for_model` crops the outer 14% margin off — which on a
    # real cell is mostly gridline + whitespace. After that crop the actual
    # digit dominates the 32x32 input, so we render with a HIGH fill ratio
    # (≥75% of the canvas height) to match that distribution. Earlier
    # iterations rendered around 50-65% which produced "small digit centred
    # in lots of whitespace" — that does NOT match the inference path.
    cell_canvas_size = 96
    for digit in range(1, 10):
        for _ in range(count_per_digit):
            font_path = fonts[int(rng.integers(0, len(fonts)))]
            # Aim for digits that fill 55-80% of the canvas. Anything bigger
            # than ~80% gets clipped by the 14% crop_center applied later in
            # normalize_cell_for_model. v4 (0.78-1.05) over-shot and broke
            # the model.
            digit_height_ratio = float(rng.uniform(0.55, 0.8))
            point_size = max(16, int(cell_canvas_size * digit_height_ratio))
            try:
                font = ImageFont.truetype(font_path, point_size)
            except OSError:
                continue

            canvas = Image.new("L", (cell_canvas_size, cell_canvas_size), color=255)
            draw = ImageDraw.Draw(canvas)
            text = str(digit)
            bbox = draw.textbbox((0, 0), text, font=font)
            text_w = bbox[2] - bbox[0]
            text_h = bbox[3] - bbox[1]
            jitter = int(round(cell_canvas_size * 0.03))
            cx = cell_canvas_size // 2 + int(rng.integers(-jitter, jitter + 1))
            cy = cell_canvas_size // 2 + int(rng.integers(-jitter, jitter + 1))
            # Real printed digits sit at near-pure black on white. Most of the
            # ink-shade noise we used to add was unrealistic.
            ink = int(rng.integers(0, 35))
            draw.text(
                (cx - text_w // 2 - bbox[0], cy - text_h // 2 - bbox[1]),
                text,
                fill=ink,
                font=font,
            )

            # Optional faint grid-line residue at the canvas edges (mimics the
            # 1-2 px of border that occasionally survives crop_center).
            if rng.random() < 0.3:
                edge = int(rng.integers(1, 3))
                shade = int(rng.integers(150, 210))
                for x in range(edge):
                    canvas.putpixel((x, x), shade)
                    canvas.putpixel((cell_canvas_size - 1 - x, x), shade)
                    canvas.putpixel((x, cell_canvas_size - 1 - x), shade)
                    canvas.putpixel(
                        (cell_canvas_size - 1 - x, cell_canvas_size - 1 - x), shade
                    )

            # Printed sudokus rarely tilt more than a couple of degrees by the
            # time they're warped by extract_board.
            angle = float(rng.uniform(-2.5, 2.5))
            canvas = canvas.rotate(angle, fillcolor=255, resample=Image.BILINEAR)

            if rng.random() < 0.25:
                radius = float(rng.uniform(0.3, 0.9))
                canvas = canvas.filter(ImageFilter.GaussianBlur(radius=radius))

            arr = np.asarray(canvas, dtype=np.uint8)
            foreground = normalize_cell_for_model(arr)
            foreground = foreground.astype(np.float32)
            foreground += rng.normal(0.0, 0.012, foreground.shape).astype(np.float32)
            foreground = np.clip(foreground, 0.0, 1.0)
            images.append(foreground)
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
