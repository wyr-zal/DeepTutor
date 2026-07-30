import 'package:deeptutor_mobile/config/server_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeServerUrl', () {
    test('defaults to HTTPS and removes trailing slashes', () {
      expect(
        normalizeServerUrl('  tutor.example.com:8443/// '),
        'https://tutor.example.com:8443',
      );
    });

    test('preserves an explicit HTTP deployment prefix', () {
      expect(
        normalizeServerUrl('http://10.0.2.2:8001/deeptutor/'),
        'http://10.0.2.2:8001/deeptutor',
      );
    });

    test('rejects cleartext HTTP when production policy is requested', () {
      expect(
        () => normalizeServerUrl(
          'http://10.0.2.2:8001',
          allowInsecure: false,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('HTTPS'),
          ),
        ),
      );
    });

    test('rejects unsupported or ambiguous addresses', () {
      expect(() => normalizeServerUrl(''), throwsFormatException);
      expect(
        () => normalizeServerUrl('ftp://example.com'),
        throwsFormatException,
      );
      expect(
        () => normalizeServerUrl('https://user@example.com'),
        throwsFormatException,
      );
      expect(
        () => normalizeServerUrl('https://example.com?redirect=elsewhere'),
        throwsFormatException,
      );
    });
  });

  test('resolveServerUri retains a deployment prefix', () {
    expect(
      resolveServerUri(
        'https://example.com/deeptutor/',
        '/api/v1/auth/status',
      ).toString(),
      'https://example.com/deeptutor/api/v1/auth/status',
    );
  });

  test('resolveServerUri does not duplicate an existing api prefix', () {
    expect(
      resolveServerUri(
        'https://example.com/deeptutor/api/v1',
        '/api/v1/auth/status',
      ).toString(),
      'https://example.com/deeptutor/api/v1/auth/status',
    );
  });
}
