import 'package:flutter/cupertino.dart';

import '../models/sudoku_state.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final RecognitionStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (status) {
      RecognitionStatus.needsReview => (
        '需要確認',
        CupertinoIcons.exclamationmark_circle,
        CupertinoColors.systemOrange,
      ),
      RecognitionStatus.solved => (
        '已求解',
        CupertinoIcons.checkmark_seal,
        CupertinoColors.systemGreen,
      ),
      RecognitionStatus.invalidPuzzle => (
        '題目衝突',
        CupertinoIcons.xmark_octagon,
        CupertinoColors.systemRed,
      ),
      RecognitionStatus.noSolution => (
        '找不到解',
        CupertinoIcons.question_circle,
        CupertinoColors.systemRed,
      ),
      RecognitionStatus.multipleSolutions => (
        '多解',
        CupertinoIcons.square_stack_3d_up,
        CupertinoColors.systemOrange,
      ),
    };
    final resolved = CupertinoDynamicColor.resolve(color, context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: resolved.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: resolved),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: resolved,
            ),
          ),
        ],
      ),
    );
  }
}
