import 'dart:io';

import 'package:deeptutor_mobile/services/audio_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes only DeepTutor-owned temporary M4A recordings', () async {
    final directory = await Directory.systemTemp.createTemp('deeptutor-audio-');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final owned = File('${directory.path}/deeptutor-answer-123.m4a');
    final unrelated = File('${directory.path}/keep-me.m4a');
    await owned.writeAsBytes(<int>[1, 2, 3]);
    await unrelated.writeAsBytes(<int>[4, 5, 6]);
    final service = AudioRecorderService(
      temporaryDirectoryProvider: () async => directory,
    );

    await service.removeTemporaryRecording(owned.path);
    await service.removeTemporaryRecording(unrelated.path);

    expect(await owned.exists(), isFalse);
    expect(await unrelated.exists(), isTrue);
  });
}
