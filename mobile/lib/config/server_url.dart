import 'package:flutter/foundation.dart';

/// Normalizes a user-entered DeepTutor server URL.
///
/// A missing scheme defaults to HTTPS. Production builds reject cleartext
/// HTTP; it remains available in debug builds for emulators and local servers.
String normalizeServerUrl(
  String value, {
  bool allowInsecure = kDebugMode,
}) {
  var candidate = value.trim();
  if (candidate.isEmpty) {
    throw const FormatException('请输入服务器地址');
  }

  if (!candidate.contains('://')) {
    candidate = 'https://$candidate';
  }

  final uri = Uri.tryParse(candidate);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException('请输入有效的 HTTP 或 HTTPS 服务器地址');
  }
  if (uri.scheme == 'http' && !allowInsecure) {
    throw const FormatException('正式版本仅支持 HTTPS 服务器地址');
  }

  var path = uri.path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path == '/') {
    path = '';
  }

  return uri.replace(path: path).toString();
}

/// Joins an API path to a normalized server URL without discarding an
/// optional deployment prefix in the base URL.
Uri resolveServerUri(String baseUrl, String path) {
  final normalizedBase = normalizeServerUrl(baseUrl);
  final cleanPath = path.trim().replaceFirst(RegExp(r'^/+'), '');
  if (cleanPath.isEmpty) {
    return Uri.parse(normalizedBase);
  }
  final base = Uri.parse(normalizedBase);
  final basePath = base.path.replaceFirst(RegExp(r'/+$'), '');
  final relativePath =
      basePath.endsWith('/api/v1') && cleanPath.startsWith('api/v1/')
          ? cleanPath.substring('api/v1/'.length)
          : cleanPath;
  return base.replace(
    path: '$basePath/$relativePath',
    query: null,
    fragment: null,
  );
}
