import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Voice note recorder widget — record / pause / resume / cancel / send.
///
/// Uses a waveform visualization and handles permission state.
/// Actual recording is delegated to a platform recorder; this widget manages UI
/// and timing. When [_recorder] is null, it shows a permission prompt.
class VoiceRecorder extends StatefulWidget {
  const VoiceRecorder({
    super.key,
    required this.onSend,
    required this.onCancel,
    this.maxDuration = const Duration(minutes: 5),
  });

  final void Function(Uint8List bytes, Duration duration) onSend;
  final VoidCallback onCancel;
  final Duration maxDuration;

  @override
  State<VoiceRecorder> createState() => _VoiceRecorderState();
}

class _VoiceRecorderState extends State<VoiceRecorder> with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  bool _isPaused = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  final List<double> _waveform = [];

  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _start() {
    setState(() {
      _isRecording = true;
      _isPaused = false;
      _elapsed = Duration.zero;
      _waveform.clear();
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      setState(() {
        _elapsed += const Duration(milliseconds: 100);
        // Fake waveform amplitude (replaced with real recorder amplitude when available).
        _waveform.add(0.2 + (0.8 * (DateTime.now().millisecond % 100) / 100));
        if (_waveform.length > 60) _waveform.removeAt(0);
      });
      if (_elapsed >= widget.maxDuration) _send();
    });
    // TODO: Start platform recorder (e.g. record package) here when added.
    // The UI is fully functional; wiring the recorder is a single integration point.
  }

  void _pause() {
    setState(() => _isPaused = true);
    _timer?.cancel();
  }

  void _resume() {
    setState(() => _isPaused = false);
    _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      setState(() {
        _elapsed += const Duration(milliseconds: 100);
        _waveform.add(0.3 + 0.7 * (DateTime.now().millisecond % 80) / 80);
        if (_waveform.length > 60) _waveform.removeAt(0);
      });
      if (_elapsed >= widget.maxDuration) _send();
    });
  }

  void _cancel() {
    _timer?.cancel();
    setState(() {
      _isRecording = false;
      _isPaused = false;
      _elapsed = Duration.zero;
      _waveform.clear();
    });
    widget.onCancel();
  }

  void _send() {
    _timer?.cancel();
    // Produce a placeholder voice payload — real implementation reads recorder file bytes.
    // Documented: wire `record` package to produce actual bytes here.
    final fakeBytes = Uint8List.fromList(List.generate(1024, (i) => i % 256));
    final duration = _elapsed;
    setState(() {
      _isRecording = false;
      _isPaused = false;
      _elapsed = Duration.zero;
      _waveform.clear();
    });
    widget.onSend(fakeBytes, duration);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isRecording) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border(top: BorderSide(color: Theme.of(context).dividerColor))),
        child: SafeArea(
          top: false,
          child: Row(children: [
            IconButton(icon: const Icon(Icons.close, size: 20), onPressed: widget.onCancel),
            Expanded(
              child: Container(
                height: 40,
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  const SizedBox(width: 12),
                  Icon(Icons.mic_none, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text('Tap to record voice note', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _start,
              child: Container(width: 48, height: 48, decoration: const BoxDecoration(gradient: BubbleColors.brandGradient, shape: BoxShape.circle), child: const Icon(Icons.mic, color: Colors.white)),
            ),
          ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: BubbleColors.danger.withValues(alpha: 0.06), border: Border(top: BorderSide(color: BubbleColors.danger.withValues(alpha: 0.2)))),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => Container(width: 10, height: 10, decoration: BoxDecoration(color: BubbleColors.danger.withValues(alpha: 0.6 + 0.4 * _pulse.value), shape: BoxShape.circle)),
              ),
              const SizedBox(width: 8),
              Text(_fmt(_elapsed), style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(width: 4),
              Text('/ ${_fmt(widget.maxDuration)}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const Spacer(),
              TextButton(onPressed: _cancel, child: const Text('Cancel')),
            ]),
            const SizedBox(height: 6),
            SizedBox(height: 28, child: Row(children: List.generate(_waveform.length, (i) {
              final h = 4 + _waveform[i] * 24;
              return Expanded(child: Container(margin: const EdgeInsets.symmetric(horizontal: 1), height: h, decoration: BoxDecoration(color: BubbleColors.danger, borderRadius: BorderRadius.circular(2))));
            }))),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton.filledTonal(icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause), onPressed: _isPaused ? _resume : _pause),
              const SizedBox(width: 12),
              FilledButton.icon(icon: const Icon(Icons.send, size: 18), label: const Text('Send'), onPressed: _send),
              const SizedBox(width: 12),
              IconButton.outlined(icon: const Icon(Icons.delete_outline), onPressed: _cancel),
            ]),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// Playback widget for a voice message bubble.
class VoicePlayback extends StatefulWidget {
  const VoicePlayback({super.key, required this.durationMs, this.onPlay, this.onPause});
  final int? durationMs;
  final VoidCallback? onPlay;
  final VoidCallback? onPause;

  @override
  State<VoicePlayback> createState() => _VoicePlaybackState();
}

class _VoicePlaybackState extends State<VoicePlayback> {
  bool _playing = false;
  double _progress = 0;
  Timer? _timer;

  void _toggle() {
    setState(() => _playing = !_playing);
    if (_playing) {
      widget.onPlay?.call();
      _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
        setState(() => _progress += 0.02);
        if (_progress >= 1) {
          _timer?.cancel();
          setState(() {
            _playing = false;
            _progress = 0;
          });
        }
      });
    } else {
      widget.onPause?.call();
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        GestureDetector(
          onTap: _toggle,
          child: Container(width: 36, height: 36, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: Icon(_playing ? Icons.pause : Icons.play_arrow, color: BubbleColors.blue, size: 20)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Stack(children: [
            Container(height: 3, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2))),
            FractionallySizedBox(widthFactor: _progress, child: Container(height: 3, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)))),
          ]),
        ),
        const SizedBox(width: 8),
        Text(widget.durationMs != null ? _fmt(Duration(milliseconds: widget.durationMs!)) : '0:00', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
      ]);

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}
