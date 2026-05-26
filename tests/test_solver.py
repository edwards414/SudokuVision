from sudoku_vision.solver import solve_unique, validate_grid


PUZZLE = [
    [5, 3, 0, 0, 7, 0, 0, 0, 0],
    [6, 0, 0, 1, 9, 5, 0, 0, 0],
    [0, 9, 8, 0, 0, 0, 0, 6, 0],
    [8, 0, 0, 0, 6, 0, 0, 0, 3],
    [4, 0, 0, 8, 0, 3, 0, 0, 1],
    [7, 0, 0, 0, 2, 0, 0, 0, 6],
    [0, 6, 0, 0, 0, 0, 2, 8, 0],
    [0, 0, 0, 4, 1, 9, 0, 0, 5],
    [0, 0, 0, 0, 8, 0, 0, 7, 9],
]


def test_validate_grid_accepts_valid_partial_grid():
    result = validate_grid(PUZZLE)

    assert result.is_valid is True
    assert result.issues == []


def test_validate_grid_rejects_duplicate_row_value():
    grid = [row.copy() for row in PUZZLE]
    grid[0][2] = 5

    result = validate_grid(grid)

    assert result.is_valid is False
    assert result.issues[0].type == "duplicate_row"


def test_solve_unique_solves_known_puzzle():
    result = solve_unique(PUZZLE)

    assert result.status == "solved"
    assert result.has_unique_solution is True
    assert result.solution is not None
    assert result.solution[0] == [5, 3, 4, 6, 7, 8, 9, 1, 2]


def test_solve_unique_reports_invalid_puzzle():
    grid = [row.copy() for row in PUZZLE]
    grid[0][2] = 5

    result = solve_unique(grid)

    assert result.status == "invalid_puzzle"
    assert result.solution is None
