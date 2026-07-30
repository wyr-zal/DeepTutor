import 'package:dio/dio.dart';

import '../models/knowledge_base.dart';

typedef KnowledgeJsonLoader = Future<Object?> Function(String path);

abstract interface class KnowledgeRepository {
  Future<List<KnowledgeBase>> listKnowledgeBases();
}

class KnowledgeApi implements KnowledgeRepository {
  KnowledgeApi({required KnowledgeJsonLoader loadJson}) : _loadJson = loadJson;

  factory KnowledgeApi.fromDio(Dio dio, {String baseUrl = ''}) {
    return KnowledgeApi(
      loadJson: (path) async {
        final response = await dio.get<Object?>(_resolve(baseUrl, path));
        return response.data;
      },
    );
  }

  static const listPath = '/api/v1/knowledge/list';

  final KnowledgeJsonLoader _loadJson;

  @override
  Future<List<KnowledgeBase>> listKnowledgeBases() async {
    final payload = await _loadJson(listPath);
    if (payload is! List) {
      throw const FormatException(
        'Knowledge list response must be a JSON array.',
      );
    }

    final items = <KnowledgeBase>[];
    for (final item in payload) {
      if (item is! Map) {
        throw const FormatException('Knowledge list contains an invalid item.');
      }
      items.add(
        KnowledgeBase.fromJson(
          item.map((key, value) => MapEntry(key.toString(), value)),
        ),
      );
    }
    return List<KnowledgeBase>.unmodifiable(items);
  }

  static String _resolve(String baseUrl, String path) {
    final base = baseUrl.trim();
    if (base.isEmpty) return path;
    return '${base.replaceFirst(RegExp(r'/+$'), '')}/${path.replaceFirst(RegExp(r'^/+'), '')}';
  }
}
