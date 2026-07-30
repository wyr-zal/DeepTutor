import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class NetworkDiagnostics {
  const NetworkDiagnostics._();

  static String requestLine(RequestOptions options) {
    return '${options.method} ${uriForDisplay(options.uri)}';
  }

  static String responseLine(Response<dynamic> response) {
    return '${response.requestOptions.method} '
        '${uriForDisplay(response.requestOptions.uri)} '
        'status=${response.statusCode ?? 'unknown'}';
  }

  static String describeDioException(DioException error) {
    final response = error.response;
    final lines = <String>[
      requestLine(error.requestOptions),
      'type=${error.type.name}',
      'status=${response?.statusCode?.toString() ?? 'none'}',
    ];

    final nativeError = error.error;
    if (nativeError != null) {
      lines.add('native=${_compact(nativeError.toString())}');
    }
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) {
      lines.add('message=${_compact(message)}');
    }
    final body = _bodySummary(response?.data);
    if (body != null) {
      lines.add(body);
    }
    return lines.join('\n');
  }

  static String describeObject(
    Object error, {
    Uri? uri,
    String? method,
  }) {
    if (error is DioException) return describeDioException(error);
    final lines = <String>[
      if (uri != null) '${method ?? 'GET'} ${uriForDisplay(uri)}',
      'error=${_compact(error.toString())}',
    ];
    return lines.join('\n');
  }

  static String describeSuccess({
    required String method,
    required Uri uri,
    int? statusCode,
    String? details,
  }) {
    return <String>[
      '$method ${uriForDisplay(uri)}',
      'status=${statusCode?.toString() ?? 'ok'}',
      if (details != null && details.trim().isNotEmpty)
        'result=${_compact(details)}',
    ].join('\n');
  }

  static void logRequest(RequestOptions options) {
    debugPrint('[DeepTutorNetwork] --> ${requestLine(options)}');
  }

  static void logResponse(Response<dynamic> response) {
    debugPrint('[DeepTutorNetwork] <-- ${responseLine(response)}');
  }

  static void logError(DioException error) {
    debugPrint('[DeepTutorNetwork] !! ${describeDioException(error)}');
  }

  static String uriForDisplay(Uri uri) {
    final port = uri.hasPort ? ':${uri.port}' : '';
    final query = uri.hasQuery ? '?<redacted>' : '';
    return '${uri.scheme}://${uri.host}$port${uri.path}$query';
  }

  static String _compact(String value, {int limit = 500}) {
    final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= limit) return singleLine;
    return '${singleLine.substring(0, limit)}…';
  }

  static String? _bodySummary(Object? body) {
    if (body == null) return null;
    if (body is Map) {
      final detail = body['detail']?.toString().trim();
      if (detail != null && detail.isNotEmpty) {
        return 'body.detail=${_compact(detail)}';
      }
      return 'body=object(keys=${body.keys.take(8).join(',')})';
    }
    if (body is List) return 'body=list(length=${body.length})';
    if (body is String && body.trim().isNotEmpty) {
      return 'body=${_compact(body)}';
    }
    return 'body=${body.runtimeType}';
  }
}
