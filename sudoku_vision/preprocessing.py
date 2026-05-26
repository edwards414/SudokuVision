"""Cell preprocessing and empty-cell heuristics for Sudoku digit recognition."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

import numpy as np


@dataclass(frozen=True)
class EmptyCellFeatures:
    """Lightweight image features used before/alongside model classification."""

    black_pixel_ratio: float
    largest_component_ratio: float
    is_empty_candidate: bool


def to_grayscale(image: np.ndarray) -> np.ndarray:
    """Convert an image to grayscale uint8."""

    arr = np.asarray(image)
    if arr.ndim == 2:
        gray = arr
    elif arr.ndim == 3 and arr.shape[2] >= 3:
        # Input may be RGB or BGR. For digit preprocessing the exact channel order
        # is not important; luminance weights still produce a stable grayscale.
        gray = 0.299 * arr[..., 0] + 0.587 * arr[..., 1] + 0.114 * arr[..., 2]
    else:
        raise ValueError(f"Expected 2D grayscale or 3D color image, got shape {arr.shape}")

    gray = np.clip(gray, 0, 255).astype(np.uint8)
    return gray


def crop_center(image: np.ndarray, margin_ratio: float = 0.14) -> np.ndarray:
    """Crop away outer cell borders before classifying the digit."""

    if not 0 <= margin_ratio < 0.45:
        raise ValueError("margin_ratio must be in [0, 0.45)")

    arr = np.asarray(image)
    height, width = arr.shape[:2]
    margin_y = int(round(height * margin_ratio))
    margin_x = int(round(width * margin_ratio))
    cropped = arr[margin_y : height - margin_y, margin_x : width - margin_x]
    if cropped.size == 0:
        raise ValueError("margin_ratio cropped the entire cell")
    return cropped


def resize_nearest(image: np.ndarray, size: int = 32) -> np.ndarray:
    """Resize using nearest neighbor without requiring OpenCV/Pillow."""

    if size <= 0:
        raise ValueError("size must be positive")

    arr = np.asarray(image)
    if arr.ndim != 2:
        raise ValueError("resize_nearest expects a 2D grayscale image")

    src_h, src_w = arr.shape
    y_idx = np.linspace(0, src_h - 1, size).round().astype(np.int64)
    x_idx = np.linspace(0, src_w - 1, size).round().astype(np.int64)
    return arr[np.ix_(y_idx, x_idx)]


def normalize_cell_for_model(
    cell_image: np.ndarray,
    output_size: int = 32,
    margin_ratio: float = 0.14,
) -> np.ndarray:
    """Prepare one cell as a model input tensor with shape ``(size, size, 1)``.

    The Tiny CNN expects dark digits on a light background, converted to a
    normalized foreground map where digit strokes approach 1.0 and background
    approaches 0.0.
    """

    gray = to_grayscale(cell_image)
    cropped = crop_center(gray, margin_ratio=margin_ratio)
    resized = resize_nearest(cropped, size=output_size)
    foreground = 1.0 - resized.astype(np.float32) / 255.0
    return foreground[..., np.newaxis]


def _binary_foreground(gray: np.ndarray) -> np.ndarray:
    """Return a foreground mask for dark strokes using an adaptive-ish threshold."""

    # Sudoku cells are usually black digits/gridlines on white paper. A percentile
    # threshold is more tolerant of shadows than a hard 128 cutoff.
    threshold = min(180.0, float(np.percentile(gray, 35)))
    return gray < threshold


def _largest_component_ratio(mask: np.ndarray) -> float:
    """Compute largest connected foreground component ratio in a small mask."""

    if mask.ndim != 2:
        raise ValueError("mask must be 2D")

    height, width = mask.shape
    total = height * width
    if total == 0 or not mask.any():
        return 0.0

    visited = np.zeros(mask.shape, dtype=bool)
    largest = 0
    neighbors: tuple[tuple[int, int], ...] = ((1, 0), (-1, 0), (0, 1), (0, -1))

    for start_y, start_x in zip(*np.where(mask & ~visited), strict=False):
        if visited[start_y, start_x]:
            continue

        stack = [(int(start_y), int(start_x))]
        visited[start_y, start_x] = True
        area = 0

        while stack:
            y, x = stack.pop()
            area += 1
            for dy, dx in neighbors:
                ny = y + dy
                nx = x + dx
                if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not visited[ny, nx]:
                    visited[ny, nx] = True
                    stack.append((ny, nx))

        largest = max(largest, area)

    return largest / float(total)


def estimate_empty_cell(
    cell_image: np.ndarray,
    margin_ratio: float = 0.18,
    black_pixel_threshold: float = 0.025,
    component_threshold: float = 0.018,
) -> EmptyCellFeatures:
    """Estimate whether a cell is empty using CV features.

    This is intentionally conservative. It marks obvious blanks as empty
    candidates, while ambiguous cells continue to the CNN.
    """

    gray = to_grayscale(cell_image)
    cropped = crop_center(gray, margin_ratio=margin_ratio)
    mask = _binary_foreground(cropped)
    black_pixel_ratio = float(mask.mean())
    largest_component_ratio = _largest_component_ratio(mask)
    is_empty = (
        black_pixel_ratio < black_pixel_threshold
        and largest_component_ratio < component_threshold
    )
    return EmptyCellFeatures(
        black_pixel_ratio=black_pixel_ratio,
        largest_component_ratio=largest_component_ratio,
        is_empty_candidate=is_empty,
    )


def split_board_cells(board_image: np.ndarray, grid_size: int = 9) -> list[list[np.ndarray]]:
    """Split a perspective-corrected square board image into a 9x9 cell matrix."""

    if grid_size <= 0:
        raise ValueError("grid_size must be positive")

    arr = np.asarray(board_image)
    height, width = arr.shape[:2]
    if height < grid_size or width < grid_size:
        raise ValueError("board image is smaller than the requested grid")

    y_edges = np.linspace(0, height, grid_size + 1).round().astype(np.int64)
    x_edges = np.linspace(0, width, grid_size + 1).round().astype(np.int64)
    cells: list[list[np.ndarray]] = []
    for row in range(grid_size):
        row_cells: list[np.ndarray] = []
        for col in range(grid_size):
            row_cells.append(arr[y_edges[row] : y_edges[row + 1], x_edges[col] : x_edges[col + 1]])
        cells.append(row_cells)
    return cells


def flatten_cells(cells: Iterable[Iterable[np.ndarray]]) -> list[np.ndarray]:
    """Flatten a 9x9 cell matrix while validating its shape."""

    rows = [list(row) for row in cells]
    if len(rows) != 9 or any(len(row) != 9 for row in rows):
        raise ValueError("cells must be a 9x9 matrix")
    return [cell for row in rows for cell in row]
