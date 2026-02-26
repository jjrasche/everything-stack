import 'package:get_it/get_it.dart';
import '../chunking_service.dart';
import '../../core/invocation_repository.dart';
import '../../core/invocation.dart';
import '../debug/debug_server.dart';

String _truncate(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength)}...';
}

void registerChunkDebugActions(DebugServer server, GetIt getIt) {
  server.registerAction('getChunks', (params) async {
    final entityId = params['entityId'];

    try {
      final chunking = getIt<ChunkingService>();

      if (entityId != null && entityId.isNotEmpty) {
        final chunks = await chunking.getChunksForEntity(entityId);
        return {
          'entityId': entityId,
          'chunkCount': chunks.length,
          'chunks': chunks.map((c) => {
            'id': c.id,
            'config': c.config,
            'tokenRange': '${c.startToken}-${c.endToken}',
            'hasEmbedding': c.embedding != null,
            'textPreview': _truncate(c.text, 100),
          }).toList(),
        };
      }

      return {
        'indexSize': chunking.index.size,
        'isConsistent': chunking.isIndexConsistent(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  server.registerAction('findOrphanedChunks', (params) async {
    try {
      final chunking = getIt<ChunkingService>();
      final repo = getIt<InvocationRepository<Invocation>>();

      final allChunks = await chunking.getAllChunks();

      int orphanCount = 0;
      final orphanSamples = <Map<String, dynamic>>[];
      final seenEntityIds = <String>{};

      for (final chunk in allChunks) {
        if (seenEntityIds.contains(chunk.sourceEntityId)) continue;
        seenEntityIds.add(chunk.sourceEntityId);

        final entity = await repo.findById(chunk.sourceEntityId);
        if (entity == null) {
          orphanCount++;
          if (orphanSamples.length < 10) {
            orphanSamples.add({
              'chunkId': chunk.id,
              'sourceEntityId': chunk.sourceEntityId,
              'sourceEntityType': chunk.sourceEntityType,
              'textPreview': chunk.text.length > 50
                  ? '${chunk.text.substring(0, 50)}...'
                  : chunk.text,
            });
          }
        }
      }

      return {
        'totalChunks': allChunks.length,
        'uniqueEntityIds': seenEntityIds.length,
        'orphanedEntityIds': orphanCount,
        'orphanSamples': orphanSamples,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  server.registerAction('deleteOrphanedChunks', (params) async {
    try {
      final chunking = getIt<ChunkingService>();
      final repo = getIt<InvocationRepository<Invocation>>();

      final allChunks = await chunking.getAllChunks();

      final orphanedEntityIds = <String>{};
      final seenEntityIds = <String>{};

      for (final chunk in allChunks) {
        if (seenEntityIds.contains(chunk.sourceEntityId)) continue;
        seenEntityIds.add(chunk.sourceEntityId);

        final entity = await repo.findById(chunk.sourceEntityId);
        if (entity == null) {
          orphanedEntityIds.add(chunk.sourceEntityId);
        }
      }

      int deletedCount = 0;
      for (final entityId in orphanedEntityIds) {
        await chunking.deleteByEntityId(entityId);
        deletedCount++;
      }

      return {
        'deletedEntityIds': deletedCount,
        'remainingChunks': chunking.index.size,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  server.registerAction('rebuildIndex', (params) async {
    try {
      final chunking = getIt<ChunkingService>();
      final stopwatch = Stopwatch()..start();

      await chunking.rebuildIndexFromStorage();

      stopwatch.stop();
      return {
        'success': true,
        'indexSize': chunking.index.size,
        'rebuildTimeMs': stopwatch.elapsedMilliseconds,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });
}
