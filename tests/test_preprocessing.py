import numpy as np

from sudoku_vision.preprocessing import (
    estimate_empty_cell,
    normalize_cell_for_model,
    split_board_cells,
)


def test_empty_cell_estimate_marks_blank_cell():
    cell = np.full((100, 100), 255, dtype=np.uint8)

    features = estimate_empty_cell(cell)

    assert features.is_empty_candidate is True
    assert features.black_pixel_ratio == 0.0
    assert features.largest_component_ratio == 0.0


def test_empty_cell_estimate_marks_digit_like_cell_not_empty():
    cell = np.full((100, 100), 255, dtype=np.uint8)
    cell[30:75, 45:58] = 0
    cell[30:42, 35:65] = 0

    features = estimate_empty_cell(cell)

    assert features.is_empty_candidate is False
    assert features.black_pixel_ratio > 0.025


def test_normalize_cell_for_model_returns_32x32_foreground_tensor():
    cell = np.full((100, 100), 255, dtype=np.uint8)
    cell[40:60, 40:60] = 0

    tensor = normalize_cell_for_model(cell)

    assert tensor.shape == (32, 32, 1)
    assert tensor.dtype == np.float32
    assert tensor.max() == 1.0
    assert tensor.min() == 0.0


def test_split_board_cells_returns_9_by_9_cells():
    board = np.zeros((90, 90), dtype=np.uint8)

    cells = split_board_cells(board)

    assert len(cells) == 9
    assert all(len(row) == 9 for row in cells)
    assert cells[0][0].shape == (10, 10)
