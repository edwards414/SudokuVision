import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;

/// Polls `<bridgeUrl>/frame.jpg` at ~[fps] Hz and displays each frame as an
/// [Image.memory]. Falls back to a placeholder builder when the bridge is
/// unreachable or no frame has arrived yet.
class LivePreview extends StatefulWidget {
  const LivePreview({
    super.key,
    required this.bridgeUrl,
    this.fps = 5.0,
    this.timeout = const Duration(seconds: 2),
    this.placeholderBuilder,
    this.errorBuilder,
  });

  final String bridgeUrl;
  final double fps;
  final Duration timeout;
  final WidgetBuilder? placeholderBuilder;
  final Widget Function(BuildContext, Object error)? errorBuilder;

  @override
  State<LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<LivePreview> {
  late http.Client _client;
  Uint8List? _bytes;
  Object? _lastError;
  Timer? _timer;
  bool _fetching = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _client = http.Client();
    _scheduleNext();
  }

  @override
  void didUpdateWidget(covariant LivePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bridgeUrl != widget.bridgeUrl ||
        oldWidget.fps != widget.fps) {
      _timer?.cancel();
      _bytes = null;
      _lastError = null;
      _scheduleNext(immediate: true);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _client.close();
    super.dispose();
  }

  void _scheduleNext({bool immediate = false}) {
    if (_disposed) return;
    final period = Duration(milliseconds: (1000 / widget.fps).round());
    _timer = Timer(immediate ? Duration.zero : period, _tick);
  }

  Future<void> _tick() async {
    if (_disposed) return;
    if (_fetching) {
      _scheduleNext();
      return;
    }
    _fetching = true;
    try {
      final base = Uri.parse(widget.bridgeUrl);
      final url = base.replace(path: _joinPath(base.path, '/frame.jpg'));
      final response = await _client
          .get(url, headers: const {'cache-control': 'no-cache'})
          .timeout(widget.timeout);
      if (_disposed) return;
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        setState(() {
          _bytes = response.bodyBytes;
          _lastError = null;
        });
      } else {
        setState(() => _lastError = 'HTTP ${response.statusCode}');
      }
    } catch (err) {
      if (!_disposed) setState(() => _lastError = err);
    } finally {
      _fetching = false;
      _scheduleNext();
    }
  }

  String _joinPath(String basePath, String suffix) {
    if (basePath.isEmpty || basePath == '/') return suffix;
    return basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1) + suffix
        : basePath + suffix;
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        gaplessPlayback: true,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    }
    if (_lastError != null && widget.errorBuilder != null) {
      return widget.errorBuilder!(context, _lastError!);
    }
    if (widget.placeholderBuilder != null) {
      return widget.placeholderBuilder!(context);
    }
    return const ColoredBox(
      color: CupertinoColors.black,
      child: Center(
        child: CupertinoActivityIndicator(color: CupertinoColors.white),
      ),
    );
  }
}
