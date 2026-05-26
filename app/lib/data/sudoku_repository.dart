import 'package:flutter/foundation.dart';

import '../models/sudoku_state.dart';

/// Lightweight in-memory store the UI binds to. Replace [loadSample] with a
/// call into the real backend (camera + recogniser + solver) when integrating
/// with `sudoku_vision`.
class SudokuRepository extends ChangeNotifier {
  SudokuRepository({RecognitionResult? initial}) {
    _result = initial ?? _sampleNeedsReview();
  }

  late RecognitionResult _result;
  RecognitionResult get result => _result;

  String _cameraSource = 'FaceTime HD Camera';
  String get cameraSource => _cameraSource;

  String _apiEndpoint = 'http://localhost:8080';
  String get apiEndpoint => _apiEndpoint;

  bool _modelReady = true;
  bool get modelReady => _modelReady;

  void setResult(RecognitionResult next) {
    _result = next;
    notifyListeners();
  }

  void setCell(int row, int col, int value) {
    final grid = [for (final r in _result.grid) [...r]];
    grid[row][col] = value;
    final low = _result.lowConfidenceCells
        .where((c) => !(c.row == row && c.col == col))
        .toList(growable: false);
    _result = _result.copyWith(
      grid: grid,
      lowConfidenceCells: low,
      status: RecognitionStatus.needsReview,
      solution: null,
      message: null,
    );
    notifyListeners();
  }

  void solve() {
    final solved = _solve(_result.grid);
    if (solved == null) {
      _result = _result.copyWith(
        status: findConflicts(_result.grid).isNotEmpty
            ? RecognitionStatus.invalidPuzzle
            : RecognitionStatus.noSolution,
        message: '目前的格子無法產生有效解，請檢查辨識結果。',
      );
    } else {
      _result = _result.copyWith(
        status: RecognitionStatus.solved,
        solution: solved,
        message: null,
      );
    }
    notifyListeners();
  }

  void loadSample({RecognitionStatus state = RecognitionStatus.needsReview}) {
    switch (state) {
      case RecognitionStatus.needsReview:
        _result = _sampleNeedsReview();
        break;
      case RecognitionStatus.solved:
        final base = _sampleNeedsReview();
        _result = base.copyWith(
          status: RecognitionStatus.solved,
          lowConfidenceCells: const [],
          solution: _solve(base.grid),
        );
        break;
      case RecognitionStatus.invalidPuzzle:
        _result = _sampleInvalid();
        break;
      case RecognitionStatus.noSolution:
        _result = _sampleNeedsReview().copyWith(
          status: RecognitionStatus.noSolution,
          message: '此題目目前找不到解，建議重新拍攝或修正辨識。',
        );
        break;
      case RecognitionStatus.multipleSolutions:
        _result = _sampleNeedsReview().copyWith(
          status: RecognitionStatus.multipleSolutions,
          message: '此題目不只一組解，請確認題目是否完整。',
        );
        break;
    }
    notifyListeners();
  }

  void setCameraSource(String value) {
    _cameraSource = value;
    notifyListeners();
  }

  void setApiEndpoint(String value) {
    _apiEndpoint = value;
    notifyListeners();
  }

  void setModelReady(bool ready) {
    _modelReady = ready;
    notifyListeners();
  }
}

RecognitionResult _sampleNeedsReview() {
  const grid = [
    [5, 3, 0, 0, 7, 0, 0, 0, 0],
    [6, 0, 0, 1, 9, 5, 0, 0, 0],
    [0, 9, 8, 0, 0, 0, 0, 6, 0],
    [8, 0, 0, 0, 6, 0, 0, 0, 3],
    [4, 0, 0, 8, 0, 3, 0, 0, 1],
    [7, 0, 0, 0, 2, 0, 0, 0, 6],
    [0, 6, 0, 0, 0, 0, 2, 8, 0],
    [0, 0, 0, 4, 1, 9, 0, 0, 5],
    [0, 0, 0, 0, 8, 0, 0, 7, 9],
  ];
  final given = [
    for (final row in grid) [for (final v in row) v != 0],
  ];
  final confidence = [
    for (final row in grid)
      [for (final v in row) v == 0 ? 1.0 : 0.97],
  ];
  confidence[0][4] = 0.62;
  confidence[3][4] = 0.78;
  confidence[7][3] = 0.81;
  return RecognitionResult(
    grid: [for (final r in grid) [...r]],
    givenMask: given,
    confidence: confidence,
    lowConfidenceCells: const [
      LowConfidenceCell(row: 0, col: 4, predicted: 7, confidence: 0.62),
      LowConfidenceCell(row: 3, col: 4, predicted: 6, confidence: 0.78),
      LowConfidenceCell(row: 7, col: 3, predicted: 4, confidence: 0.81),
    ],
    status: RecognitionStatus.needsReview,
  );
}

RecognitionResult _sampleInvalid() {
  final base = _sampleNeedsReview();
  final grid = [for (final r in base.grid) [...r]];
  grid[0][2] = 5;
  return base.copyWith(
    grid: grid,
    status: RecognitionStatus.invalidPuzzle,
    message: '偵測到衝突：列 1 出現兩個 5。',
  );
}

/// Backtracking solver used purely so the UI demo can show a real solution.
/// The production solver lives in `sudoku_vision/solver.py`.
List<List<int>>? _solve(List<List<int>> input) {
  final grid = [for (final r in input) [...r]];
  bool helper() {
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        if (grid[r][c] != 0) continue;
        for (var v = 1; v <= 9; v++) {
          if (_canPlace(grid, r, c, v)) {
            grid[r][c] = v;
            if (helper()) return true;
            grid[r][c] = 0;
          }
        }
        return false;
      }
    }
    return true;
  }

  if (findConflicts(grid).isNotEmpty) return null;
  return helper() ? grid : null;
}

bool _canPlace(List<List<int>> grid, int row, int col, int value) {
  for (var i = 0; i < 9; i++) {
    if (grid[row][i] == value) return false;
    if (grid[i][col] == value) return false;
  }
  final br = (row ~/ 3) * 3;
  final bc = (col ~/ 3) * 3;
  for (var r = br; r < br + 3; r++) {
    for (var c = bc; c < bc + 3; c++) {
      if (grid[r][c] == value) return false;
    }
  }
  return true;
}
