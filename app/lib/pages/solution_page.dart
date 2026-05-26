import 'package:flutter/cupertino.dart';

import '../models/sudoku_state.dart';
import '../widgets/repository_scope.dart';
import '../widgets/status_pill.dart';
import '../widgets/sudoku_grid.dart';

class SolutionPage extends StatelessWidget {
  const SolutionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final result = repo.result;
    return CupertinoPageScaffold(
      backgroundColor:
          CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: const CupertinoNavigationBar(middle: Text('解答')),
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
                      _headline(result.status),
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
              if (result.solution != null)
                SudokuGrid(result: result, mode: SudokuGridMode.solution)
              else
                _EmptyState(status: result.status, message: result.message),
              const SizedBox(height: 16),
              const _Legend(),
            ],
          ),
        ),
      ),
    );
  }

  String _headline(RecognitionStatus status) {
    return switch (status) {
      RecognitionStatus.solved => '已找到唯一解。',
      RecognitionStatus.needsReview => '請先在「辨識確認」完成修正。',
      RecognitionStatus.invalidPuzzle => '題目違反數獨規則，請修正衝突格子。',
      RecognitionStatus.noSolution => '目前的數字組合無解。',
      RecognitionStatus.multipleSolutions => '此題不只一組解，僅顯示其中之一。',
    };
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.status, required this.message});

  final RecognitionStatus status;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      RecognitionStatus.noSolution => (
        CupertinoIcons.question_circle,
        CupertinoColors.systemRed,
      ),
      RecognitionStatus.invalidPuzzle => (
        CupertinoIcons.xmark_octagon,
        CupertinoColors.systemRed,
      ),
      RecognitionStatus.multipleSolutions => (
        CupertinoIcons.square_stack_3d_up,
        CupertinoColors.systemOrange,
      ),
      _ => (CupertinoIcons.wand_stars, CupertinoColors.systemBlue),
    };
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.secondarySystemGroupedBackground,
          context,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: color.resolveFrom(context)),
          const SizedBox(height: 12),
          Text(
            message ?? '回到「辨識確認」分頁按下求解。',
            textAlign: TextAlign.center,
            style: CupertinoTheme.of(context)
                .textTheme
                .textStyle
                .copyWith(fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.secondarySystemGroupedBackground,
          context,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LegendRow(
            color: CupertinoColors.label,
            label: '原始題目數字',
            isBold: true,
          ),
          const SizedBox(height: 8),
          _LegendRow(
            color: CupertinoColors.systemGreen,
            label: '系統補上的答案',
            isBold: false,
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.isBold,
  });

  final Color color;
  final String label;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    final resolved = CupertinoDynamicColor.resolve(color, context);
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: resolved.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '7',
            style: TextStyle(
              fontSize: 14,
              color: resolved,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: CupertinoTheme.of(context)
              .textTheme
              .textStyle
              .copyWith(fontSize: 14),
        ),
      ],
    );
  }
}
