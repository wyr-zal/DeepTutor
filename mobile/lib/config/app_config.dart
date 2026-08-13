import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'server_url.dart';

class AppConnectionConfig {
  const AppConnectionConfig({
    required this.fixedServerUrl,
    this.diagnosticsEnabled = false,
    this.manualServerEntryEnabled = kDebugMode,
  });

  factory AppConnectionConfig.fromEnvironment() {
    const configuredServerUrl = String.fromEnvironment(
      'DEEPTUTOR_FIXED_SERVER_URL',
    );
    const manualServerEntryEnabled = bool.fromEnvironment(
      'DEEPTUTOR_ALLOW_SERVER_ENTRY',
    );
    return AppConnectionConfig(
      fixedServerUrl: configuredServerUrl,
      diagnosticsEnabled: const bool.fromEnvironment('DEEPTUTOR_DIAGNOSTICS'),
      manualServerEntryEnabled: kDebugMode || manualServerEntryEnabled,
    );
  }

  final String fixedServerUrl;
  final bool diagnosticsEnabled;
  final bool manualServerEntryEnabled;

  bool get hasFixedServerUrl => fixedServerUrl.trim().isNotEmpty;

  String? normalizedFixedServerUrl() {
    if (!hasFixedServerUrl) return null;
    return normalizeServerUrl(fixedServerUrl);
  }
}

final appConnectionConfigProvider = Provider<AppConnectionConfig>(
  (ref) => AppConnectionConfig.fromEnvironment(),
);
