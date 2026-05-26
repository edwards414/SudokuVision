"""Sudoku grid validation and solving."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

Grid = list[list[int]]
SolveStatus = Literal["solved", "invalid_puzzle", "no_solution", "multiple_solutions"]


@dataclass(frozen=True)
class GridIssue:
    type: str
    row: int | None = None
    col: int | None = None
    value: int | None = None
    message: str = ""


@dataclass(frozen=True)
class ValidationResult:
    is_valid: bool
    issues: list[GridIssue]


@dataclass(frozen=True)
class SolveResult:
    status: SolveStatus
    has_unique_solution: bool
    solution: Grid | None
    message: str | None = None
    issues: list[GridIssue] | None = None


def _copy_grid(grid: Grid) -> Grid:
    return [list(row) for row in grid]


def validate_grid(grid: Grid) -> ValidationResult:
    """Validate shape, values, and duplicate givens."""

    issues: list[GridIssue] = []
    if len(grid) != 9:
        issues.append(GridIssue(type="shape", message="Grid must have 9 rows"))
        return ValidationResult(False, issues)

    for row_idx, row in enumerate(grid):
        if len(row) != 9:
            issues.append(
                GridIssue(type="shape", row=row_idx, message="Each row must have 9 columns")
            )
            continue
        for col_idx, value in enumerate(row):
            if not isinstance(value, int) or not 0 <= value <= 9:
                issues.append(
                    GridIssue(
                        type="value",
                        row=row_idx,
                        col=col_idx,
                        value=value if isinstance(value, int) else None,
                        message="Cell value must be an integer from 0 to 9",
                    )
                )

    if issues:
        return ValidationResult(False, issues)

    def check_unit(cells: list[tuple[int, int]], unit_type: str) -> None:
        seen: dict[int, tuple[int, int]] = {}
        for row, col in cells:
            value = grid[row][col]
            if value == 0:
                continue
            if value in seen:
                first_row, first_col = seen[value]
                issues.append(
                    GridIssue(
                        type=f"duplicate_{unit_type}",
                        row=row,
                        col=col,
                        value=value,
                        message=(
                            f"Duplicate {value} at ({first_row}, {first_col}) "
                            f"and ({row}, {col})"
                        ),
                    )
                )
            else:
                seen[value] = (row, col)

    for idx in range(9):
        check_unit([(idx, col) for col in range(9)], "row")
        check_unit([(row, idx) for row in range(9)], "column")

    for box_row in range(0, 9, 3):
        for box_col in range(0, 9, 3):
            check_unit(
                [(box_row + dr, box_col + dc) for dr in range(3) for dc in range(3)],
                "box",
            )

    return ValidationResult(not issues, issues)


def _candidates(grid: Grid, row: int, col: int) -> set[int]:
    used = set(grid[row])
    used.update(grid[r][col] for r in range(9))
    box_row = (row // 3) * 3
    box_col = (col // 3) * 3
    used.update(grid[box_row + dr][box_col + dc] for dr in range(3) for dc in range(3))
    return set(range(1, 10)) - used


def _select_next_cell(grid: Grid) -> tuple[int, int, set[int]] | None:
    best: tuple[int, int, set[int]] | None = None
    for row in range(9):
        for col in range(9):
            if grid[row][col] != 0:
                continue
            candidates = _candidates(grid, row, col)
            if best is None or len(candidates) < len(best[2]):
                best = (row, col, candidates)
            if len(candidates) == 0:
                return best
    return best


def _search(grid: Grid, solutions: list[Grid], limit: int) -> None:
    if len(solutions) >= limit:
        return

    next_cell = _select_next_cell(grid)
    if next_cell is None:
        solutions.append(_copy_grid(grid))
        return

    row, col, candidates = next_cell
    if not candidates:
        return

    for value in sorted(candidates):
        grid[row][col] = value
        _search(grid, solutions, limit)
        grid[row][col] = 0
        if len(solutions) >= limit:
            return


def solve_unique(grid: Grid) -> SolveResult:
    """Solve a Sudoku puzzle and distinguish invalid/no/multiple solutions."""

    validation = validate_grid(grid)
    if not validation.is_valid:
        return SolveResult(
            status="invalid_puzzle",
            has_unique_solution=False,
            solution=None,
            message="Puzzle violates Sudoku rules",
            issues=validation.issues,
        )

    working = _copy_grid(grid)
    solutions: list[Grid] = []
    _search(working, solutions, limit=2)

    if not solutions:
        return SolveResult(
            status="no_solution",
            has_unique_solution=False,
            solution=None,
            message="Puzzle has no valid solution",
            issues=[],
        )

    if len(solutions) > 1:
        return SolveResult(
            status="multiple_solutions",
            has_unique_solution=False,
            solution=solutions[0],
            message="Puzzle has more than one solution",
            issues=[],
        )

    return SolveResult(
        status="solved",
        has_unique_solution=True,
        solution=solutions[0],
        message=None,
        issues=[],
    )
