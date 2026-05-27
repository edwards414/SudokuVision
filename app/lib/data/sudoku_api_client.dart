import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/sudoku_state.dart';

/// Talks to the FastAPI backend exposed by `sudoku_vision.api`.
class SudokuApiClient {
  SudokuApiClient({required this.baseUrl, http.Client? httpClient})
      : _client = httpClient ?? http.Client();

  Uri baseUrl;
  final http.Client _client;

  void close() => _client.close();

  Future<bool> health() async {
    final response = await _client.get(baseUrl.resolve('/health'));
    if (response.statusCode != 200) return false;
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return payload['status'] == 'ok';
  }

  Future<RecognitionResult> solve(List<List<int>> grid) async {
    final response = await _client.post(
      baseUrl.resolve('/solve'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'grid': grid}),
    );
    _ensureOk(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return _resultFromSolveResponse(grid: grid, payload: payload);
  }

  /// POST /recognize/capture — let the server grab a frame from its
  /// configured camera/stream and run the pipeline. No client-side image
  /// upload required.
  Future<RecognitionResult> captureRecognize({
    List<List<double>>? corners,
    List<List<double>>? fallbackCorners,
    int boardSize = 900,
    int warmupFrames = 10,
    String? source,
  }) async {
    final raw = await captureRecognizeRaw(
      corners: corners,
      fallbackCorners: fallbackCorners,
      boardSize: boardSize,
      warmupFrames: warmupFrames,
      source: source,
    );
    return raw.result;
  }

  /// Full capture response including [boardCorners] and the source image
  /// dimensions — needed by the live overlay that projects the recognised
  /// grid back onto the preview.
  Future<CaptureRecognizeResponse> captureRecognizeRaw({
    List<List<double>>? corners,
    List<List<double>>? fallbackCorners,
    int boardSize = 900,
    int warmupFrames = 10,
    String? source,
  }) async {
    final body = <String, dynamic>{
      'board_size': boardSize,
      'warmup_frames': warmupFrames,
    };
    if (corners != null) body['corners'] = corners;
    if (fallbackCorners != null) body['fallback_corners'] = fallbackCorners;
    if (source != null && source.isNotEmpty) body['source'] = source;
    final response = await _client.post(
      baseUrl.resolve('/recognize/capture'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(body),
    );
    _ensureOk(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final result = _resultFromRecognizeResponse(payload);
    final cornersList = (payload['board_corners'] as List?)
        ?.map<List<double>>(
          (row) => (row as List).map((v) => (v as num).toDouble()).toList(),
        )
        .toList();
    final size = (payload['source_size'] as List?)
        ?.map((v) => (v as num).toDouble())
        .toList();
    return CaptureRecognizeResponse(
      result: result,
      boardCorners: cornersList,
      sourceWidth: size != null && size.length == 2 ? size[0] : null,
      sourceHeight: size != null && size.length == 2 ? size[1] : null,
    );
  }

  Future<RecognitionResult> recognize({
    required Uint8List imageBytes,
    String filename = 'capture.png',
    String contentType = 'image/png',
    List<List<double>>? corners,
    int boardSize = 900,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      baseUrl.resolve('/recognize'),
    );
    request.files.add(http.MultipartFile.fromBytes(
      'image',
      imageBytes,
      filename: filename,
    ));
    request.fields['board_size'] = '$boardSize';
    if (corners != null) {
      request.fields['corners'] = jsonEncode(corners);
    }
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    _ensureOk(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return _resultFromRecognizeResponse(payload);
  }

  void _ensureOk(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw SudokuApiException(
      statusCode: response.statusCode,
      body: response.body,
    );
  }

  RecognitionResult _resultFromSolveResponse({
    required List<List<int>> grid,
    required Map<String, dynamic> payload,
  }) {
    final validation = payload['validation'] as Map<String, dynamic>;
    final isValid = validation['is_valid'] as bool;
    final solve = payload['solve'] as Map<String, dynamic>?;
    final status = !isValid
        ? RecognitionStatus.invalidPuzzle
        : solve == null
            ? RecognitionStatus.needsReview
            : parseStatus(solve['status'] as String);
    final solution = (solve?['solution'] as List?)
        ?.map<List<int>>((row) => (row as List).cast<int>())
        .toList();
    final given = [
      for (final row in grid) [for (final v in row) v != 0],
    ];
    final confidence = [
      for (final row in grid)
        [for (final _ in row) 1.0],
    ];
    return RecognitionResult(
      grid: [for (final r in grid) [...r]],
      givenMask: given,
      confidence: confidence,
      lowConfidenceCells: const [],
      status: status,
      solution: solution,
      message: solve?['message'] as String?,
    );
  }

  RecognitionResult _resultFromRecognizeResponse(Map<String, dynamic> payload) {
    final grid = (payload['grid'] as List)
        .map<List<int>>((row) => (row as List).cast<int>())
        .toList();
    final confidenceRaw = (payload['confidence'] as List)
        .map<List<double>>(
          (row) => (row as List).map((v) => (v as num).toDouble()).toList(),
        )
        .toList();
    final lowRaw = (payload['low_confidence_cells'] as List).cast<Map>();
    final low = [
      for (final m in lowRaw)
        LowConfidenceCell(
          row: (m['row'] as num).toInt(),
          col: (m['col'] as num).toInt(),
          predicted: (m['predicted'] as num).toInt(),
          confidence: (m['confidence'] as num).toDouble(),
        ),
    ];
    final given = [
      for (final row in grid) [for (final v in row) v != 0],
    ];
    final solve = payload['solve'] as Map<String, dynamic>?;
    final solution = (solve?['solution'] as List?)
        ?.map<List<int>>((row) => (row as List).cast<int>())
        .toList();
    final status = parseStatus((payload['status'] as String?) ?? 'needs_review');
    return RecognitionResult(
      grid: grid,
      givenMask: given,
      confidence: confidenceRaw,
      lowConfidenceCells: low,
      status: status,
      solution: solution,
      message: solve?['message'] as String?,
    );
  }
}

class CaptureRecognizeResponse {
  CaptureRecognizeResponse({
    required this.result,
    required this.boardCorners,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  final RecognitionResult result;
  final List<List<double>>? boardCorners;
  final double? sourceWidth;
  final double? sourceHeight;
}

class SudokuApiException implements Exception {
  SudokuApiException({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  @override
  String toString() => 'SudokuApiException($statusCode): $body';
}
