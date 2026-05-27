import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudoku_vision_app/app.dart';
import 'package:sudoku_vision_app/data/sudoku_repository.dart';
import 'package:sudoku_vision_app/models/sudoku_state.dart';
import 'package:sudoku_vision_app/pages/camera_page.dart';
import 'package:sudoku_vision_app/pages/review_page.dart';
import 'package:sudoku_vision_app/pages/solution_page.dart';
import 'package:sudoku_vision_app/widgets/repository_scope.dart';
import 'package:sudoku_vision_app/widgets/sudoku_grid.dart';

Widget _wrap(Widget child, SudokuRepository repo) {
  return CupertinoApp(
    home: RepositoryScope(repository: repo, child: child),
  );
}

void main() {
  testWidgets('Cupertino root and tab shell render', (tester) async {
    final repo = SudokuRepository(autoConfigureApi: false);
    addTearDown(repo.dispose);
    await tester.pumpWidget(SudokuVisionApp(repository: repo));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoApp), findsOneWidget);
    expect(find.byType(CupertinoTabScaffold), findsOneWidget);
    expect(find.text('相機'), findsWidgets);
    expect(find.text('辨識'), findsOneWidget);
    expect(find.text('解答'), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);
  });

  testWidgets('Camera page exposes capture action and Cupertino chrome',
      (tester) async {
    final repo = SudokuRepository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(_wrap(const CameraPage(), repo));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.text('拍照辨識'), findsOneWidget);
    expect(find.bySemanticsLabel('即時辨識'), findsOneWidget);
    expect(find.text('對齊藍框後辨識'), findsOneWidget);
  });

  testWidgets('Camera page shows recognition and answer in the same window',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = SudokuRepository();
    addTearDown(repo.dispose);
    repo.loadSample(state: RecognitionStatus.solved);

    await tester.pumpWidget(_wrap(const CameraPage(), repo));
    await tester.pumpAndSettle();

    expect(find.text('相機'), findsOneWidget);
    expect(find.text('辨識結果'), findsOneWidget);
    expect(find.text('答案'), findsOneWidget);
    expect(find.byType(SudokuGrid), findsOneWidget);
    expect(find.text('已找到唯一解。'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('Camera page mobile layout fits without scrolling',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = SudokuRepository();
    addTearDown(repo.dispose);
    repo.loadSample(state: RecognitionStatus.solved);

    await tester.pumpWidget(_wrap(const CameraPage(), repo));
    await tester.pumpAndSettle();

    expect(find.text('對齊藍框後辨識'), findsOneWidget);
    expect(find.text('辨識結果'), findsOneWidget);
    expect(find.text('答案'), findsOneWidget);
    expect(find.byType(SudokuGrid), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('Review page surfaces low-confidence cells with non-color cue',
      (tester) async {
    final repo = SudokuRepository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(_wrap(const ReviewPage(), repo));
    await tester.pumpAndSettle();
    expect(find.text('辨識確認'), findsOneWidget);
    expect(
      find.byIcon(CupertinoIcons.exclamationmark_circle_fill),
      findsWidgets,
    );
    expect(find.text('求解'), findsOneWidget);
  });

  testWidgets('Review → number pad updates the grid', (tester) async {
    final repo = SudokuRepository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(_wrap(const ReviewPage(), repo));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    await tester.tap(find.text('列 1，欄 5　預測 7'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('numpad-4')));
    await tester.pumpAndSettle();
    expect(repo.result.grid[0][4], 4);
    expect(repo.result.isLowConfidence(0, 4), isFalse);
  });

  testWidgets('Solution page renders solved grid', (tester) async {
    final repo = SudokuRepository();
    addTearDown(repo.dispose);
    repo.loadSample(state: RecognitionStatus.solved);
    await tester.pumpWidget(_wrap(const SolutionPage(), repo));
    await tester.pumpAndSettle();
    expect(find.text('已求解'), findsOneWidget);
    expect(find.text('解答'), findsOneWidget);
    expect(repo.result.solution, isNotNull);
  });

  testWidgets('Solution page shows inline message for no-solution state',
      (tester) async {
    final repo = SudokuRepository();
    addTearDown(repo.dispose);
    repo.loadSample(state: RecognitionStatus.noSolution);
    await tester.pumpWidget(_wrap(const SolutionPage(), repo));
    await tester.pumpAndSettle();
    expect(find.text('找不到解'), findsOneWidget);
  });

  test('findConflicts detects row duplicates', () {
    final grid = List.generate(9, (_) => List.filled(9, 0));
    grid[0][0] = 5;
    grid[0][8] = 5;
    final conflicts = findConflicts(grid);
    expect(conflicts.contains(const CellPosition(0, 0)), isTrue);
    expect(conflicts.contains(const CellPosition(0, 8)), isTrue);
  });
}
