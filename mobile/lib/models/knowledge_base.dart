class KnowledgeBase {
  const KnowledgeBase({
    required this.name,
    this.id,
    this.isDefault = false,
    this.statistics = const <String, dynamic>{},
    this.metadata,
    this.status,
    this.progress,
    this.source,
    this.assigned = false,
    this.readOnly = false,
    this.provenanceLabel,
    this.available = true,
  });

  factory KnowledgeBase.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('Knowledge base name is missing.');
    }

    return KnowledgeBase(
      id: _optionalString(json['id']),
      name: name.trim(),
      isDefault: json['is_default'] == true,
      statistics: _stringMap(json['statistics']) ?? const <String, dynamic>{},
      metadata: _stringMap(json['metadata']),
      status: _optionalString(json['status']),
      progress: _stringMap(json['progress']),
      source: _optionalString(json['source']),
      assigned: json['assigned'] == true,
      readOnly: json['read_only'] == true,
      provenanceLabel: _optionalString(json['provenance_label']),
      available: json['available'] != false,
    );
  }

  final String? id;
  final String name;
  final bool isDefault;
  final Map<String, dynamic> statistics;
  final Map<String, dynamic>? metadata;
  final String? status;
  final Map<String, dynamic>? progress;
  final String? source;
  final bool assigned;
  final bool readOnly;
  final String? provenanceLabel;
  final bool available;

  int? get documentCount {
    const keys = <String>[
      'document_count',
      'documents',
      'total_documents',
      'file_count',
    ];
    for (final key in keys) {
      final value = statistics[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
    }
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (id != null) 'id': id,
        'name': name,
        'is_default': isDefault,
        'statistics': statistics,
        if (metadata != null) 'metadata': metadata,
        if (status != null) 'status': status,
        if (progress != null) 'progress': progress,
        if (source != null) 'source': source,
        'assigned': assigned,
        'read_only': readOnly,
        if (provenanceLabel != null) 'provenance_label': provenanceLabel,
        'available': available,
      };

  static String? _optionalString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static Map<String, dynamic>? _stringMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
}
