// Run with: flutter test test/screenshot_capture.dart
// Renders the Cupertino UI off-screen and writes PNGs to ../docs/screenshots/.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sudoku_vision_app/data/sudoku_repository.dart';
import 'package:sudoku_vision_app/models/sudoku_state.dart';
import 'package:sudoku_vision_app/pages/camera_page.dart';
import 'package:sudoku_vision_app/pages/review_page.dart';
import 'package:sudoku_vision_app/pages/solution_page.dart';
import 'package:sudoku_vision_app/widgets/repository_scope.dart';

const _fallbackFamily = 'ScreenshotFallback';
bool _fontLoaded = false;

Future<void> _ensureFont(WidgetTester tester) async {
  if (_fontLoaded) return;
  await tester.runAsync(() async {
    const candidates = [
      '/System/Library/Fonts/PingFang.ttc',
      '/System/Library/Fonts/STHeiti Light.ttc',
      '/System/Library/Fonts/Hiragino Sans GB.ttc',
    ];
    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final loader = FontLoader(_fallbackFamily)
          ..addFont(Future.value(ByteData.view(bytes.buffer)));
        await loader.load();
        _fontLoaded = true;
        return;
      }
    }
  });
}

void main() {
  testWidgets('capture review screenshot', (tester) async {
    await _capture(tester, 'review.png', (repo) => const ReviewPage());
  });

  testWidgets('capture camera screenshot', (tester) async {
    await _capture(tester, 'camera.png', (repo) => const CameraPage());
  });

  testWidgets('capture solution screenshot', (tester) async {
    await _capture(
      tester,
      'solution.png',
      (repo) {
        repo.loadSample(state: RecognitionStatus.solved);
        return const SolutionPage();
      },
    );
  });
}

typedef _Builder = Widget Function(SudokuRepository repo);

Future<void> _capture(
  WidgetTester tester,
  String filename,
  _Builder builder,
) async {
  await _ensureFont(tester);
  const size = Size(420, 860);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repo = SudokuRepository();
  addTearDown(repo.dispose);
  final key = GlobalKey();

  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: _fallbackFamily,
          color: CupertinoColors.black,
        ),
        child: CupertinoApp(
          debugShowCheckedModeBanner: false,
          theme: const CupertinoThemeData(
            brightness: Brightness.light,
            primaryColor: CupertinoColors.activeBlue,
            textTheme: CupertinoTextThemeData(
              textStyle: TextStyle(
                fontFamily: _fallbackFamily,
                fontSize: 16,
                color: CupertinoColors.label,
              ),
              actionTextStyle: TextStyle(
                fontFamily: _fallbackFamily,
                fontSize: 16,
                color: CupertinoColors.activeBlue,
              ),
              navTitleTextStyle: TextStyle(
                fontFamily: _fallbackFamily,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.label,
              ),
              navLargeTitleTextStyle: TextStyle(
                fontFamily: _fallbackFamily,
                fontSize: 34,
                fontWeight: FontWeight.w700,
                color: CupertinoColors.label,
              ),
              navActionTextStyle: TextStyle(
                fontFamily: _fallbackFamily,
                fontSize: 16,
                color: CupertinoColors.activeBlue,
              ),
              tabLabelTextStyle: TextStyle(
                fontFamily: _fallbackFamily,
                fontSize: 10,
              ),
              pickerTextStyle: TextStyle(
                fontFamily: _fallbackFamily,
                fontSize: 21,
              ),
              dateTimePickerTextStyle: TextStyle(
                fontFamily: _fallbackFamily,
                fontSize: 21,
              ),
            ),
          ),
          home: RepositoryScope(repository: repo, child: builder(repo)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
    final ByteData? bytes =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('../docs/screenshots/$filename');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
