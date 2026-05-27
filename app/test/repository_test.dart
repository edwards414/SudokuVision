import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sudoku_vision_app/data/sudoku_api_client.dart';
import 'package:sudoku_vision_app/data/sudoku_repository.dart';
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

const _solution = [
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

void main() {
  test('default repository configures the local backend automatically', () {
    final repo = SudokuRepository();
    addTearDown(repo.dispose);

    expect(repo.apiEndpoint, SudokuRepository.defaultApiEndpoint);
    expect(repo.apiClient, isNotNull);
  });

  test('repository can still run without backend for isolated UI tests', () {
    final repo = SudokuRepository(autoConfigureApi: false);
    addTearDown(repo.dispose);

    expect(repo.apiEndpoint, SudokuRepository.defaultApiEndpoint);
    expect(repo.apiClient, isNull);
  });

  test('live recognition can update overlay and committed result together',
      () async {
    final mock = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/recognize/capture');
      return http.Response(
        jsonEncode({
          'grid': _validPuzzle,
          'confidence': [
            for (final row in _validPuzzle) [for (final _ in row) 0.96],
          ],
          'low_confidence_cells': [],
          'status': 'solved',
          'validation': {'is_valid': true, 'issues': []},
          'solve': {
            'status': 'solved',
            'has_unique_solution': true,
            'solution': _solution,
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
          'board_detection_mode': 'auto',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final repo = SudokuRepository(
      apiClient: SudokuApiClient(
        baseUrl: Uri.parse('http://example.test'),
        httpClient: mock,
      ),
    );
    addTearDown(repo.dispose);

    final ok = await repo.refreshLiveOverlay(
      warmupFrames: 0,
      commitResult: true,
    );

    expect(ok, isTrue);
    expect(repo.liveOverlay?.status, RecognitionStatus.solved);
    expect(repo.liveBoardCorners, [
      [20.0, 20.0],
      [180.0, 20.0],
      [180.0, 180.0],
      [20.0, 180.0],
    ]);
    expect(repo.liveSourceWidth, 200);
    expect(repo.liveSourceHeight, 200);
    expect(repo.boardDetectionMode, 'auto');
    expect(repo.result.status, RecognitionStatus.solved);
    expect(repo.result.solution, _solution);
  });

  test('capture recognition stores preview overlay and frame source', () async {
    final mock = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/recognize/capture');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['fallback_corners'], [
        [0.18, 0.08],
        [0.82, 0.08],
        [0.82, 0.92],
        [0.18, 0.92],
      ]);
      return http.Response(
        jsonEncode({
          'grid': _validPuzzle,
          'confidence': [
            for (final row in _validPuzzle) [for (final _ in row) 0.96],
          ],
          'low_confidence_cells': [],
          'status': 'solved',
          'validation': {'is_valid': true, 'issues': []},
          'solve': {
            'status': 'solved',
            'has_unique_solution': true,
            'solution': _solution,
            'message': null,
            'issues': [],
          },
          'board_corners': [
            [18, 8],
            [82, 8],
            [82, 92],
            [18, 92],
          ],
          'source_size': [100, 100],
          'board_detection_mode': 'fallback_corners',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final repo = SudokuRepository(
      apiClient: SudokuApiClient(
        baseUrl: Uri.parse('http://example.test'),
        httpClient: mock,
      ),
    );
    addTearDown(repo.dispose);

    final ok = await repo.captureViaBackend(
      warmupFrames: 0,
      fallbackCorners: const [
        [0.18, 0.08],
        [0.82, 0.08],
        [0.82, 0.92],
        [0.18, 0.92],
      ],
    );

    expect(ok, isTrue);
    expect(repo.result.status, RecognitionStatus.solved);
    expect(repo.liveOverlay?.status, RecognitionStatus.solved);
    expect(repo.liveBoardCorners, [
      [18.0, 8.0],
      [82.0, 8.0],
      [82.0, 92.0],
      [18.0, 92.0],
    ]);
    expect(repo.liveSourceWidth, 100);
    expect(repo.liveSourceHeight, 100);
    expect(repo.boardDetectionMode, 'fallback_corners');
  });
}
