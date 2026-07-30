import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../config/server_url.dart';

/// Produces a stable, non-identifying storage namespace for one server user.
///
/// Only the normalized server origin and user id are hashed. The resulting
/// lowercase SHA-256 digest is safe to use in file names and does not expose
/// either input in backups or directory listings.
String buildScopedCacheNamespace({
  required String serverUrl,
  required String userId,
}) {
  final user = userId.trim();
  if (user.isEmpty) {
    throw ArgumentError.value(userId, 'userId', 'Must not be empty.');
  }
  final server = Uri.parse(normalizeServerUrl(serverUrl));
  final canonicalOrigin = Uri(
    scheme: server.scheme.toLowerCase(),
    host: server.host.toLowerCase(),
    port: server.hasPort ? server.port : null,
  ).origin;
  return sha256.convert(utf8.encode('$canonicalOrigin\n$user')).toString();
}

String? validateCacheNamespace(String? value) {
  if (value == null) return null;
  final normalized = value.trim().toLowerCase();
  if (!RegExp(r'^[a-z0-9_-]{1,128}$').hasMatch(normalized)) {
    throw ArgumentError.value(value, 'namespace', 'Must be file-name safe.');
  }
  return normalized;
}
