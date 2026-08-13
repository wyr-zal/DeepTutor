import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../config/server_url.dart';
import '../services/auth_store.dart';
import 'network_diagnostics.dart';

class UnauthorizedEvent {
  const UnauthorizedEvent(this.uri);

  final Uri uri;
}

class ApiClient {
  ApiClient({
    required AuthStore authStore,
    Dio? dio,
    this.diagnosticsEnabled = false,
  })  : _authStore = authStore,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
                sendTimeout: const Duration(seconds: 30),
                responseType: ResponseType.json,
              ),
            ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (diagnosticsEnabled) {
            NetworkDiagnostics.logRequest(options);
          }
          final storedBaseUrl = await _authStore.readBaseUrl();
          final token = await _authStore.readAccessToken();
          if (token != null &&
              token.isNotEmpty &&
              storedBaseUrl != null &&
              _belongsToServer(options.uri, storedBaseUrl)) {
            options.headers.putIfAbsent('Authorization', () => 'Bearer $token');
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          if (diagnosticsEnabled) {
            NetworkDiagnostics.logResponse(response);
          }
          handler.next(response);
        },
        onError: (error, handler) {
          if (diagnosticsEnabled) {
            NetworkDiagnostics.logError(error);
          }
          if (error.response?.statusCode == 401 && !_unauthorized.isClosed) {
            _unauthorized.add(UnauthorizedEvent(error.requestOptions.uri));
          }
          handler.next(error);
        },
      ),
    );
  }

  final AuthStore _authStore;
  final Dio _dio;
  final bool diagnosticsEnabled;
  final StreamController<UnauthorizedEvent> _unauthorized =
      StreamController<UnauthorizedEvent>.broadcast();

  Dio get dio => _dio;

  Stream<UnauthorizedEvent> get unauthorizedEvents => _unauthorized.stream;

  Future<Response<T>> get<T>(
    String baseUrl,
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.getUri<T>(
      _withQuery(resolveServerUri(baseUrl, path), queryParameters),
      options: options,
    );
  }

  Future<Response<T>> post<T>(
    String baseUrl,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.postUri<T>(
      _withQuery(resolveServerUri(baseUrl, path), queryParameters),
      data: data,
      options: options,
    );
  }

  Future<Response<T>> patch<T>(
    String baseUrl,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.patchUri<T>(
      _withQuery(resolveServerUri(baseUrl, path), queryParameters),
      data: data,
      options: options,
    );
  }

  Future<Response<T>> delete<T>(
    String baseUrl,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.deleteUri<T>(
      _withQuery(resolveServerUri(baseUrl, path), queryParameters),
      data: data,
      options: options,
    );
  }

  static Uri _withQuery(
    Uri uri,
    Map<String, dynamic>? queryParameters,
  ) {
    if (queryParameters == null || queryParameters.isEmpty) return uri;
    return uri.replace(
      queryParameters: <String, dynamic>{
        ...uri.queryParametersAll,
        for (final entry in queryParameters.entries)
          entry.key: switch (entry.value) {
            Iterable<Object?> values => values.map((value) => '$value'),
            final value => '$value',
          },
      },
    );
  }

  static bool _belongsToServer(Uri request, String storedBaseUrl) {
    try {
      final server = Uri.parse(normalizeServerUrl(storedBaseUrl));
      final serverPath =
          server.path.endsWith('/') ? server.path : '${server.path}/';
      return request.scheme == server.scheme &&
          request.host == server.host &&
          request.port == server.port &&
          (server.path.isEmpty ||
              request.path == server.path ||
              request.path.startsWith(serverPath));
    } on FormatException {
      return false;
    }
  }

  void dispose() {
    _unauthorized.close();
    _dio.close();
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    authStore: ref.watch(authStoreProvider),
    diagnosticsEnabled:
        ref.watch(appConnectionConfigProvider).diagnosticsEnabled,
  );
  ref.onDispose(client.dispose);
  return client;
});
