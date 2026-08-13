class SessionDetail {
  const SessionDetail({
    required this.sessionId,
    required this.title,
    required this.messages,
    this.revision,
  });

  factory SessionDetail.fromJson(Map<String, dynamic> json) {
    final sessionId =
        (json['session_id'] ?? json['id'] ?? '').toString().trim();
    if (sessionId.isEmpty) {
      throw const FormatException('Session detail is missing an id.');
    }
    final rawMessages = json['messages'];
    if (rawMessages is! Iterable) {
      throw const FormatException('Session detail must contain messages.');
    }
    return SessionDetail(
      sessionId: sessionId,
      title: (json['title'] ?? '').toString().trim(),
      messages: List<SessionMessage>.unmodifiable(
        rawMessages.whereType<Map>().map(
              (message) => SessionMessage.fromJson(
                message.map((key, value) => MapEntry(key.toString(), value)),
              ),
            ),
      ),
      revision: _parseNonNegativeIntOrNull(json['revision']),
    );
  }

  final String sessionId;
  final String title;
  final List<SessionMessage> messages;
  final int? revision;

  static int? _parseNonNegativeIntOrNull(Object? value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }
}

class SessionMessage {
  const SessionMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.capability,
    required this.metadata,
    required this.events,
  });

  factory SessionMessage.fromJson(Map<String, dynamic> json) {
    return SessionMessage(
      id: (json['id'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      capability: (json['capability'] ?? '').toString(),
      metadata: _stringMap(json['metadata']),
      events: List<Map<String, dynamic>>.unmodifiable(
        (json['events'] is Iterable
                ? json['events'] as Iterable
                : const <Object>[])
            .whereType<Map>()
            .map((event) => event.map(
                  (key, value) => MapEntry(key.toString(), value),
                )),
      ),
    );
  }

  final String id;
  final String role;
  final String content;
  final String capability;
  final Map<String, dynamic> metadata;
  final List<Map<String, dynamic>> events;

  static Map<String, dynamic> _stringMap(Object? value) {
    if (value is! Map) return const <String, dynamic>{};
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
}
