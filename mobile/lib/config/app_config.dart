import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'server_url.dart';

class AppConnectionConfig {
  const AppConnectionConfig({
    required this.fixedServerUrl,
    required this.personalServerMode,
    this.diagnosticsEnabled = false,
  });

  factory AppConnectionConfig.fromEnvironment() {
    return const AppConnectionConfig(
      fixedServerUrl: String.fromEnvironment('DEEPTUTOR_FIXED_SERVER_URL'),
      personalServerMode: bool.fromEnvironment(
        'DEEPTUTOR_PERSONAL_SERVER_MODE',
      ),
      diagnosticsEnabled: bool.fromEnvironment('DEEPTUTOR_DIAGNOSTICS'),
    );
  }

  final String fixedServerUrl;
  final bool personalServerMode;
  final bool diagnosticsEnabled;

  bool get hasFixedServerUrl => fixedServerUrl.trim().isNotEmpty;

  String? normalizedFixedServerUrl() {
    if (!hasFixedServerUrl) return null;
    return normalizeServerUrl(fixedServerUrl);
  }
}

final appConnectionConfigProvider = Provider<AppConnectionConfig>(
  (ref) => AppConnectionConfig.fromEnvironment(),
);
