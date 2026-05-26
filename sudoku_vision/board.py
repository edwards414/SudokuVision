"""OpenCV-based Sudoku board detection and perspective correction."""

from __future__ import annotations

import numpy as np

from sudoku_vision.errors import OptionalDependencyError


def _require_cv2():
    try:
        import cv2  # type: ignore
    except ModuleNotFoundError as exc:
        raise OptionalDependencyError("opencv-python", "Sudoku board detection") from exc
    return cv2


def order_points(points: np.ndarray) -> np.ndarray:
    """Order four points as top-left, top-right, bottom-right, bottom-left."""

    pts = np.asarray(points, dtype=np.float32).reshape(4, 2)
    sums = pts.sum(axis=1)
    diffs = np.diff(pts, axis=1).ravel()
    ordered = np.zeros((4, 2), dtype=np.float32)
    ordered[0] = pts[np.argmin(sums)]
    ordered[2] = pts[np.argmax(sums)]
    ordered[1] = pts[np.argmin(diffs)]
    ordered[3] = pts[np.argmax(diffs)]
    return ordered


def warp_board(image: np.ndarray, corners: np.ndarray, output_size: int = 900) -> np.ndarray:
    """Perspective-correct the board into a square image."""

    cv2 = _require_cv2()
    if output_size <= 0:
        raise ValueError("output_size must be positive")

    src = order_points(corners)
    dst = np.array(
        [
            [0, 0],
            [output_size - 1, 0],
            [output_size - 1, output_size - 1],
            [0, output_size - 1],
        ],
        dtype=np.float32,
    )
    matrix = cv2.getPerspectiveTransform(src, dst)
    return cv2.warpPerspective(image, matrix, (output_size, output_size))


def find_board_corners(image: np.ndarray) -> np.ndarray:
    """Find the largest square-like contour as Sudoku board corners."""

    cv2 = _require_cv2()
    arr = np.asarray(image)
    if arr.ndim == 3:
        gray = cv2.cvtColor(arr, cv2.COLOR_BGR2GRAY)
    elif arr.ndim == 2:
        gray = arr
    else:
        raise ValueError(f"Expected grayscale or BGR image, got shape {arr.shape}")

    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    thresh = cv2.adaptiveThreshold(
        blurred,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY_INV,
        11,
        2,
    )

    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    contours = sorted(contours, key=cv2.contourArea, reverse=True)

    image_area = gray.shape[0] * gray.shape[1]
    for contour in contours[:20]:
        area = cv2.contourArea(contour)
        if area < image_area * 0.05:
            continue

        perimeter = cv2.arcLength(contour, True)
        approx = cv2.approxPolyDP(contour, 0.02 * perimeter, True)
        if len(approx) != 4:
            continue

        corners = approx.reshape(4, 2).astype(np.float32)
        ordered = order_points(corners)
        width_top = np.linalg.norm(ordered[1] - ordered[0])
        width_bottom = np.linalg.norm(ordered[2] - ordered[3])
        height_left = np.linalg.norm(ordered[3] - ordered[0])
        height_right = np.linalg.norm(ordered[2] - ordered[1])
        width = (width_top + width_bottom) / 2.0
        height = (height_left + height_right) / 2.0
        if width <= 0 or height <= 0:
            continue

        aspect = width / height
        if 0.75 <= aspect <= 1.25:
            return ordered

    raise ValueError("Could not detect a square-like Sudoku board")


def extract_board(image: np.ndarray, output_size: int = 900) -> tuple[np.ndarray, np.ndarray]:
    """Detect and warp the Sudoku board from an input image."""

    corners = find_board_corners(image)
    return warp_board(image, corners, output_size=output_size), corners
