import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

enum AudioRecorderFailure {
  permissionDenied,
  permissionPermanentlyDenied,
  recording,
}

class AudioRecorderException implements Exception {
  const AudioRecorderException(this.failure, this.message);

  final AudioRecorderFailure failure;
  final String message;

  @override
  String toString() => message;
}

class AudioRecorderService {
  AudioRecorderService({
    AudioRecorder? recorder,
    Future<Directory> Function()? temporaryDirectoryProvider,
  })  : _recorder = recorder,
        _temporaryDirectoryProvider =
            temporaryDirectoryProvider ?? getTemporaryDirectory;

  AudioRecorder? _recorder;
  final Future<Directory> Function() _temporaryDirectoryProvider;

  AudioRecorder get _audioRecorder => _recorder ??= AudioRecorder();

  String? _activePath;

  bool get isRecording => _activePath != null;

  Future<String> start() async {
    if (isRecording) return _activePath!;

    var permission = await Permission.microphone.status;
    if (!permission.isGranted) {
      permission = await Permission.microphone.request();
    }
    if (permission.isPermanentlyDenied) {
      throw const AudioRecorderException(
        AudioRecorderFailure.permissionPermanentlyDenied,
        '麦克风权限已被永久拒绝，请在系统设置中允许 DeepTutor 使用麦克风。',
      );
    }
    if (!permission.isGranted || !await _audioRecorder.hasPermission()) {
      throw const AudioRecorderException(
        AudioRecorderFailure.permissionDenied,
        '需要麦克风权限才能录入语音答案。',
      );
    }

    final directory = await _temporaryDirectoryProvider();
    await directory.create(recursive: true);
    final path = '${directory.path}${Platform.pathSeparator}'
        'deeptutor-answer-${DateTime.now().microsecondsSinceEpoch}.m4a';
    try {
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 24000,
          numChannels: 1,
        ),
        path: path,
      );
      _activePath = path;
      return path;
    } catch (_) {
      throw const AudioRecorderException(
        AudioRecorderFailure.recording,
        '无法开始 AAC/M4A 录音。请确认设备编码器可用；若服务器 STT 不支持 M4A，需改用 WAV/PCM 并同步检查 provider 配置。',
      );
    }
  }

  Future<String?> stop() async {
    if (!isRecording) return null;
    try {
      final path = await _audioRecorder.stop();
      return path ?? _activePath;
    } catch (_) {
      throw const AudioRecorderException(
        AudioRecorderFailure.recording,
        '停止录音失败，请重新录制。若 AAC/M4A 持续失败，请检查设备编码器或切换 WAV/PCM。',
      );
    } finally {
      _activePath = null;
    }
  }

  Future<void> cancel() async {
    if (!isRecording) return;
    try {
      await _audioRecorder.cancel();
    } finally {
      _activePath = null;
    }
  }

  Future<void> removeTemporaryRecording(String path) async {
    try {
      final directory = (await _temporaryDirectoryProvider()).absolute;
      final file = File(path).absolute;
      final name = file.uri.pathSegments.last;
      final isOwnedRecording = file.parent.path == directory.path &&
          name.startsWith('deeptutor-answer-') &&
          name.endsWith('.m4a');
      if (isOwnedRecording && await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Cache cleanup is best-effort and must not hide a successful transcript.
    }
  }

  Future<bool> openPermissionSettings() => openAppSettings();

  Future<void> dispose() async {
    await cancel();
    await _recorder?.dispose();
  }
}
