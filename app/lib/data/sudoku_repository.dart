import 'package:flutter/foundation.dart';

import '../models/sudoku_state.dart';
import 'sudoku_api_client.dart';

/// Lightweight in-memory store the UI binds to. When a [SudokuApiClient] is
/// configured, [solve] and [recognizeWithBackend] call the real FastAPI
/// backend; otherwise the in-process solver and sample data are used so the
/// UI can run offline.
class SudokuRepository extends ChangeNotifier {
  SudokuRepository({RecognitionResult? initial, SudokuApiClient? apiClient})
      : _apiClient = apiClient {
    _result = initial ?? _sampleNeedsReview();
  }

  late RecognitionResult _result;
  RecognitionResult get result => _result;

  SudokuApiClient? _apiClient;
  SudokuApiClient? get apiClient => _apiClient;

  bool _busy = false;
  bool get busy => _busy;
  String? _lastError;
  String? get lastError => _lastError;

  String _apiEndpoint = 'http://localhost:8080';
  String get apiEndpoint => _apiEndpoint;

  /// Host camera bridge URL (the FastAPI server in `sudoku_vision.host_camera`).
  /// Separate from [apiEndpoint] because the recogniser usually runs in a
  /// container while the bridge serves frames from the host directly.
  String _bridgeUrl = 'http://localhost:8765';
  String get bridgeUrl => _bridgeUrl;

  void setBridgeUrl(String value) {
    _bridgeUrl = value;
    notifyListeners();
  }

  bool _modelReady = true;
  bool get modelReady => _modelReady;

  /// Normalised 4-corner override (each [x, y] in [0, 1]). Sent with the
  /// next recognise request when set.
  List<List<double>>? _manualCorners;
  List<List<double>>? get manualCorners =>
      _manualCorners == null ? null : [for (final c in _manualCorners!) [...c]];

  void setManualCorners(List<List<double>>? corners) {
    _manualCorners = corners == null
        ? null
        : [for (final c in corners) [c[0], c[1]]];
    notifyListeners();
  }

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

  Future<void> solve() async {
    if (_apiClient != null) {
      await _runBackend(() async {
        final next = await _apiClient!.solve(_result.grid);
        _result = _result.copyWith(
          status: next.status,
          solution: next.solution,
          message: next.message,
        );
      });
      return;
    }
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

  /// Send a captured image to the backend and replace [result] with what the
  /// recogniser returns. Falls back to [loadSample] when no API is configured.
  Future<void> recognizeWithBackend({
    required Uint8List imageBytes,
    List<List<double>>? corners,
  }) async {
    if (_apiClient == null) {
      loadSample();
      return;
    }
    await _runBackend(() async {
      _result = await _apiClient!.recognize(
        imageBytes: imageBytes,
        corners: corners,
      );
    });
  }

  /// Latest live-overlay recognition response (independent of [result] which
  /// is the user-confirmed snapshot). Updated by the periodic poll the camera
  /// page kicks off; null when live overlay isn't running or hasn't returned
  /// a usable response yet.
  RecognitionResult? _liveOverlay;
  RecognitionResult? get liveOverlay => _liveOverlay;
  /// Raw board corners returned with the last live recognise call, in source
  /// image pixel coordinates. Needed to map the grid back onto the live image.
  List<List<double>>? _liveBoardCorners;
  List<List<double>>? get liveBoardCorners => _liveBoardCorners;
  /// Width/height of the image the last live recognise ran against — used to
  /// map [liveBoardCorners] from image pixels into widget space.
  double? _liveSourceWidth;
  double? _liveSourceHeight;
  String? _boardDetectionMode;
  double? get liveSourceWidth => _liveSourceWidth;
  double? get liveSourceHeight => _liveSourceHeight;
  String? get boardDetectionMode => _boardDetectionMode;

  void clearLiveOverlay() {
    _liveOverlay = null;
    _liveBoardCorners = null;
    _liveSourceWidth = null;
    _liveSourceHeight = null;
    _boardDetectionMode = null;
    notifyListeners();
  }

  void _applyCaptureResponse(
    CaptureRecognizeResponse response, {
    required bool commitResult,
  }) {
    _liveOverlay = response.result;
    if (commitResult) {
      _result = response.result;
    }
    _liveBoardCorners = response.boardCorners;
    _liveSourceWidth = response.sourceWidth;
    _liveSourceHeight = response.sourceHeight;
    _boardDetectionMode = response.boardDetectionMode;
  }

  /// Drives [liveOverlay] from a periodic poll. Same backend call as
  /// [captureViaBackend]. By default it only updates the overlay; when
  /// [commitResult] is true the camera page also treats the live frame as the
  /// current recognition/answer shown in the same window.
  Future<bool> refreshLiveOverlay({
    int warmupFrames = 3,
    bool commitResult = false,
    List<List<double>>? corners,
    List<List<double>>? fallbackCorners,
  }) async {
    final client = _apiClient;
    if (client == null) return false;
    try {
      final response = await client.captureRecognizeRaw(
        warmupFrames: warmupFrames,
        corners: corners,
        fallbackCorners: fallbackCorners,
      );
      _applyCaptureResponse(response, commitResult: commitResult);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ask the backend to grab a frame from its own camera/stream and run the
  /// recognise pipeline. Returns true when the API call succeeded; falls back
  /// to [loadSample] (and returns false) when no API client is configured.
  Future<bool> captureViaBackend({
    List<List<double>>? corners,
    List<List<double>>? fallbackCorners,
    int warmupFrames = 10,
  }) async {
    if (_apiClient == null) {
      loadSample();
      return false;
    }
    var ok = false;
    await _runBackend(() async {
      final response = await _apiClient!.captureRecognizeRaw(
        corners: corners,
        fallbackCorners: fallbackCorners,
        warmupFrames: warmupFrames,
      );
      _applyCaptureResponse(response, commitResult: true);
      ok = true;
    });
    return ok && _lastError == null;
  }

  /// Hit GET /health on the configured backend. Used by the Settings page.
  Future<bool> pingBackend() async {
    if (_apiClient == null) return false;
    try {
      return await _apiClient!.health();
    } catch (_) {
      return false;
    }
  }

  Future<void> _runBackend(Future<void> Function() action) async {
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await action();
    } catch (err) {
      _lastError = err.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void configureApi(Uri baseUrl) {
    _apiClient?.close();
    _apiClient = SudokuApiClient(baseUrl: baseUrl);
    _apiEndpoint = baseUrl.toString();
    notifyListeners();
  }

  void disableApi() {
    _apiClient?.close();
    _apiClient = null;
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

  void setApiEndpoint(String value) {
    _apiEndpoint = value;
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) {
      configureApi(uri);
    } else {
      disableApi();
    }
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
