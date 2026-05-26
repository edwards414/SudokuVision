import 'package:flutter/cupertino.dart';

class NumberPad extends StatelessWidget {
  const NumberPad({
    super.key,
    required this.onSelect,
    required this.onClear,
  });

  final ValueChanged<int> onSelect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final divider = CupertinoDynamicColor.resolve(
      CupertinoColors.separator,
      context,
    );
    return Container(
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.secondarySystemGroupedBackground,
          context,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: divider, width: 0.5),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in const [
            [1, 2, 3],
            [4, 5, 6],
            [7, 8, 9],
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  for (final v in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _PadButton(
                          key: ValueKey('numpad-$v'),
                          label: '$v',
                          onPressed: () => onSelect(v),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  color: CupertinoColors.systemRed.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  onPressed: onClear,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.clear,
                        size: 18,
                        color: CupertinoColors.systemRed.resolveFrom(context),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '清空',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color:
                              CupertinoColors.systemRed.resolveFrom(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 14),
      color: CupertinoColors.activeBlue.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: CupertinoColors.activeBlue.resolveFrom(context),
        ),
      ),
    );
  }
}
