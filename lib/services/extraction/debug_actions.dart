import 'package:get_it/get_it.dart';
import '../../core/invocation_repository.dart';
import '../../core/invocation.dart';
import '../debug/debug_server.dart';
import 'atomic_insight_extractor.dart';

void registerExtractionDebugActions(DebugServer server, GetIt getIt) {
  server.registerAction('extractInsights', (params) async {
    final convUuid = params['uuid'];
    if (convUuid == null || convUuid.isEmpty) {
      return {
        'error': 'Missing uuid parameter',
        'hint': 'Use ?uuid=<conversation-uuid>',
      };
    }

    try {
      final extractor = getIt<AtomicInsightExtractor>();
      final repo = getIt<InvocationRepository<Invocation>>();
      final all = await repo.findAll();

      final turns = all
          .where((inv) =>
              inv.implementer == 'claude_import' &&
              inv.metadata?['sourceConversationUuid'] == convUuid)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      if (turns.isEmpty) {
        return {'error': 'Conversation not found', 'uuid': convUuid};
      }

      final turnMaps = turns.map((inv) => {
        'prompt': inv.input?['prompt'] ?? '',
        'response': inv.output?['response'] ?? '',
      }).toList();

      final batchSize = params['batchSize'] != null
          ? int.tryParse(params['batchSize']!) ?? 5
          : 5;

      final insights = await extractor.extractFromConversation(
        turns: turnMaps,
        batchSize: batchSize,
      );

      return {
        'success': true,
        'conversationUuid': convUuid,
        'conversationName':
            turns.first.metadata?['sourceConversationName'] ?? 'Unnamed',
        'turnsProcessed': turns.length,
        'insightsExtracted': insights.length,
        'insights': insights.map((i) => {
          'uuid': i.uuid,
          'content': i.content,
          'scope': i.scope,
          'type': i.type,
          'hasEmbedding': i.embedding != null,
        }).toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });
}
