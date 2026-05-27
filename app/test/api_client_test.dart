import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sudoku_vision_app/data/sudoku_api_client.dart';
import 'package:sudoku_vision_app/models/sudoku_state.dart';

const _validPuzzle = [
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

const _expectedSolution = [
  [5, 3, 4, 6, 7, 8, 9, 1, 2],
  [6, 7, 2, 1, 9, 5, 3, 4, 8],
  [1, 9, 8, 3, 4, 2, 5, 6, 7],
  [8, 5, 9, 7, 6, 1, 4, 2, 3],
  [4, 2, 6, 8, 5, 3, 7, 9, 1],
  [7, 1, 3, 9, 2, 4, 8, 5, 6],
  [9, 6, 1, 5, 3, 7, 2, 8, 4],
  [2, 8, 7, 4, 1, 9, 6, 3, 5],
  [3, 4, 5, 2, 8, 6, 1, 7, 9],
];

SudokuApiClient _client(MockClient mock) =>
    SudokuApiClient(baseUrl: Uri.parse('http://example.test'), httpClient: mock);

void main() {
  test('solve() posts JSON grid and parses solved status', () async {
    late http.BaseRequest captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'validation': {'is_valid': true, 'issues': []},
          'solve': {
            'status': 'solved',
            'has_unique_solution': true,
            'solution': _expectedSolution,
            'message': null,
            'issues': [],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final result = await _client(mock).solve(_validPuzzle);
    expect(captured.method, 'POST');
    expect(captured.url.path, '/solve');
    expect(result.status, RecognitionStatus.solved);
    expect(result.solution, _expectedSolution);
  });

  test('solve() maps invalid puzzles to RecognitionStatus.invalidPuzzle',
      () async {
    final mock = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'validation': {
            'is_valid': false,
            'issues': [
              {'type': 'duplicate_row', 'row': 0, 'col': 0, 'value': 5},
            ],
          },
          'solve': null,
        }),
        200,
      );
    });
    final result = await _client(mock).solve(_validPuzzle);
    expect(result.status, RecognitionStatus.invalidPuzzle);
    expect(result.solution, isNull);
  });

  test('recognize() uploads multipart with corners and decodes payload',
      () async {
    String? capturedBody;
    String? capturedContentType;
    final mock = MockClient((request) async {
      capturedBody = utf8.decode(request.bodyBytes);
      capturedContentType = request.headers['content-type'];
      return http.Response(
        jsonEncode({
          'grid': [for (final r in _validPuzzle) r],
          'confidence': [
            for (final r in _validPuzzle) [for (final _ in r) 0.95],
          ],
          'low_confidence_cells': [
            {'row': 0, 'col': 4, 'predicted': 7, 'confidence': 0.62},
          ],
          'status': 'needs_review',
          'validation': {'is_valid': true, 'issues': []},
          'solve': null,
        }),
        200,
      );
    });
    final result = await _client(mock).recognize(
      imageBytes: Uint8List.fromList([1, 2, 3]),
      corners: [
        [0.0, 0.0],
        [1.0, 0.0],
        [1.0, 1.0],
        [0.0, 1.0],
      ],
    );
    expect(capturedContentType, contains('multipart/form-data'));
    expect(capturedBody, contains('name="corners"'));
    expect(capturedBody, contains('[[0.0,0.0],[1.0,0.0],[1.0,1.0],[0.0,1.0]]'));
    expect(result.status, RecognitionStatus.needsReview);
    expect(result.lowConfidenceCells, hasLength(1));
    expect(result.lowConfidenceCells.first.predicted, 7);
  });

  test('captureRecognizeRaw() sends fallback_corners for guided capture',
      () async {
    Map<String, dynamic>? capturedBody;
    final mock = MockClient((request) async {
      capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'grid': [for (final r in _validPuzzle) r],
          'confidence': [
            for (final r in _validPuzzle) [for (final _ in r) 0.95],
          ],
          'low_confidence_cells': [],
          'status': 'solved',
          'validation': {'is_valid': true, 'issues': []},
          'solve': {
            'status': 'solved',
            'has_unique_solution': true,
            'solution': _expectedSolution,
            'message': null,
            'issues': [],
          },
          'board_corners': [
            [20, 20],
            [180, 20],
            [180, 180],
            [20, 180],
          ],
          'source_size': [200, 200],
        }),
        200,
      );
    });

    final response = await _client(mock).captureRecognizeRaw(
      warmupFrames: 0,
      fallbackCorners: [
        [0.18, 0.08],
        [0.82, 0.08],
        [0.82, 0.92],
        [0.18, 0.92],
      ],
    );

    expect(capturedBody?['fallback_corners'], [
      [0.18, 0.08],
      [0.82, 0.08],
      [0.82, 0.92],
      [0.18, 0.92],
    ]);
    expect(response.result.status, RecognitionStatus.solved);
  });

  test('solve() throws SudokuApiException on non-2xx response', () async {
    final mock = MockClient((request) async => http.Response('oops', 500));
    await expectLater(
      _client(mock).solve(_validPuzzle),
      throwsA(isA<SudokuApiException>()),
    );
  });
}
