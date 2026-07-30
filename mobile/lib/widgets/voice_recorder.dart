import 'package:flutter/material.dart';

import '../services/audio_recorder.dart';

typedef RecordingCompleteCallback = Future<void> Function(String path);

class VoiceRecorder extends StatefulWidget {
  const VoiceRecorder({
    super.key,
    required this.recorder,
    required this.onRecordingComplete,
    this.enabled = true,
  });

  final AudioRecorderService recorder;
  final RecordingCompleteCallback onRecordingComplete;
  final bool enabled;

  @override
  State<VoiceRecorder> createState() => _VoiceRecorderState();
}

class _VoiceRecorderState extends State<VoiceRecorder> {
  bool _recording = false;
  bool _starting = false;
  bool _finishing = false;
  bool _longPressHeld = false;
  String? _error;

  Future<void> _start() async {
    if (!widget.enabled || _recording || _starting || _finishing) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await widget.recorder.start();
      if (!mounted) return;
      setState(() => _recording = true);
    } on AudioRecorderException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '无法开始录音，请重试。');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    if (!_recording || _finishing) return;
    setState(() {
      _recording = false;
      _finishing = true;
      _error = null;
    });
    try {
      final path = await widget.recorder.stop();
      if (path != null) await widget.onRecordingComplete(path);
    } on AudioRecorderException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '处理录音失败，请重试。');
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  Future<void> _toggle() => _recording ? _stop() : _start();

  Future<void> _handleLongPressStart() async {
    _longPressHeld = true;
    await _start();
    // Permission prompts may outlive the physical press. Stop immediately once
    // recording starts if the learner has already released the button.
    if (!_longPressHeld && _recording) await _stop();
  }

  Future<void> _handleLongPressEnd() async {
    _longPressHeld = false;
    if (_recording) await _stop();
  }

  @override
  Widget build(BuildContext context) {
    final label = _starting
        ? '正在启动录音…'
        : _finishing
            ? '正在转写…'
            : _recording
                ? '停止录音'
                : '开始录音';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          button: true,
          label: '语音答题，长按录音，松开后转写',
          child: GestureDetector(
            onLongPressStart: widget.enabled && !_finishing
                ? (_) => _handleLongPressStart()
                : null,
            onLongPressEnd: widget.enabled && !_finishing
                ? (_) => _handleLongPressEnd()
                : null,
            child: FilledButton.icon(
              onPressed:
                  widget.enabled && !_finishing && !_starting ? _toggle : null,
              icon: _finishing || _starting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _recording ? Icons.stop_circle_outlined : Icons.mic_none,
                    ),
              label: Text(label),
              style: _recording
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _recording ? '正在录音，松开或点击按钮结束' : '可长按按钮录音，也可点击开始/停止',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          if (_error!.contains('系统设置'))
            TextButton(
              onPressed: () {
                widget.recorder.openPermissionSettings();
              },
              child: const Text('打开系统设置'),
            ),
        ],
      ],
    );
  }
}
