import 'package:flutter/foundation.dart';

enum RecognitionStatus {
  needsReview,
  solved,
  invalidPuzzle,
  noSolution,
  multipleSolutions,
}

RecognitionStatus parseStatus(String value) {
  switch (value) {
    case 'solved':
      return RecognitionStatus.solved;
    case 'invalid_puzzle':
      return RecognitionStatus.invalidPuzzle;
    case 'no_solution':
      return RecognitionStatus.noSolution;
    case 'multiple_solutions':
      return RecognitionStatus.multipleSolutions;
    case 'needs_review':
    default:
      return RecognitionStatus.needsReview;
  }
}

@immutable
class CellPosition {
  const CellPosition(this.row, this.col);

  final int row;
  final int col;

  @override
  bool operator ==(Object other) =>
      other is CellPosition && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);
}

@immutable
class LowConfidenceCell {
  const LowConfidenceCell({
    required this.row,
    required this.col,
    required this.predicted,
    required this.confidence,
  });

  final int row;
  final int col;
  final int predicted;
  final double confidence;
}

@immutable
class RecognitionResult {
  const RecognitionResult({
    required this.grid,
    required this.givenMask,
    required this.confidence,
    required this.lowConfidenceCells,
    required this.status,
    this.solution,
    this.message,
  });

  /// 9x9 grid of recognised values. 0 means empty.
  final List<List<int>> grid;

  /// 9x9 mask marking cells that came from the original puzzle (vs user edits).
  final List<List<bool>> givenMask;

  /// 9x9 confidence values (0.0 - 1.0).
  final List<List<double>> confidence;

  final List<LowConfidenceCell> lowConfidenceCells;
  final RecognitionStatus status;

  /// 9x9 solved grid, when [status] is [RecognitionStatus.solved].
  final List<List<int>>? solution;

  final String? message;

  bool isLowConfidence(int row, int col) {
    return lowConfidenceCells.any((c) => c.row == row && c.col == col);
  }

  RecognitionResult copyWith({
    List<List<int>>? grid,
    List<List<bool>>? givenMask,
    List<List<double>>? confidence,
    List<LowConfidenceCell>? lowConfidenceCells,
    RecognitionStatus? status,
    List<List<int>>? solution,
    String? message,
  }) {
    return RecognitionResult(
      grid: grid ?? this.grid,
      givenMask: givenMask ?? this.givenMask,
      confidence: confidence ?? this.confidence,
      lowConfidenceCells: lowConfidenceCells ?? this.lowConfidenceCells,
      status: status ?? this.status,
      solution: solution ?? this.solution,
      message: message ?? this.message,
    );
  }
}

/// Conflict detection (row / col / 3x3 box duplicates). Returns the set of
/// cell positions that violate sudoku rules.
Set<CellPosition> findConflicts(List<List<int>> grid) {
  final conflicts = <CellPosition>{};
  for (var r = 0; r < 9; r++) {
    final seen = <int, List<int>>{};
    for (var c = 0; c < 9; c++) {
      final v = grid[r][c];
      if (v == 0) continue;
      seen.putIfAbsent(v, () => []).add(c);
    }
    for (final entry in seen.entries) {
      if (entry.value.length > 1) {
        for (final c in entry.value) {
          conflicts.add(CellPosition(r, c));
        }
      }
    }
  }
  for (var c = 0; c < 9; c++) {
    final seen = <int, List<int>>{};
    for (var r = 0; r < 9; r++) {
      final v = grid[r][c];
      if (v == 0) continue;
      seen.putIfAbsent(v, () => []).add(r);
    }
    for (final entry in seen.entries) {
      if (entry.value.length > 1) {
        for (final r in entry.value) {
          conflicts.add(CellPosition(r, c));
        }
      }
    }
  }
  for (var br = 0; br < 3; br++) {
    for (var bc = 0; bc < 3; bc++) {
      final seen = <int, List<CellPosition>>{};
      for (var r = br * 3; r < br * 3 + 3; r++) {
        for (var c = bc * 3; c < bc * 3 + 3; c++) {
          final v = grid[r][c];
          if (v == 0) continue;
          seen.putIfAbsent(v, () => []).add(CellPosition(r, c));
        }
      }
      for (final entry in seen.entries) {
        if (entry.value.length > 1) {
          conflicts.addAll(entry.value);
        }
      }
    }
  }
  return conflicts;
}
