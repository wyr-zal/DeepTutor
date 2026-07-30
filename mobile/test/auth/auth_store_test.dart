import 'package:deeptutor_mobile/models/auth_session.dart';
import 'package:deeptutor_mobile/services/auth_store.dart';
import 'package:flutter_test/flutter_test.dart';

class MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

void main() {
  test('round-trips a complete token session', () async {
    final storage = MemorySecureStore();
    final store = AuthStore(storage);
    const session = AuthSession(
      baseUrl: 'https://tutor.example.com',
      accessToken: 'secret-jwt',
      tokenType: 'bearer',
      expiresIn: 3600,
      user: AuthUser(
        id: 'u_1',
        username: 'learner',
        role: 'user',
        isAdmin: false,
      ),
      authEnabled: true,
    );

    await store.saveSession(session);
    final restored = await store.readSession();

    expect(restored?.baseUrl, session.baseUrl);
    expect(restored?.accessToken, session.accessToken);
    expect(restored?.user.username, 'learner');
    expect(restored?.authEnabled, isTrue);
  });

  test('retains base URL while clearing credentials', () async {
    final storage = MemorySecureStore();
    final store = AuthStore(storage);
    await store.saveSession(
      AuthSession.local(baseUrl: 'https://tutor.example.com'),
    );

    await store.clearSession();

    expect(await store.readBaseUrl(), 'https://tutor.example.com');
    expect(await store.readSession(), isNull);
  });

  test('round-trips an auth-disabled session without a token', () async {
    final store = AuthStore(MemorySecureStore());
    final session = AuthSession.local(baseUrl: 'http://10.0.2.2:8001');

    await store.saveSession(session);

    final restored = await store.readSession();
    expect(restored?.authEnabled, isFalse);
    expect(restored?.hasAccessToken, isFalse);
  });
}
