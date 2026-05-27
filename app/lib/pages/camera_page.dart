import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../data/sudoku_repository.dart';
import '../models/sudoku_state.dart';
import '../widgets/live_preview.dart';
import '../widgets/recognition_overlay.dart';
import '../widgets/repository_scope.dart';
import '../widgets/status_pill.dart';
import '../widgets/sudoku_grid.dart';

enum _CameraResultMode { recognition, solution }

class CameraPage extends StatefulWidget {
  const CameraPage({super.key, this.onCaptured});

  final VoidCallback? onCaptured;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  /// Default corners hug the preview frame.
  List<Offset> _corners = const [
    Offset(0.18, 0.08),
    Offset(0.82, 0.08),
    Offset(0.82, 0.92),
    Offset(0.18, 0.92),
  ];
  bool _manualMode = false;
  bool _liveOverlay = false;
  _CameraResultMode _resultMode = _CameraResultMode.solution;
  Timer? _liveTimer;
  Timer? _cornerDebounce;

  @override
  void dispose() {
    _liveTimer?.cancel();
    _cornerDebounce?.cancel();
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
    final ok = await repo.refreshLiveOverlay(
      corners: _manualMode ? _cornersForBackend() : null,
      fallbackCorners: _manualMode ? null : _cornersForBackend(),
      commitResult: true,
    );
    if (ok && mounted && repo.result.solution != null) {
      setState(() => _resultMode = _CameraResultMode.solution);
    }
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
              _NavIconButton(
                label: _liveOverlay ? '停止辨識' : '即時辨識',
                icon: _liveOverlay
                    ? CupertinoIcons.pause_circle
                    : CupertinoIcons.play_circle,
                onPressed: () => _toggleLive(repo),
              ),
            _NavIconButton(
              label: _manualMode ? '自動標角' : '手動標角',
              icon:
                  _manualMode ? CupertinoIcons.viewfinder : CupertinoIcons.scope,
              onPressed: _toggleManual,
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 860;
              final overlaySourceSize = repo.liveSourceWidth != null &&
                      repo.liveSourceHeight != null
                  ? Size(repo.liveSourceWidth!, repo.liveSourceHeight!)
                  : null;
              final hasBoardFrame =
                  repo.liveBoardCorners != null && overlaySourceSize != null;
              final preview = _PreviewFrame(
                bridgeUrl: repo.bridgeUrl,
                corners: _corners,
                manual: _manualMode,
                detectionMode: repo.boardDetectionMode,
                overlayResult: repo.liveOverlay,
                overlayCorners: repo.liveBoardCorners,
                overlaySourceSize: overlaySourceSize,
                onCornersChanged: (next) => _updateCorners(next, repo),
              );
              final status = _StatusRow(
                status: repo.result.status,
                bridgeUrl: repo.bridgeUrl,
                manual: _manualMode,
                detectionMode: repo.boardDetectionMode,
                hasBoardFrame: hasBoardFrame,
              );
              final actions = _ActionRow(
                busy: repo.busy,
                hasBackend: repo.apiClient != null,
                onCaptured: () => _capture(repo, context),
                onLoadSolved: () {
                  repo.setManualCorners(null);
                  repo.clearLiveOverlay();
                  repo.loadSample(state: RecognitionStatus.solved);
                  setState(() => _resultMode = _CameraResultMode.solution);
                },
              );
              final resultPanel = _InlineResultPanel(
                result: repo.result,
                mode: _resultMode,
                busy: repo.busy,
                onModeChanged: (mode) => setState(() => _resultMode = mode),
                onSolve: () => _solve(repo),
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          status,
                          const SizedBox(height: 16),
                          Expanded(child: preview),
                          const SizedBox(height: 16),
                          actions,
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: constraints.maxWidth * 0.38,
                      child: resultPanel,
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  status,
                  const SizedBox(height: 10),
                  Expanded(
                    flex: constraints.maxHeight < 640 ? 4 : 5,
                    child: preview,
                  ),
                  const SizedBox(height: 10),
                  actions,
                  const SizedBox(height: 10),
                  Expanded(
                    flex: 6,
                    child: resultPanel,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<List<double>> _cornersForBackend() {
    return [for (final o in _corners) [o.dx, o.dy]];
  }

  void _updateCorners(List<Offset> next, SudokuRepository repo) {
    setState(() => _corners = next);
    if (!_liveOverlay) return;
    _cornerDebounce?.cancel();
    _cornerDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _runLivePoll(repo),
    );
  }

  Future<void> _capture(SudokuRepository repo, BuildContext context) async {
    final corners = _manualMode ? _cornersForBackend() : null;
    final fallbackCorners = _manualMode ? null : _cornersForBackend();
    repo.setManualCorners(corners);
    final wentToBackend = await repo.captureViaBackend(
      corners: corners,
      fallbackCorners: fallbackCorners,
    );
    if (!context.mounted) return;
    if (!wentToBackend && repo.apiClient != null) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialog) => CupertinoAlertDialog(
          title: const Text('辨識失敗'),
          content: Text(repo.lastError ?? '無法從後端取得結果'),
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
    if (repo.result.solution != null) {
      setState(() => _resultMode = _CameraResultMode.solution);
    }
    widget.onCaptured?.call();
  }

  Future<void> _solve(SudokuRepository repo) async {
    await repo.solve();
    if (!mounted) return;
    if (repo.result.solution != null) {
      setState(() => _resultMode = _CameraResultMode.solution);
    }
  }

  void _toggleManual() {
    setState(() => _manualMode = !_manualMode);
  }
}

class _NavIconButton extends StatelessWidget {
  const _NavIconButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: CupertinoButton(
        minSize: 32,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        onPressed: onPressed,
        child: Icon(icon, size: 22),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.status,
    required this.bridgeUrl,
    required this.manual,
    required this.detectionMode,
    required this.hasBoardFrame,
  });

  final RecognitionStatus status;
  final String bridgeUrl;
  final bool manual;
  final String? detectionMode;
  final bool hasBoardFrame;

  @override
  Widget build(BuildContext context) {
    final hostPort = _hostPort(bridgeUrl);
    final frameLabel = _boardFrameLabel(detectionMode, hasBoardFrame);
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
        if (frameLabel != null)
          _SmallStatusChip(
            text: '外框：$frameLabel',
            color: CupertinoColors.systemGreen,
          )
        else if (manual)
          const _SmallStatusChip(
            text: '手動標角',
            color: CupertinoColors.activeBlue,
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

class _SmallStatusChip extends StatelessWidget {
  const _SmallStatusChip({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final resolved = CupertinoDynamicColor.resolve(color, context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: resolved.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: resolved,
        ),
      ),
    );
  }
}

String _hostPort(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasAuthority) return url;
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.host}$port';
}

String? _boardFrameLabel(String? detectionMode, bool hasBoardFrame) {
  final modeLabel = _boardDetectionModeLabel(detectionMode);
  if (modeLabel != null) return modeLabel;
  return hasBoardFrame ? '已回傳' : null;
}

String? _boardDetectionModeLabel(String? mode) {
  if (mode == null || mode.isEmpty) return null;
  switch (mode) {
    case 'auto':
      return '自動';
    case 'manual_corners':
      return '手動';
    case 'fallback_corners':
      return '導引框';
    default:
      return '已回傳';
  }
}

class _InlineResultPanel extends StatelessWidget {
  const _InlineResultPanel({
    required this.result,
    required this.mode,
    required this.busy,
    required this.onModeChanged,
    required this.onSolve,
  });

  final RecognitionResult result;
  final _CameraResultMode mode;
  final bool busy;
  final ValueChanged<_CameraResultMode> onModeChanged;
  final VoidCallback onSolve;

  @override
  Widget build(BuildContext context) {
    final hasSolution = result.solution != null;
    final effectiveMode =
        hasSolution ? mode : _CameraResultMode.recognition;
    final conflicts = findConflicts(result.grid).length;
    final canSolve = conflicts == 0;
    final notices = <Widget>[
      if (result.lowConfidenceCells.isNotEmpty)
        _InlineNotice(
          icon: CupertinoIcons.exclamationmark_circle_fill,
          color: CupertinoColors.systemOrange,
          text: '${result.lowConfidenceCells.length} 格低信心',
        )
      else if (result.message != null)
        _InlineNotice(
          icon: CupertinoIcons.info_circle_fill,
          color: CupertinoColors.systemBlue,
          text: result.message!,
        ),
    ];
    final background = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemGroupedBackground,
      context,
    );

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StatusPill(status: result.status),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _headline(result, conflicts),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          const SizedBox(height: 8),
          CupertinoSlidingSegmentedControl<_CameraResultMode>(
            groupValue: effectiveMode,
            children: const {
              _CameraResultMode.recognition: Text('辨識結果'),
              _CameraResultMode.solution: Text('答案'),
            },
            onValueChanged: (next) {
              if (next != null) onModeChanged(next);
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: SudokuGrid(
                  result: result,
                  mode: effectiveMode == _CameraResultMode.solution
                      ? SudokuGridMode.solution
                      : SudokuGridMode.review,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (notices.isNotEmpty) ...[
            for (var i = 0; i < notices.length; i++) ...[
              notices[i],
              if (i != notices.length - 1) const SizedBox(height: 6),
            ],
            const SizedBox(height: 8),
          ],
          CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(vertical: 10),
            borderRadius: BorderRadius.circular(12),
            onPressed: busy || !canSolve ? null : onSolve,
            child: busy
                ? const CupertinoActivityIndicator(
                    color: CupertinoColors.white,
                  )
                : Text(
                    hasSolution ? '重新求解' : '求解',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _headline(RecognitionResult result, int conflicts) {
    if (conflicts > 0) return '$conflicts 格衝突';
    if (result.status == RecognitionStatus.solved) return '已找到唯一解。';
    if (result.solution != null) return '已產生答案，請確認辨識結果。';
    if (result.lowConfidenceCells.isNotEmpty) {
      return '${result.lowConfidenceCells.length} 格需要確認';
    }
    return switch (result.status) {
      RecognitionStatus.invalidPuzzle => '題目違反數獨規則',
      RecognitionStatus.noSolution => '目前找不到解',
      RecognitionStatus.multipleSolutions => '此題不只一組解',
      RecognitionStatus.needsReview => '等待確認',
      RecognitionStatus.solved => '已找到唯一解。',
    };
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final resolved = CupertinoDynamicColor.resolve(color, context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: resolved.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: resolved),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: CupertinoTheme.of(context)
                  .textTheme
                  .textStyle
                  .copyWith(fontSize: 13, color: resolved),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({
    required this.bridgeUrl,
    required this.corners,
    required this.manual,
    required this.detectionMode,
    required this.onCornersChanged,
    this.overlayResult,
    this.overlayCorners,
    this.overlaySourceSize,
  });

  final String bridgeUrl;
  final List<Offset> corners;
  final bool manual;
  final String? detectionMode;
  final ValueChanged<List<Offset>> onCornersChanged;
  final RecognitionResult? overlayResult;
  final List<List<double>>? overlayCorners;
  final Size? overlaySourceSize;

  @override
  Widget build(BuildContext context) {
    final outline = CupertinoColors.activeBlue.resolveFrom(context);
    final frameLabel = _boardFrameLabel(
      detectionMode,
      overlayCorners != null && overlaySourceSize != null,
    );
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
                CustomPaint(
                  painter: _BoardOverlayPainter(
                    color: outline,
                    corners: corners,
                    showGrid: false,
                  ),
                ),
                if (overlayResult != null &&
                    overlayCorners != null &&
                    overlaySourceSize != null)
                  RecognitionOverlay(
                    result: overlayResult!,
                    boardCorners: overlayCorners!,
                    sourceSize: overlaySourceSize!,
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
                    label: manual
                        ? '請拖曳四角對齊棋盤'
                        : frameLabel == null
                            ? '對齊藍框後辨識'
                            : '外框：$frameLabel',
                    color: manual
                        ? CupertinoColors.activeBlue
                        : frameLabel == null
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
                          hasBackend ? '拍照辨識' : '辨識（離線）',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
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
