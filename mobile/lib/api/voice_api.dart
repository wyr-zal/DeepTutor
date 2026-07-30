import 'dart:io';

import 'package:dio/dio.dart';

enum VoiceApiFailure { unauthorized, invalidAudio, offline, server, unknown }

class VoiceApiException implements Exception {
  const VoiceApiException(this.failure, this.message, {this.statusCode});

  final VoiceApiFailure failure;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class VoiceApi {
  VoiceApi({required Dio dio, required Uri endpoint, required String token})
      : _dio = dio,
        _endpoint = endpoint,
        _token = token;

  factory VoiceApi.fromBaseUri({
    required Dio dio,
    required Uri baseUri,
    required String token,
  }) {
    return VoiceApi(
      dio: dio,
      endpoint: _apiUri(baseUri, 'voice/stt'),
      token: token,
    );
  }

  final Dio _dio;
  final Uri _endpoint;
  final String _token;

  Future<String> transcribe({
    required String filePath,
    String? language,
  }) async {
    final audioFile = File(filePath);
    if (!await audioFile.exists() || await audioFile.length() == 0) {
      throw const VoiceApiException(
        VoiceApiFailure.invalidAudio,
        '录音文件为空，请重新录音。',
      );
    }

    final filename = audioFile.uri.pathSegments.last;
    final fields = <String, dynamic>{
      'file': await MultipartFile.fromFile(
        filePath,
        filename: filename,
        contentType: DioMediaType('audio', 'mp4'),
      ),
    };
    final normalizedLanguage = language?.trim();
    if (normalizedLanguage != null && normalizedLanguage.isNotEmpty) {
      fields['language'] = normalizedLanguage;
    }

    try {
      final response = await _dio.post<dynamic>(
        _endpoint.toString(),
        data: FormData.fromMap(fields),
        options: Options(
          headers: <String, String>{
            if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
          },
        ),
      );
      final data = response.data;
      final text = data is Map ? data['text']?.toString().trim() : null;
      if (text == null || text.isEmpty) {
        throw const VoiceApiException(
          VoiceApiFailure.server,
          '语音服务未返回转写文字，请重试。',
        );
      }
      return text;
    } on VoiceApiException {
      rethrow;
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  static VoiceApiException _mapDioException(DioException error) {
    final statusCode = error.response?.statusCode;
    if (statusCode == 401 || statusCode == 403) {
      return VoiceApiException(
        VoiceApiFailure.unauthorized,
        '登录已失效，请重新登录。',
        statusCode: statusCode,
      );
    }
    if (statusCode == 400 || statusCode == 413 || statusCode == 415) {
      final detail = _responseDetail(error.response?.data);
      return VoiceApiException(
        VoiceApiFailure.invalidAudio,
        detail.isEmpty
            ? '服务器无法识别 AAC/M4A 录音；请确认 STT provider 支持 M4A，必要时改用 WAV/PCM。'
            : '$detail（若持续失败，请确认 STT provider 支持 AAC/M4A，必要时改用 WAV/PCM。）',
        statusCode: statusCode,
      );
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return const VoiceApiException(
        VoiceApiFailure.offline,
        '无法连接服务器，请检查网络后重试。',
      );
    }
    return VoiceApiException(
      statusCode == null ? VoiceApiFailure.unknown : VoiceApiFailure.server,
      _responseDetail(error.response?.data).isNotEmpty
          ? _responseDetail(error.response?.data)
          : '语音转写失败，请稍后重试。',
      statusCode: statusCode,
    );
  }

  static String _responseDetail(Object? data) {
    if (data is Map && data['detail'] != null) return data['detail'].toString();
    return '';
  }

  static Uri _apiUri(Uri baseUri, String suffix) {
    final basePath = baseUri.path.replaceFirst(RegExp(r'/+$'), '');
    final hasApiPrefix = basePath.endsWith('/api/v1');
    return baseUri.replace(
      path: '${hasApiPrefix ? basePath : '$basePath/api/v1'}/$suffix',
      query: null,
      fragment: null,
    );
  }
}
