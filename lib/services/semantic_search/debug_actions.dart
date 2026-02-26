import 'package:get_it/get_it.dart';
import 'semantic_search_service.dart';
import '../../core/invocation_repository.dart';
import '../../core/invocation.dart';
import '../debug/debug_server.dart';

void registerSearchDebugActions(DebugServer server, GetIt getIt) {
  server.registerAction('search', (params) async {
    final query = params['q'] ?? params['query'];
    if (query == null || query.isEmpty) {
      return {'error': 'Missing query'};
    }

    try {
      final searchService = getIt<SemanticSearchService>();
      final limit = int.tryParse(params['limit'] ?? '10') ?? 10;

      final stopwatch = Stopwatch()..start();
      final results = await searchService.search(query, limit: limit);
      stopwatch.stop();

      return {
        'query': query,
        'resultCount': results.length,
        'searchTimeMs': stopwatch.elapsedMilliseconds,
        'results': results.map((r) => {
          'chunkId': r.chunk.id,
          'sourceEntityId': r.chunk.sourceEntityId,
          'sourceEntityType': r.chunk.sourceEntityType,
          'similarity': r.similarity,
          'similarityPercent': '${(r.similarity * 100).toStringAsFixed(1)}%',
          'entityLoaded': r.sourceEntity != null,
          'chunkText': r.chunk.text.length > 200
              ? '${r.chunk.text.substring(0, 200)}...'
              : r.chunk.text,
        }).toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  server.registerAction('getEntity', (params) async {
    final uuid = params['uuid'];
    if (uuid == null || uuid.isEmpty) {
      return {'error': 'Missing uuid'};
    }

    try {
      final repo = getIt<InvocationRepository<Invocation>>();
      final entity = await repo.findById(uuid);

      if (entity == null) {
        return {'error': 'Entity not found', 'uuid': uuid};
      }

      return {
        'uuid': entity.uuid,
        'type': entity.runtimeType.toString(),
        'componentType': entity.componentType,
        'success': entity.success,
        'createdAt': entity.createdAt.toIso8601String(),
        'input': entity.input,
        'output': entity.output,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  server.registerAction('countInvocations', (params) async {
    try {
      final repo = getIt<InvocationRepository<Invocation>>();
      final all = await repo.findAll();
      return {
        'count': all.length,
        'sample': all.take(5).map((inv) => {
          'uuid': inv.uuid,
          'componentType': inv.componentType,
          'createdAt': inv.createdAt.toIso8601String(),
        }).toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });
}
