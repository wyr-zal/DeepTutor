import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_session.dart';
import 'api_client.dart';
import 'network_diagnostics.dart';

class AuthApiException implements Exception {
  const AuthApiException(
    this.message, {
    this.statusCode,
    this.diagnosticDetails,
  });

  final String message;
  final int? statusCode;
  final String? diagnosticDetails;

  @override
  String toString() => message;
}

class AuthApi {
  const AuthApi(this._client);

  final ApiClient _client;

  Future<AuthStatus> status(String baseUrl) async {
    try {
      final response = await _client.get<dynamic>(
        baseUrl,
        '/api/v1/auth/status',
      );
      return AuthStatus.fromJson(_asJsonMap(response.data));
    } on DioException catch (error) {
      throw _mapDioError(error);
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  Future<AuthSession> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    try {
      final response = await _client.post<dynamic>(
        baseUrl,
        '/api/v1/auth/token',
        data: <String, String>{'username': username, 'password': password},
      );
      return AuthSession.fromTokenResponse(
        baseUrl: baseUrl,
        json: _asJsonMap(response.data),
      );
    } on DioException catch (error) {
      throw _mapDioError(error);
    } on FormatException catch (error) {
      throw AuthApiException(error.message);
    }
  }

  static Map<String, dynamic> _asJsonMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    throw const FormatException('服务器返回了无法识别的数据');
  }

  static AuthApiException _mapDioError(DioException error) {
    final statusCode = error.response?.statusCode;
    final body = error.response?.data;
    final detail = body is Map ? body['detail']?.toString().trim() : null;

    if (statusCode == 401) {
      return AuthApiException(
        '用户名或密码不正确',
        statusCode: 401,
        diagnosticDetails: NetworkDiagnostics.describeDioException(error),
      );
    }
    if (statusCode == 404) {
      return AuthApiException(
        '服务器不支持移动端登录接口，请确认 DeepTutor 版本',
        statusCode: 404,
        diagnosticDetails: NetworkDiagnostics.describeDioException(error),
      );
    }
    if (statusCode != null) {
      return AuthApiException(
        detail?.isNotEmpty == true ? detail! : '服务器请求失败（$statusCode）',
        statusCode: statusCode,
        diagnosticDetails: NetworkDiagnostics.describeDioException(error),
      );
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return AuthApiException(
        '连接服务器超时，请检查地址和网络',
        diagnosticDetails: NetworkDiagnostics.describeDioException(error),
      );
    }
    return AuthApiException(
      '无法连接服务器，请检查地址和网络',
      diagnosticDetails: NetworkDiagnostics.describeDioException(error),
    );
  }
}

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiClientProvider)),
);
