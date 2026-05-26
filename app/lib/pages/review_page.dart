import 'package:flutter/cupertino.dart';

import '../models/sudoku_state.dart';
import '../widgets/number_pad.dart';
import '../widgets/repository_scope.dart';
import '../widgets/status_pill.dart';
import '../widgets/sudoku_grid.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, this.onSolved});

  final VoidCallback? onSolved;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  CellPosition? _selected;

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final result = repo.result;
    final conflicts = findConflicts(result.grid);
    final canSolve = conflicts.isEmpty;
    final low = result.lowConfidenceCells;

    return CupertinoPageScaffold(
      backgroundColor:
          CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: const CupertinoNavigationBar(middle: Text('辨識確認')),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  StatusPill(status: result.status),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _summary(result: result, conflicts: conflicts.length),
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .textStyle
                          .copyWith(
                            fontSize: 14,
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context),
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SudokuGrid(
                result: result,
                mode: SudokuGridMode.review,
                selected: _selected,
                onCellTap: (pos) => setState(() => _selected = pos),
              ),
              const SizedBox(height: 16),
              if (low.isNotEmpty) _LowConfidenceList(
                low: low,
                onSelect: (pos) => setState(() => _selected = pos),
              ),
              const SizedBox(height: 16),
              _Editor(
                selected: _selected,
                onPick: (v) {
                  final pos = _selected;
                  if (pos == null) return;
                  repo.setCell(pos.row, pos.col, v);
                },
                onClear: () {
                  final pos = _selected;
                  if (pos == null) return;
                  repo.setCell(pos.row, pos.col, 0);
                },
              ),
              const SizedBox(height: 16),
              CupertinoButton.filled(
                padding: const EdgeInsets.symmetric(vertical: 14),
                borderRadius: BorderRadius.circular(12),
                onPressed: canSolve
                    ? () async {
                        await repo.solve();
                        if (!mounted) return;
                        widget.onSolved?.call();
                      }
                    : null,
                child: const Text(
                  '求解',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _summary({required RecognitionResult result, required int conflicts}) {
    if (conflicts > 0) return '$conflicts 格衝突，請修正後再求解。';
    final low = result.lowConfidenceCells.length;
    if (low > 0) return '$low 格低信心，請確認後再求解。';
    return '辨識完成，準備求解。';
  }
}

class _LowConfidenceList extends StatelessWidget {
  const _LowConfidenceList({required this.low, required this.onSelect});

  final List<LowConfidenceCell> low;
  final ValueChanged<CellPosition> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.secondarySystemGroupedBackground,
          context,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < low.length; i++) ...[
            _LowConfidenceTile(
              cell: low[i],
              onTap: () => onSelect(CellPosition(low[i].row, low[i].col)),
            ),
            if (i != low.length - 1)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                height: 0.5,
                color:
                    CupertinoColors.separator.resolveFrom(context),
              ),
          ],
        ],
      ),
    );
  }
}

class _LowConfidenceTile extends StatelessWidget {
  const _LowConfidenceTile({required this.cell, required this.onTap});

  final LowConfidenceCell cell;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final orange = CupertinoColors.systemOrange.resolveFrom(context);
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      onPressed: onTap,
      child: Row(
        children: [
          Icon(CupertinoIcons.exclamationmark_circle_fill,
              size: 18, color: orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '列 ${cell.row + 1}，欄 ${cell.col + 1}　預測 ${cell.predicted}',
              style: CupertinoTheme.of(context)
                  .textTheme
                  .textStyle
                  .copyWith(fontSize: 15),
            ),
          ),
          Text(
            '${(cell.confidence * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: orange,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 6),
          Icon(CupertinoIcons.chevron_right,
              size: 14,
              color: CupertinoColors.tertiaryLabel.resolveFrom(context)),
        ],
      ),
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor({
    required this.selected,
    required this.onPick,
    required this.onClear,
  });

  final CellPosition? selected;
  final ValueChanged<int> onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (selected == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
            CupertinoColors.secondarySystemGroupedBackground,
            context,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.hand_point_right,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '點選棋盤格子以修改數字。',
                style: CupertinoTheme.of(context)
                    .textTheme
                    .textStyle
                    .copyWith(
                      fontSize: 14,
                      color: CupertinoColors.secondaryLabel
                          .resolveFrom(context),
                    ),
              ),
            ),
          ],
        ),
      );
    }
    final pos = selected!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '修改 列 ${pos.row + 1}，欄 ${pos.col + 1}',
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        NumberPad(onSelect: onPick, onClear: onClear),
      ],
    );
  }
}
