import 'package:flutter/cupertino.dart';

import '../models/sudoku_state.dart';
import '../widgets/repository_scope.dart';
import '../widgets/status_pill.dart';

class CameraPage extends StatelessWidget {
  const CameraPage({super.key, this.onCaptured});

  /// Called after a simulated capture completes, so a parent can switch tabs.
  final VoidCallback? onCaptured;

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    return CupertinoPageScaffold(
      backgroundColor:
          CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: const CupertinoNavigationBar(
        middle: Text('相機'),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusRow(status: repo.result.status, source: repo.cameraSource),
              const SizedBox(height: 16),
              const Expanded(child: _PreviewFrame()),
              const SizedBox(height: 16),
              _ActionRow(
                onCaptured: () {
                  repo.loadSample(state: RecognitionStatus.needsReview);
                  onCaptured?.call();
                },
                onLoadSolved: () {
                  repo.loadSample(state: RecognitionStatus.solved);
                  onCaptured?.call();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.status, required this.source});

  final RecognitionStatus status;
  final String source;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        StatusPill(status: status),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            source,
            overflow: TextOverflow.ellipsis,
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 14,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
          ),
        ),
        Icon(
          CupertinoIcons.viewfinder,
          size: 18,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ],
    );
  }
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame();

  @override
  Widget build(BuildContext context) {
    final outline = CupertinoColors.activeBlue.resolveFrom(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.black,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _PreviewPainter()),
            Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: outline, width: 2),
                    ),
                    child: CustomPaint(painter: _BoardGridPainter(outline)),
                  ),
                ),
              ),
            ),
            const Positioned(
              left: 16,
              top: 16,
              child: _CameraBadge(
                icon: CupertinoIcons.viewfinder_circle_fill,
                label: '棋盤已偵測',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF1C1C1E), Color(0xFF2C2C2E)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BoardGridPainter extends CustomPainter {
  _BoardGridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final thin = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 0.6;
    final thick = Paint()
      ..color = color.withValues(alpha: 0.65)
      ..strokeWidth = 1.4;
    final step = size.width / 9;
    for (var i = 1; i < 9; i++) {
      final isThick = i % 3 == 0;
      final p = isThick ? thick : thin;
      canvas.drawLine(Offset(step * i, 0), Offset(step * i, size.height), p);
      canvas.drawLine(Offset(0, step * i), Offset(size.width, step * i), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CameraBadge extends StatelessWidget {
  const _CameraBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGreen.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: CupertinoColors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: CupertinoColors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.onCaptured, required this.onLoadSolved});

  final VoidCallback onCaptured;
  final VoidCallback onLoadSolved;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 14),
            color: CupertinoColors.activeBlue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            onPressed: onLoadSolved,
            child: Text(
              '載入示範',
              style: TextStyle(
                color: CupertinoColors.activeBlue.resolveFrom(context),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(vertical: 14),
            borderRadius: BorderRadius.circular(12),
            onPressed: onCaptured,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.camera, size: 18),
                SizedBox(width: 8),
                Text(
                  '辨識棋盤',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
