import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:deeptutor_mobile/api/voice_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File audio;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('deeptutor-voice-test-');
    audio = File('${directory.path}/answer.m4a');
    await audio.writeAsBytes(<int>[0, 1, 2, 3]);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('uploads multipart file and language with bearer token', () async {
    RequestOptions? captured;
    final adapter = _FakeAdapter((options) {
      captured = options;
      return ResponseBody.fromString(
        '{"text":"四"}',
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        },
      );
    });
    final dio = Dio()..httpClientAdapter = adapter;
    final api = VoiceApi.fromBaseUri(
      dio: dio,
      baseUri: Uri.parse('https://example.test'),
      token: 'jwt-token',
    );

    expect(await api.transcribe(filePath: audio.path, language: 'zh'), '四');
    final request = captured!;
    expect(request.uri.path, '/api/v1/voice/stt');
    expect(request.headers['Authorization'], 'Bearer jwt-token');
    final data = request.data as FormData;
    expect(
      data.fields
          .any((entry) => entry.key == 'language' && entry.value == 'zh'),
      isTrue,
    );
    expect(data.files.single.key, 'file');
    expect(data.files.single.value.filename, 'answer.m4a');
  });

  test('maps 401 to an explicit unauthorized error', () async {
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter(
        (_) => ResponseBody.fromString('{"detail":"Unauthorized"}', 401),
      );
    final api = VoiceApi.fromBaseUri(
      dio: dio,
      baseUri: Uri.parse('https://example.test'),
      token: 'expired',
    );

    await expectLater(
      api.transcribe(filePath: audio.path),
      throwsA(
        isA<VoiceApiException>().having(
          (error) => error.failure,
          'failure',
          VoiceApiFailure.unauthorized,
        ),
      ),
    );
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}
