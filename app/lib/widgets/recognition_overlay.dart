import 'package:flutter/cupertino.dart';

import '../models/sudoku_state.dart';

/// Draws the recognised digits + solved answers on top of the live camera
/// preview. Uses the board corners returned by the backend to project the
/// 9×9 grid back onto the source-image space, then maps that into the
/// widget's letterboxed `BoxFit.contain` rect.
class RecognitionOverlay extends StatelessWidget {
  const RecognitionOverlay({
    super.key,
    required this.result,
    required this.boardCorners,
    required this.sourceSize,
  });

  final RecognitionResult result;
  final List<List<double>> boardCorners;
  final Size sourceSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: constraints.biggest,
          painter: _OverlayPainter(
            result: result,
            corners: boardCorners,
            sourceSize: sourceSize,
            givenColor: CupertinoColors.label.resolveFrom(context),
            filledColor:
                CupertinoColors.systemGreen.resolveFrom(context),
            conflictColor:
                CupertinoColors.systemRed.resolveFrom(context),
            lowConfidenceColor:
                CupertinoColors.systemOrange.resolveFrom(context),
            outlineColor:
                CupertinoColors.systemGreen.resolveFrom(context),
          ),
        );
      },
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.result,
    required this.corners,
    required this.sourceSize,
    required this.givenColor,
    required this.filledColor,
    required this.conflictColor,
    required this.lowConfidenceColor,
    required this.outlineColor,
  });

  final RecognitionResult result;
  final List<List<double>> corners;
  final Size sourceSize;
  final Color givenColor;
  final Color filledColor;
  final Color conflictColor;
  final Color lowConfidenceColor;
  final Color outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4 || sourceSize.isEmpty) return;
    final fit = _fitContain(sourceSize, size);
    if (fit.isEmpty) return;

    Offset project(double x, double y) {
      return Offset(
        fit.left + (x / sourceSize.width) * fit.width,
        fit.top + (y / sourceSize.height) * fit.height,
      );
    }

    final tl = project(corners[0][0], corners[0][1]);
    final tr = project(corners[1][0], corners[1][1]);
    final br = project(corners[2][0], corners[2][1]);
    final bl = project(corners[3][0], corners[3][1]);

    // Board outline
    final boardPath = Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy)
      ..close();
    canvas.drawPath(
      boardPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = outlineColor,
    );
    canvas.drawPath(
      boardPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = outlineColor.withValues(alpha: 0.05),
    );

    final conflicts = findConflicts(result.grid);

    Offset quadPoint(double u, double v) {
      // Bilinear interpolation across the quadrilateral defined by tl/tr/br/bl.
      final top = Offset.lerp(tl, tr, u)!;
      final bottom = Offset.lerp(bl, br, u)!;
      return Offset.lerp(top, bottom, v)!;
    }

    final solution = result.solution;
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        final centerU = (c + 0.5) / 9.0;
        final centerV = (r + 0.5) / 9.0;
        final centre = quadPoint(centerU, centerV);

        final cellTL = quadPoint(c / 9.0, r / 9.0);
        final cellBR = quadPoint((c + 1) / 9.0, (r + 1) / 9.0);
        final cellSize = (cellBR - cellTL).distance / 1.6;

        final isGiven = result.givenMask[r][c];
        final value = result.grid[r][c];
        final solutionValue = solution?[r][c] ?? 0;
        final isFilled = !isGiven && value == 0 && solutionValue != 0;
        final isLowConf = result.isLowConfidence(r, c);
        final isConflict = conflicts.contains(CellPosition(r, c));

        Color color;
        int displayValue;
        FontWeight weight;
        if (isConflict) {
          color = conflictColor;
          displayValue = value;
          weight = FontWeight.w700;
        } else if (isLowConf) {
          color = lowConfidenceColor;
          displayValue = value;
          weight = FontWeight.w700;
        } else if (value != 0) {
          color = givenColor;
          displayValue = value;
          weight = isGiven ? FontWeight.w700 : FontWeight.w500;
        } else if (isFilled) {
          color = filledColor;
          displayValue = solutionValue;
          weight = FontWeight.w500;
        } else {
          continue;
        }

        final painter = TextPainter(
          textDirection: TextDirection.ltr,
          text: TextSpan(
            text: '$displayValue',
            style: TextStyle(
              color: color,
              fontSize: cellSize.clamp(10.0, 36.0),
              fontWeight: weight,
              shadows: const [
                Shadow(
                  blurRadius: 3,
                  color: Color(0xCCFFFFFF),
                  offset: Offset.zero,
                ),
              ],
            ),
          ),
        )..layout();
        painter.paint(
          canvas,
          centre - Offset(painter.width / 2, painter.height / 2),
        );
      }
    }
  }

  Rect _fitContain(Size source, Size target) {
    if (source.width <= 0 || source.height <= 0) return Rect.zero;
    final scale = target.width / source.width < target.height / source.height
        ? target.width / source.width
        : target.height / source.height;
    final w = source.width * scale;
    final h = source.height * scale;
    return Rect.fromLTWH(
      (target.width - w) / 2,
      (target.height - h) / 2,
      w,
      h,
    );
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) {
    return oldDelegate.result != result ||
        oldDelegate.corners != corners ||
        oldDelegate.sourceSize != sourceSize;
  }
}
