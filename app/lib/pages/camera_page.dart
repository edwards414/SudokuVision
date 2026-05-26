import 'package:flutter/cupertino.dart';

import '../models/sudoku_state.dart';
import '../widgets/repository_scope.dart';
import '../widgets/status_pill.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key, this.onCaptured});

  final VoidCallback? onCaptured;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  /// Default corners hug the preview frame.
  List<Offset> _corners = const [
    Offset(0.1, 0.18),
    Offset(0.9, 0.18),
    Offset(0.9, 0.82),
    Offset(0.1, 0.82),
  ];
  bool _manualMode = false;

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    return CupertinoPageScaffold(
      backgroundColor:
          CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('相機'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _toggleManual,
          child: Text(
            _manualMode ? '自動' : '手動標角',
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusRow(
                status: repo.result.status,
                source: repo.cameraSource,
                manual: _manualMode,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _PreviewFrame(
                  corners: _corners,
                  manual: _manualMode,
                  onCornersChanged: (next) =>
                      setState(() => _corners = next),
                ),
              ),
              const SizedBox(height: 16),
              _ActionRow(
                busy: repo.busy,
                onCaptured: () async {
                  if (_manualMode) {
                    repo.setManualCorners([
                      for (final o in _corners) [o.dx, o.dy],
                    ]);
                  } else {
                    repo.setManualCorners(null);
                  }
                  repo.loadSample(state: RecognitionStatus.needsReview);
                  widget.onCaptured?.call();
                },
                onLoadSolved: () {
                  repo.setManualCorners(null);
                  repo.loadSample(state: RecognitionStatus.solved);
                  widget.onCaptured?.call();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleManual() {
    setState(() => _manualMode = !_manualMode);
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.status,
    required this.source,
    required this.manual,
  });

  final RecognitionStatus status;
  final String source;
  final bool manual;

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
        if (manual)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: CupertinoColors.activeBlue
                  .resolveFrom(context)
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '手動標角',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.activeBlue.resolveFrom(context),
              ),
            ),
          )
        else
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
  const _PreviewFrame({
    required this.corners,
    required this.manual,
    required this.onCornersChanged,
  });

  final List<Offset> corners;
  final bool manual;
  final ValueChanged<List<Offset>> onCornersChanged;

  @override
  Widget build(BuildContext context) {
    final outline = CupertinoColors.activeBlue.resolveFrom(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: CupertinoColors.black,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _PreviewPainter()),
                CustomPaint(
                  painter: _BoardOverlayPainter(
                    color: outline,
                    corners: corners,
                    showGrid: !manual,
                  ),
                ),
                if (!manual)
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
                if (manual)
                  for (var i = 0; i < corners.length; i++)
                    _CornerHandle(
                      offset: corners[i],
                      size: constraints.biggest,
                      color: outline,
                      onChanged: (next) {
                        final updated = List<Offset>.from(corners);
                        updated[i] = next;
                        onCornersChanged(updated);
                      },
                    ),
                Positioned(
                  left: 16,
                  top: 16,
                  child: _CameraBadge(
                    icon: manual
                        ? CupertinoIcons.scope
                        : CupertinoIcons.viewfinder_circle_fill,
                    label: manual ? '請拖曳四角對齊棋盤' : '棋盤已偵測',
                    color: manual
                        ? CupertinoColors.activeBlue
                        : CupertinoColors.systemGreen,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CornerHandle extends StatelessWidget {
  const _CornerHandle({
    required this.offset,
    required this.size,
    required this.color,
    required this.onChanged,
  });

  final Offset offset;
  final Size size;
  final Color color;
  final ValueChanged<Offset> onChanged;

  @override
  Widget build(BuildContext context) {
    const handleSize = 28.0;
    final x = offset.dx * size.width - handleSize / 2;
    final y = offset.dy * size.height - handleSize / 2;
    return Positioned(
      left: x,
      top: y,
      width: handleSize,
      height: handleSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          final next = Offset(
            ((offset.dx * size.width) + details.delta.dx)
                    .clamp(0.0, size.width) /
                size.width,
            ((offset.dy * size.height) + details.delta.dy)
                    .clamp(0.0, size.height) /
                size.height,
          );
          onChanged(next);
        },
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.32),
            border: Border.all(color: color, width: 2),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
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

class _BoardOverlayPainter extends CustomPainter {
  _BoardOverlayPainter({
    required this.color,
    required this.corners,
    required this.showGrid,
  });

  final Color color;
  final List<Offset> corners;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    if (showGrid || corners.length != 4) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color;
    final points = [
      for (final c in corners) Offset(c.dx * size.width, c.dy * size.height),
    ];
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(path, paint);

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.08);
    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(covariant _BoardOverlayPainter oldDelegate) =>
      oldDelegate.corners != corners || oldDelegate.showGrid != showGrid;
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
  const _CameraBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final resolved = CupertinoDynamicColor.resolve(color, context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: resolved.withValues(alpha: 0.85),
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
  const _ActionRow({
    required this.busy,
    required this.onCaptured,
    required this.onLoadSolved,
  });

  final bool busy;
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
            onPressed: busy ? null : onLoadSolved,
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
            onPressed: busy ? null : onCaptured,
            child: busy
                ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.camera, size: 18),
                      SizedBox(width: 8),
                      Text(
                        '辨識棋盤',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
