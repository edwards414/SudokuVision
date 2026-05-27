import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../data/sudoku_repository.dart';
import '../models/sudoku_state.dart';
import '../widgets/live_preview.dart';
import '../widgets/recognition_overlay.dart';
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
  bool _liveOverlay = false;
  Timer? _liveTimer;

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  void _toggleLive(SudokuRepository repo) {
    setState(() => _liveOverlay = !_liveOverlay);
    if (_liveOverlay) {
      _liveTimer?.cancel();
      _runLivePoll(repo);
      _liveTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _runLivePoll(repo),
      );
    } else {
      _liveTimer?.cancel();
      repo.clearLiveOverlay();
    }
  }

  Future<void> _runLivePoll(SudokuRepository repo) async {
    if (!mounted || repo.apiClient == null) return;
    await repo.refreshLiveOverlay();
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    return CupertinoPageScaffold(
      backgroundColor:
          CupertinoColors.systemGroupedBackground.resolveFrom(context),
      navigationBar: CupertinoNavigationBar(
        middle: const Text('相機'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (repo.apiClient != null)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _toggleLive(repo),
                child: Text(
                  _liveOverlay ? '停止辨識' : '即時辨識',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _toggleManual,
              child: Text(
                _manualMode ? '自動' : '手動標角',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
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
                bridgeUrl: repo.bridgeUrl,
                manual: _manualMode,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _PreviewFrame(
                  bridgeUrl: repo.bridgeUrl,
                  corners: _corners,
                  manual: _manualMode,
                  overlayResult:
                      _liveOverlay ? repo.liveOverlay : null,
                  overlayCorners:
                      _liveOverlay ? repo.liveBoardCorners : null,
                  overlaySourceSize: _liveOverlay &&
                          repo.liveSourceWidth != null &&
                          repo.liveSourceHeight != null
                      ? Size(repo.liveSourceWidth!, repo.liveSourceHeight!)
                      : null,
                  onCornersChanged: (next) =>
                      setState(() => _corners = next),
                ),
              ),
              const SizedBox(height: 16),
              _ActionRow(
                busy: repo.busy,
                hasBackend: repo.apiClient != null,
                onCaptured: () async {
                  List<List<double>>? corners;
                  if (_manualMode) {
                    corners = [for (final o in _corners) [o.dx, o.dy]];
                    repo.setManualCorners(corners);
                  } else {
                    repo.setManualCorners(null);
                  }
                  final wentToBackend = await repo.captureViaBackend(
                    corners: corners,
                  );
                  if (!context.mounted) return;
                  if (!wentToBackend && repo.apiClient != null) {
                    // API configured but call failed — surface the error.
                    await showCupertinoDialog<void>(
                      context: context,
                      builder: (dialog) => CupertinoAlertDialog(
                        title: const Text('辨識失敗'),
                        content: Text(
                          repo.lastError ?? '無法從後端取得結果',
                        ),
                        actions: [
                          CupertinoDialogAction(
                            isDefaultAction: true,
                            onPressed: () => Navigator.of(dialog).pop(),
                            child: const Text('好'),
                          ),
                        ],
                      ),
                    );
                    return;
                  }
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
    required this.bridgeUrl,
    required this.manual,
  });

  final RecognitionStatus status;
  final String bridgeUrl;
  final bool manual;

  @override
  Widget build(BuildContext context) {
    final hostPort = _hostPort(bridgeUrl);
    return Row(
      children: [
        StatusPill(status: status),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            hostPort,
            overflow: TextOverflow.ellipsis,
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 14,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  fontFeatures: const [FontFeature.tabularFigures()],
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

String _hostPort(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasAuthority) return url;
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.host}$port';
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({
    required this.bridgeUrl,
    required this.corners,
    required this.manual,
    required this.onCornersChanged,
    this.overlayResult,
    this.overlayCorners,
    this.overlaySourceSize,
  });

  final String bridgeUrl;
  final List<Offset> corners;
  final bool manual;
  final ValueChanged<List<Offset>> onCornersChanged;
  final RecognitionResult? overlayResult;
  final List<List<double>>? overlayCorners;
  final Size? overlaySourceSize;

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
                LivePreview(
                  bridgeUrl: bridgeUrl,
                  placeholderBuilder: (_) =>
                      CustomPaint(painter: _PreviewPainter()),
                  errorBuilder: (_, _) =>
                      CustomPaint(painter: _PreviewPainter()),
                ),
                if (overlayResult != null &&
                    overlayCorners != null &&
                    overlaySourceSize != null)
                  RecognitionOverlay(
                    result: overlayResult!,
                    boardCorners: overlayCorners!,
                    sourceSize: overlaySourceSize!,
                  ),
                CustomPaint(
                  painter: _BoardOverlayPainter(
                    color: outline,
                    corners: corners,
                    showGrid: !manual,
                  ),
                ),
                // Auto-detect overlay is now a thin guide rectangle over the
                // live frame so the user can frame the board.
                if (!manual)
                  Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: outline.withValues(alpha: 0.65),
                              width: 2,
                            ),
                          ),
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
    required this.hasBackend,
    required this.onCaptured,
    required this.onLoadSolved,
  });

  final bool busy;
  final bool hasBackend;
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
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          hasBackend
                              ? CupertinoIcons.cloud_download
                              : CupertinoIcons.camera,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          hasBackend ? '從後端抓 frame' : '辨識（離線）',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
