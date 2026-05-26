import 'package:flutter/cupertino.dart';

import '../models/sudoku_state.dart';

enum SudokuGridMode { review, solution }

class SudokuGrid extends StatelessWidget {
  const SudokuGrid({
    super.key,
    required this.result,
    required this.mode,
    this.selected,
    this.onCellTap,
  });

  final RecognitionResult result;
  final SudokuGridMode mode;
  final CellPosition? selected;
  final ValueChanged<CellPosition>? onCellTap;

  @override
  Widget build(BuildContext context) {
    final separator = CupertinoDynamicColor.resolve(
      CupertinoColors.separator,
      context,
    );
    final heavy = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final background = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemGroupedBackground,
      context,
    );
    final conflicts = mode == SudokuGridMode.review
        ? findConflicts(result.grid)
        : const <CellPosition>{};

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth.clamp(0.0, 540.0);
        final cellSize = side / 9;
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: heavy.withValues(alpha: 0.55), width: 1.4),
              ),
              child: Column(
                children: [
                  for (var r = 0; r < 9; r++)
                    Expanded(
                      child: Row(
                        children: [
                          for (var c = 0; c < 9; c++)
                            _Cell(
                              row: r,
                              col: c,
                              size: cellSize,
                              result: result,
                              mode: mode,
                              isSelected: selected != null &&
                                  selected!.row == r &&
                                  selected!.col == c,
                              isConflict: conflicts.contains(CellPosition(r, c)),
                              separator: separator,
                              heavy: heavy,
                              onTap: onCellTap == null
                                  ? null
                                  : () => onCellTap!(CellPosition(r, c)),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.row,
    required this.col,
    required this.size,
    required this.result,
    required this.mode,
    required this.isSelected,
    required this.isConflict,
    required this.separator,
    required this.heavy,
    required this.onTap,
  });

  final int row;
  final int col;
  final double size;
  final RecognitionResult result;
  final SudokuGridMode mode;
  final bool isSelected;
  final bool isConflict;
  final Color separator;
  final Color heavy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isGiven = result.givenMask[row][col];
    final value = mode == SudokuGridMode.solution
        ? (result.solution?[row][col] ?? result.grid[row][col])
        : result.grid[row][col];
    final isLow = mode == SudokuGridMode.review && result.isLowConfidence(row, col);

    final filled = mode == SudokuGridMode.solution && !isGiven && value != 0;

    Color background = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemGroupedBackground,
      context,
    );
    if (isSelected) {
      background = CupertinoDynamicColor.resolve(
        CupertinoColors.activeBlue,
        context,
      ).withValues(alpha: 0.18);
    } else if (isConflict) {
      background = CupertinoDynamicColor.resolve(
        CupertinoColors.systemRed,
        context,
      ).withValues(alpha: 0.16);
    } else if (isLow) {
      background = CupertinoDynamicColor.resolve(
        CupertinoColors.systemOrange,
        context,
      ).withValues(alpha: 0.14);
    } else if (filled) {
      background = CupertinoDynamicColor.resolve(
        CupertinoColors.systemGreen,
        context,
      ).withValues(alpha: 0.08);
    }

    final textColor = filled
        ? CupertinoDynamicColor.resolve(CupertinoColors.systemGreen, context)
        : isConflict
            ? CupertinoDynamicColor.resolve(CupertinoColors.systemRed, context)
            : heavy;
    final fontWeight =
        isGiven ? FontWeight.w700 : (filled ? FontWeight.w500 : FontWeight.w500);

    final rightHeavy = col == 2 || col == 5;
    final bottomHeavy = row == 2 || row == 5;
    final border = Border(
      right: BorderSide(
        color: rightHeavy ? heavy.withValues(alpha: 0.7) : separator,
        width: rightHeavy ? 1.2 : 0.5,
      ),
      bottom: BorderSide(
        color: bottomHeavy ? heavy.withValues(alpha: 0.7) : separator,
        width: bottomHeavy ? 1.2 : 0.5,
      ),
    );

    final semantics = _semanticLabel(value: value, isGiven: isGiven, isLow: isLow);
    final cell = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, border: border),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            value == 0 ? '' : '$value',
            style: TextStyle(
              fontSize: size * 0.46,
              fontWeight: fontWeight,
              color: textColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (isLow)
            Positioned(
              top: 3,
              right: 3,
              child: Icon(
                CupertinoIcons.exclamationmark_circle_fill,
                size: size * 0.22,
                color: CupertinoColors.systemOrange.resolveFrom(context),
                semanticLabel: '低信心',
              ),
            ),
        ],
      ),
    );

    return Expanded(
      child: Semantics(
        button: onTap != null,
        label: semantics,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: cell,
        ),
      ),
    );
  }

  String _semanticLabel({
    required int value,
    required bool isGiven,
    required bool isLow,
  }) {
    final v = value == 0 ? 'empty' : 'value $value';
    final origin = isGiven ? 'given' : 'edited';
    final confidence = isLow ? ', low confidence' : '';
    return 'Row ${row + 1} Column ${col + 1}, $v, $origin$confidence';
  }
}
