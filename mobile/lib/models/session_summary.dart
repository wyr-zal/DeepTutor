class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.title,
    required this.capability,
    required this.status,
    required this.messageCount,
    required this.lastMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String capability;
  final String status;
  final int messageCount;
  final String lastMessage;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    final id = (json['session_id'] ?? json['id'] ?? '').toString().trim();
    if (id.isEmpty) {
      throw const FormatException('Session summary is missing an id.');
    }

    final rawCount = json['message_count'];
    final messageCount = switch (rawCount) {
      int value => value,
      num value => value.toInt(),
      _ => int.tryParse('$rawCount') ?? 0,
    };

    return SessionSummary(
      id: id,
      title: (json['title'] ?? '').toString().trim(),
      capability: (json['capability'] ?? json['mode'] ?? '').toString().trim(),
      status: (json['status'] ?? '').toString().trim(),
      messageCount: messageCount < 0 ? 0 : messageCount,
      lastMessage: (json['last_message'] ?? '').toString().trim(),
      createdAt: _parseTimestamp(json['created_at']),
      updatedAt: _parseTimestamp(json['updated_at']),
    );
  }

  DateTime? get activityAt => updatedAt ?? createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'session_id': id,
        'title': title,
        'capability': capability,
        'status': status,
        'message_count': messageCount,
        'last_message': lastMessage,
        if (createdAt != null)
          'created_at': createdAt!.toUtc().toIso8601String(),
        if (updatedAt != null)
          'updated_at': updatedAt!.toUtc().toIso8601String(),
      };

  static DateTime? _parseTimestamp(Object? value) {
    if (value == null) return null;
    if (value is num) {
      final milliseconds =
          value.abs() >= 100000000000 ? value.round() : (value * 1000).round();
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    final numeric = num.tryParse(text);
    if (numeric != null) return _parseTimestamp(numeric);
    return DateTime.tryParse(text)?.toUtc();
  }
}
