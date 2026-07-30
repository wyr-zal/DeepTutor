class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.role,
    required this.isAdmin,
  });

  final String id;
  final String username;
  final String role;
  final bool isAdmin;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final role = (json['role'] as String?)?.trim() ?? 'user';
    final username = (json['username'] ?? '').toString().trim();
    final rawId = (json['user_id'] ?? json['id'] ?? '').toString().trim();
    return AuthUser(
      // Older deployments can omit user_id from /auth/status. Falling back to
      // the authenticated username keeps per-user local history isolated.
      id: rawId.isEmpty ? username : rawId,
      username: username,
      role: role,
      isAdmin: json['is_admin'] == true || role == 'admin',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'user_id': id,
        'username': username,
        'role': role,
        'is_admin': isAdmin,
      };
}

class AuthSession {
  const AuthSession({
    required this.baseUrl,
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    required this.user,
    required this.authEnabled,
  });

  final String baseUrl;
  final String? accessToken;
  final String tokenType;
  final int? expiresIn;
  final AuthUser user;
  final bool authEnabled;

  bool get hasAccessToken => accessToken?.isNotEmpty == true;

  factory AuthSession.fromTokenResponse({
    required String baseUrl,
    required Map<String, dynamic> json,
  }) {
    final accessToken = (json['access_token'] ?? '').toString().trim();
    if (accessToken.isEmpty) {
      throw const FormatException('服务器未返回访问令牌');
    }

    final rawUser = json['user'];
    final user = rawUser is Map
        ? AuthUser.fromJson(Map<String, dynamic>.from(rawUser))
        : AuthUser.fromJson(json);
    final expires = json['expires_in'];

    return AuthSession(
      baseUrl: baseUrl,
      accessToken: accessToken,
      tokenType: (json['token_type'] ?? 'bearer').toString(),
      expiresIn: expires is int ? expires : int.tryParse('$expires'),
      user: user,
      authEnabled: true,
    );
  }

  factory AuthSession.local({required String baseUrl, AuthUser? user}) {
    return AuthSession(
      baseUrl: baseUrl,
      accessToken: null,
      tokenType: 'bearer',
      expiresIn: null,
      user: user ??
          const AuthUser(
            id: 'local-admin',
            username: 'local',
            role: 'admin',
            isAdmin: true,
          ),
      authEnabled: false,
    );
  }
}

class AuthStatus {
  const AuthStatus({
    required this.enabled,
    required this.authenticated,
    this.user,
  });

  final bool enabled;
  final bool authenticated;
  final AuthUser? user;

  factory AuthStatus.fromJson(Map<String, dynamic> json) {
    final nestedUser = json['user'];
    final userJson = nestedUser is Map
        ? Map<String, dynamic>.from(nestedUser)
        : <String, dynamic>{
            'user_id': json['user_id'],
            'username': json['username'],
            'role': json['role'],
            'is_admin': json['is_admin'],
          };
    final hasUser = (userJson['username'] ?? '').toString().isNotEmpty;
    return AuthStatus(
      enabled: json['enabled'] != false,
      authenticated: json['authenticated'] == true,
      user: hasUser ? AuthUser.fromJson(userJson) : null,
    );
  }
}
