import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/network_diagnostics.dart';
import '../../config/app_config.dart';
import '../../config/server_url.dart';

final transportDiagnosticsProvider =
    FutureProvider<TransportDiagnosticsReport?>((ref) async {
  final config = ref.watch(appConnectionConfigProvider);
  if (!config.diagnosticsEnabled) return null;

  try {
    final fixedBaseUrl = config.normalizedFixedServerUrl();
    if (fixedBaseUrl == null || fixedBaseUrl.isEmpty) {
      return const TransportDiagnosticsReport(
        steps: <TransportDiagnosticStep>[
          TransportDiagnosticStep.failed(
            name: 'fixed URL',
            detail: 'DEEPTUTOR_FIXED_SERVER_URL is empty',
            elapsedMs: 0,
          ),
        ],
      );
    }
    return TransportDiagnosticsRunner.run(Uri.parse(fixedBaseUrl));
  } on Object catch (error) {
    return TransportDiagnosticsReport(
      steps: <TransportDiagnosticStep>[
        TransportDiagnosticStep.failed(
          name: 'transport diagnostics bootstrap',
          detail: NetworkDiagnostics.describeObject(error),
          elapsedMs: 0,
        ),
      ],
    );
  }
});

class TransportDiagnosticsReport {
  const TransportDiagnosticsReport({required this.steps});

  final List<TransportDiagnosticStep> steps;

  String toDisplayText() {
    if (steps.isEmpty) return 'transport diagnostics: no steps';
    return steps.map((step) => step.toDisplayText()).join('\n');
  }
}

class TransportDiagnosticStep {
  const TransportDiagnosticStep({
    required this.name,
    required this.ok,
    required this.detail,
    required this.elapsedMs,
  });

  const TransportDiagnosticStep.ok({
    required String name,
    required String detail,
    required int elapsedMs,
  }) : this(
          name: name,
          ok: true,
          detail: detail,
          elapsedMs: elapsedMs,
        );

  const TransportDiagnosticStep.failed({
    required String name,
    required String detail,
    required int elapsedMs,
  }) : this(
          name: name,
          ok: false,
          detail: detail,
          elapsedMs: elapsedMs,
        );

  final String name;
  final bool ok;
  final String detail;
  final int elapsedMs;

  String toDisplayText() {
    final status = ok ? 'OK' : 'FAIL';
    return '[$status] $name (${elapsedMs}ms)\n$detail';
  }
}

class TransportDiagnosticsRunner {
  const TransportDiagnosticsRunner._();

  static const Duration _timeout = Duration(seconds: 6);

  static Future<TransportDiagnosticsReport> run(Uri baseUri) async {
    final host = baseUri.host;
    final port = _portFor(baseUri);
    final authStatusUri = resolveServerUri(
      _origin(baseUri),
      '/api/v1/auth/status',
    );
    final steps = <TransportDiagnosticStep>[];
    var addresses = <InternetAddress>[];

    steps.add(
      await _record('DNS lookup', () async {
        addresses = await InternetAddress.lookup(host).timeout(_timeout);
        if (addresses.isEmpty) {
          throw const SocketException('DNS returned no address');
        }
        return addresses
            .map((address) => '${address.address}/${address.type.name}')
            .join(', ');
      }),
    );

    steps.add(
      await _record('TCP host:$port', () async {
        final socket = await Socket.connect(
          host,
          port,
          timeout: _timeout,
        ).timeout(_timeout);
        final detail =
            'remote=${socket.remoteAddress.address}:${socket.remotePort}';
        socket.destroy();
        return detail;
      }),
    );

    if (baseUri.scheme == 'https') {
      steps.add(
        await _record('TLS host + SNI', () async {
          final socket = await SecureSocket.connect(
            host,
            port,
            timeout: _timeout,
            supportedProtocols: const <String>['http/1.1'],
          ).timeout(_timeout);
          final detail = _secureSocketDetail(socket);
          await socket.close().timeout(_timeout);
          return detail;
        }),
      );
    }

    if (addresses.isNotEmpty) {
      final address = _preferredAddress(addresses);
      steps.add(
        await _record('TCP direct IP:$port', () async {
          final socket = await Socket.connect(
            address,
            port,
            timeout: _timeout,
          ).timeout(_timeout);
          final detail =
              'remote=${socket.remoteAddress.address}:${socket.remotePort}';
          socket.destroy();
          return detail;
        }),
      );

      if (baseUri.scheme == 'https') {
        steps.add(
          await _record('TLS direct IP + SNI', () async {
            final raw = await Socket.connect(
              address,
              port,
              timeout: _timeout,
            ).timeout(_timeout);
            final socket = await SecureSocket.secure(
              raw,
              host: host,
              supportedProtocols: const <String>['http/1.1'],
            ).timeout(_timeout);
            final detail = _secureSocketDetail(socket);
            await socket.close().timeout(_timeout);
            return detail;
          }),
        );

        steps.add(
          await _record('HTTPS direct IP + SNI + Host GET', () async {
            final raw = await Socket.connect(
              address,
              port,
              timeout: _timeout,
            ).timeout(_timeout);
            final socket = await SecureSocket.secure(
              raw,
              host: host,
              supportedProtocols: const <String>['http/1.1'],
            ).timeout(_timeout);
            try {
              socket.write(
                'GET ${authStatusUri.path} HTTP/1.1\r\n'
                'Host: $host\r\n'
                'User-Agent: DeepTutorMobileDiagnostics/1.0\r\n'
                'Accept: application/json\r\n'
                'Connection: close\r\n'
                '\r\n',
              );
              await socket.flush().timeout(_timeout);
              final responseText = await socket
                  .cast<List<int>>()
                  .transform(utf8.decoder)
                  .join()
                  .timeout(_timeout);
              return _httpResponseSummary(responseText);
            } finally {
              await socket.close().timeout(_timeout);
            }
          }),
        );
      }
    }

    steps.add(
      await _record('HttpClient GET auth/status', () async {
        return _httpClientGet(authStatusUri);
      }),
    );

    steps.add(
      await _record('HttpClient GET browser UA', () async {
        return _httpClientGet(
          authStatusUri,
          userAgent: 'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36',
        );
      }),
    );

    return TransportDiagnosticsReport(steps: List.unmodifiable(steps));
  }

  static Future<TransportDiagnosticStep> _record(
    String name,
    Future<String> Function() action,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final detail = await action();
      stopwatch.stop();
      final step = TransportDiagnosticStep.ok(
        name: name,
        detail: _compact(detail),
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
      debugPrint('[DeepTutorTransport] ${step.toDisplayText()}');
      return step;
    } on Object catch (error) {
      stopwatch.stop();
      final step = TransportDiagnosticStep.failed(
        name: name,
        detail: _compact(_describeTransportError(error)),
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
      debugPrint('[DeepTutorTransport] ${step.toDisplayText()}');
      return step;
    }
  }

  static Future<String> _httpClientGet(
    Uri uri, {
    String? userAgent,
  }) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(uri).timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (userAgent != null) {
        request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      }
      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join().timeout(
            _timeout,
          );
      return 'status=${response.statusCode}\nbody=${_compact(body)}';
    } finally {
      client.close(force: true);
    }
  }

  static String _secureSocketDetail(SecureSocket socket) {
    final certificate = socket.peerCertificate;
    final subject = certificate?.subject ?? '<no peer certificate>';
    return <String>[
      'remote=${socket.remoteAddress.address}:${socket.remotePort}',
      'selectedProtocol=${socket.selectedProtocol ?? '<none>'}',
      'certificate=${_compact(subject, limit: 220)}',
    ].join('\n');
  }

  static String _httpResponseSummary(String responseText) {
    final crlfLines = responseText.split('\r\n');
    final lfLines = responseText.split('\n');
    final firstHeaderLine = crlfLines.firstOrNullSafe ??
        lfLines.firstOrNullSafe ??
        '<empty response>';
    final bodyStart = responseText.indexOf('\r\n\r\n');
    final body =
        bodyStart >= 0 ? responseText.substring(bodyStart + 4) : responseText;
    return 'head=${_compact(firstHeaderLine)}\nbody=${_compact(body)}';
  }

  static InternetAddress _preferredAddress(List<InternetAddress> addresses) {
    return addresses.firstWhere(
      (address) => address.type == InternetAddressType.IPv4,
      orElse: () => addresses.first,
    );
  }

  static int _portFor(Uri uri) {
    if (uri.hasPort) return uri.port;
    return switch (uri.scheme) {
      'https' => 443,
      'http' => 80,
      _ => uri.port,
    };
  }

  static String _origin(Uri uri) {
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  static String _describeTransportError(Object error) {
    if (error is TimeoutException) {
      return 'TimeoutException: ${error.message ?? 'operation timed out'}';
    }
    return '${error.runtimeType}: $error';
  }

  static String _compact(String value, {int limit = 500}) {
    final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= limit) return singleLine;
    return '${singleLine.substring(0, limit)}…';
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNullSafe => isEmpty ? null : first;
}
