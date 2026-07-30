import 'package:deeptutor_mobile/models/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses token contract with nested user', () {
    final session = AuthSession.fromTokenResponse(
      baseUrl: 'https://tutor.example.com',
      json: <String, dynamic>{
        'access_token': 'jwt-value',
        'token_type': 'bearer',
        'expires_in': 7200,
        'user': <String, dynamic>{
          'user_id': 'u_1',
          'username': 'learner',
          'role': 'user',
          'is_admin': false,
        },
      },
    );

    expect(session.accessToken, 'jwt-value');
    expect(session.expiresIn, 7200);
    expect(session.user.id, 'u_1');
    expect(session.user.username, 'learner');
    expect(session.user.isAdmin, isFalse);
  });

  test('auth-disabled session is usable without an access token', () {
    final session = AuthSession.local(baseUrl: 'http://10.0.2.2:8001');

    expect(session.authEnabled, isFalse);
    expect(session.hasAccessToken, isFalse);
    expect(session.user.isAdmin, isTrue);
  });

  test('missing access token is rejected', () {
    expect(
      () => AuthSession.fromTokenResponse(
        baseUrl: 'https://tutor.example.com',
        json: const <String, dynamic>{},
      ),
      throwsFormatException,
    );
  });
}
