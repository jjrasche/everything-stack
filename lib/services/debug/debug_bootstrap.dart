import 'package:get_it/get_it.dart';
import 'debug_server.dart';
import 'screenshot_service.dart';
import 'vlm_analyzer.dart';
import 'ui_interaction_schema.dart';
import '../semantic_search/semantic_search_service.dart';
import '../chunking_service.dart';
import '../hnsw_index.dart';
import '../../core/entity_repository.dart';
import '../../core/invocation_repository.dart';
import '../../core/invocation.dart';
import '../../core/debug/debug.dart';
import '../../tools/import/claude_import_tool.dart';
import '../extraction/atomic_insight_extractor.dart';
import '../extraction/extraction_evaluator.dart';
import '../extraction/extraction_improvement_loop.dart';
import '../prompt/prompt_registry.dart';
import '../../domain/atomic_insight_repository.dart';
import 'ui_automation_service.dart';

Future<void> initializeDebugInfrastructure() async {
  print('🔧 [Debug] Initializing debug infrastructure...');

  final server = DebugServer.instance;
  final getIt = GetIt.instance;
  final registry = DebugRegistry.instance;

  // Initialize VLM analyzer if API key is available
  _initializeVlmAnalyzer();

  // Register introspectable components with central registry
  _registerIntrospectableComponents(registry, getIt);

  // Register state providers (mix of registry + manual)
  _registerStateProviders(server, getIt, registry);

  // Register actions (mix of registry + manual)
  _registerActions(server, getIt, registry);

  // Set screenshot callback
  server.setScreenshotCallback(() async {
    return await ScreenshotService.instance.capture(context: 'debug-request');
  });

  // Start server
  await server.start(port: 9999);

  print('✅ [Debug] Debug infrastructure ready');
  print('   📡 Debug server: http://localhost:9999');
  print('   📸 Screenshots: logs/screenshots/');
  print('   📊 State file: logs/debug-state.json');
  print('   🔍 Registered components: ${registry.componentNames}');
  print('   👁️ VLM analyzer: ${VlmAnalyzer.instance.isConfigured ? 'configured' : 'not configured (set ANTHROPIC_API_KEY)'}');
}

/// Initialize VLM analyzer from dotenv/environment variables
void _initializeVlmAnalyzer() {
  VlmAnalyzer.instance.autoInitialize();

  if (VlmAnalyzer.instance.isConfigured) {
    print('   👁️ VLM: Configured and ready for visual debugging');
  } else {
    print('   ⚠️ VLM: No API key found (set ANTHROPIC_API_KEY or OPENAI_API_KEY in .env for visual debugging)');
  }
}

/// Register components that implement DebugIntrospectable with the central registry.
/// As more components adopt the mixin, add them here.
void _registerIntrospectableComponents(DebugRegistry registry, GetIt getIt) {
  try {
    final chunking = getIt<ChunkingService>();
    registry.register(chunking);
    print('   ✓ Registered: ${chunking.debugName}');
  } catch (e) {
    print('   ⚠️ ChunkingService not available for debug registration');
  }

  try {
    final extractor = getIt<AtomicInsightExtractor>();
    registry.register(extractor);
    print('   ✓ Registered: ${extractor.debugName}');
  } catch (e) {
    print('   ⚠️ AtomicInsightExtractor not available for debug registration');
  }

  try {
    final evaluator = getIt<ExtractionEvaluator>();
    registry.register(evaluator);
    print('   ✓ Registered: ${evaluator.debugName}');
  } catch (e) {
    print('   ⚠️ ExtractionEvaluator not available for debug registration');
  }

  try {
    final promptRegistry = getIt<PromptRegistry>();
    registry.register(promptRegistry);
    print('   ✓ Registered: ${promptRegistry.debugName}');
  } catch (e) {
    print('   ⚠️ PromptRegistry not available for debug registration');
  }

  try {
    final improvementLoop = getIt<ExtractionImprovementLoop>();
    registry.register(improvementLoop);
    print('   ✓ Registered: ${improvementLoop.debugName}');
  } catch (e) {
    print('   ⚠️ ExtractionImprovementLoop not available for debug registration');
  }

}

void _registerStateProviders(DebugServer server, GetIt getIt, DebugRegistry registry) {
  // Register state from DebugRegistry (components with DebugIntrospectable)
  // This auto-discovers state from all registered components
  server.registerStateProvider('_registry', () {
    return registry.getAllState();
  });

  // HNSW Index state (standalone, not introspectable yet)
  server.registerStateProvider('hnswIndex', () {
    try {
      final index = getIt<HnswIndex>();
      return {
        'size': index.size,
        'dimensions': 384, // Jina embeddings
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  // Chunking service state - now uses registry via DebugIntrospectable
  // Kept here for backwards compatibility, but delegates to registry
  server.registerStateProvider('chunking', () {
    return registry.getState('chunking') ?? {'error': 'not registered'};
  });

  // Semantic search state (not introspectable yet)
  server.registerStateProvider('semanticSearch', () {
    try {
      final search = getIt<SemanticSearchService>();
      return {
        'indexSize': search.index.size,
        'entityLoaderType': search.entityLoader.runtimeType.toString(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  // Recent screenshots
  server.registerStateProvider('screenshots', () {
    return {'note': 'Use /screenshot endpoint to capture'};
  });
}

/// Helper to safely truncate string with ellipsis
String _truncate(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength)}...';
}

void _registerActions(DebugServer server, GetIt getIt, DebugRegistry registry) {
  // Registry-based action invocation (for components with DebugIntrospectable)
  // Format: /action/component.actionName (e.g., /action/chunking.rebuild)
  server.registerAction('invoke', (params) async {
    final target = params['target'];
    if (target == null || !target.contains('.')) {
      return {
        'error': 'Missing target. Format: component.action',
        'available': registry.getAllActions(),
      };
    }

    final parts = target.split('.');
    final componentName = parts[0];
    final actionName = parts[1];

    final result = await registry.invokeAction(componentName, actionName, params);
    return result ?? {'error': 'Unknown component or action'};
  });

  // List all available actions from registry
  server.registerAction('listActions', (params) async {
    return {
      'components': registry.componentNames,
      'actions': registry.getAllActions(),
    };
  });

  // Search action
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

  // Get entity action
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

  // Get chunks action
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

      // No entityId - return stats
      return {
        'indexSize': chunking.index.size,
        'isConsistent': chunking.isIndexConsistent(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  // Capture screenshot action
  server.registerAction('captureScreenshot', (params) async {
    final context = params['context'] ?? 'action-request';
    final path = await ScreenshotService.instance.capture(context: context);
    return {
      'success': path != null,
      'path': path,
      'timestamp': DateTime.now().toIso8601String(),
    };
  });

  // List screenshots action
  server.registerAction('listScreenshots', (params) async {
    final limit = int.tryParse(params['limit'] ?? '10') ?? 10;
    final screenshots = await ScreenshotService.instance.getRecentScreenshots(limit: limit);
    return {
      'count': screenshots.length,
      'screenshots': screenshots,
    };
  });

  // Analyze screenshot with VLM (visual debugging)
  server.registerAction('analyzeScreenshot', (params) async {
    if (!VlmAnalyzer.instance.isConfigured) {
      return {
        'error': 'VLM not configured',
        'hint': 'Set ANTHROPIC_API_KEY or OPENAI_API_KEY environment variable',
      };
    }

    // Get image path - either specified or capture new
    String? imagePath = params['path'];
    if (imagePath == null || imagePath.isEmpty) {
      // Capture fresh screenshot
      imagePath = await ScreenshotService.instance.capture(context: 'vlm-analysis');
      if (imagePath == null) {
        return {'error': 'Failed to capture screenshot'};
      }
    }

    // Get prompt - use default if not specified
    final prompt = params['prompt'] ??
        'Describe this UI screenshot. Focus on: 1) What screen/state is shown, 2) Any error messages or warnings, 3) Data being displayed, 4) Any UI issues or unexpected states.';

    final analysis = await VlmAnalyzer.instance.analyzeScreenshot(
      imagePath: imagePath,
      prompt: prompt,
    );

    return {
      'imagePath': imagePath,
      'prompt': prompt,
      'analysis': analysis,
      'timestamp': DateTime.now().toIso8601String(),
    };
  });

  // Structured VLM analysis with interaction schema
  server.registerAction('analyzeStructured', (params) async {
    if (!VlmAnalyzer.instance.isConfigured) {
      return {
        'error': 'VLM not configured',
        'hint': 'Set ANTHROPIC_API_KEY or OPENAI_API_KEY environment variable',
      };
    }

    final screenName = params['screen'] ?? 'voice_assistant';
    final schema = UiInteractionSchema.forScreen(screenName);
    if (schema == null) {
      return {
        'error': 'Unknown screen: $screenName',
        'availableScreens': UiInteractionSchema.knownScreens,
      };
    }

    // Get image path - either specified or capture new
    String? imagePath = params['path'];
    if (imagePath == null || imagePath.isEmpty) {
      imagePath = await ScreenshotService.instance.capture(context: 'structured-analysis');
      if (imagePath == null) {
        return {'error': 'Failed to capture screenshot'};
      }
    }

    final query = params['query'] ?? 'What is the current state?';

    try {
      final result = await schema.analyzeWithVlm(
        vlm: VlmAnalyzer.instance,
        screenshotPath: imagePath,
        query: query,
      );

      return {
        'success': true,
        'imagePath': imagePath,
        'screen': result.screenIdentified,
        'state': result.screenState,
        'data': result.data,
        'availableActions': result.availableActions,
        'errors': result.errors,
        'warnings': result.warnings,
        'hasErrors': result.hasErrors,
        'canInteract': result.canInteract,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  // Count invocations action
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

  // Find orphaned chunks (chunks whose source entities don't exist)
  server.registerAction('findOrphanedChunks', (params) async {
    try {
      final chunking = getIt<ChunkingService>();
      final repo = getIt<InvocationRepository<Invocation>>();

      // Get all chunks
      final allChunks = await chunking.getAllChunks();

      // Check which have missing entities
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
              'textPreview': chunk.text.length > 50 ? '${chunk.text.substring(0, 50)}...' : chunk.text,
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

  // Delete orphaned chunks
  server.registerAction('deleteOrphanedChunks', (params) async {
    try {
      final chunking = getIt<ChunkingService>();
      final repo = getIt<InvocationRepository<Invocation>>();

      // Get all chunks
      final allChunks = await chunking.getAllChunks();

      // Find orphaned entity IDs
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

      // Delete chunks for orphaned entities
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

  // Rebuild HNSW index from database (without app restart)
  server.registerAction('rebuildIndex', (params) async {
    try {
      final chunking = getIt<ChunkingService>();
      final stopwatch = Stopwatch()..start();

      // Clear in-memory index and reload from database
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

  // Query imported Claude invocations
  server.registerAction('queryImportedInvocations', (params) async {
    try {
      final repo = getIt<InvocationRepository<Invocation>>();
      final all = await repo.findAll();

      // Filter for claude_import implementer
      final imported = all.where((inv) => inv.implementer == 'claude_import').toList();

      final limit = params['limit'] != null ? int.tryParse(params['limit']!) ?? 10 : 10;
      final offset = params['offset'] != null ? int.tryParse(params['offset']!) ?? 0 : 0;

      final page = imported.skip(offset).take(limit).toList();

      return {
        'total': imported.length,
        'offset': offset,
        'limit': limit,
        'results': page.map((inv) => {
          'uuid': inv.uuid,
          'eventId': inv.eventId,
          'createdAt': inv.createdAt.toIso8601String(),
          'componentType': inv.componentType,
          'implementer': inv.implementer,
          'input': {
            'prompt': (inv.input?['prompt'] as String?)?.substring(
              0,
              ((inv.input?['prompt'] as String?)?.length ?? 0) > 100 ? 100 : (inv.input?['prompt'] as String?)?.length ?? 0
            ),
          },
          'output': {
            'response': (inv.output?['response'] as String?)?.substring(
              0,
              ((inv.output?['response'] as String?)?.length ?? 0) > 100 ? 100 : (inv.output?['response'] as String?)?.length ?? 0
            ),
          },
        }).toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  // Import Claude conversations
  server.registerAction('importClaude', (params) async {
    final path = params['path'];
    if (path == null || path.isEmpty) {
      return {
        'error': 'Missing path parameter',
        'hint': 'Use ?path=/path/to/conversations.json',
      };
    }

    try {
      final repo = getIt<EntityRepository<Invocation>>();
      final importer = ClaudeImportTool(invocationRepo: repo);

      final limit = params['limit'] != null ? int.tryParse(params['limit']!) : null;

      final result = await importer.importFromExport(
        conversationsPath: path,
        limit: limit,
        skipExisting: true,
      );

      return {
        'success': true,
        'conversations': result.conversations,
        'imported': result.imported,
        'skipped': result.skipped,
        'errors': result.errors.take(10).toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  // List imported conversations (grouped by conversation UUID)
  server.registerAction('listConversations', (params) async {
    try {
      final repo = getIt<InvocationRepository<Invocation>>();
      final all = await repo.findAll();

      // Filter for claude_import
      final imported = all.where((inv) => inv.implementer == 'claude_import').toList();

      // Group by conversation UUID
      final Map<String, List<Invocation>> byConversation = {};
      for (final inv in imported) {
        final convUuid = inv.metadata?['sourceConversationUuid'] as String?;
        if (convUuid != null) {
          byConversation.putIfAbsent(convUuid, () => []).add(inv);
        }
      }

      // Sort conversations by first turn date (most recent first)
      final conversations = byConversation.entries.toList()
        ..sort((a, b) {
          final aFirst = a.value.map((inv) => inv.createdAt).reduce((a, b) => a.isBefore(b) ? a : b);
          final bFirst = b.value.map((inv) => inv.createdAt).reduce((a, b) => a.isBefore(b) ? a : b);
          return bFirst.compareTo(aFirst); // Most recent first
        });

      final limit = params['limit'] != null ? int.tryParse(params['limit']!) ?? 20 : 20;
      final offset = params['offset'] != null ? int.tryParse(params['offset']!) ?? 0 : 0;

      final page = conversations.skip(offset).take(limit).toList();

      return {
        'total': conversations.length,
        'offset': offset,
        'limit': limit,
        'conversations': page.map((entry) {
          final turns = entry.value..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          final first = turns.first;
          final last = turns.last;
          final firstPrompt = first.input?['prompt'] as String? ?? '';
          final lastResponse = last.output?['response'] as String? ?? '';

          return {
            'uuid': entry.key,
            'name': first.metadata?['sourceConversationName'] ?? 'Unnamed',
            'turnCount': turns.length,
            'firstTurnDate': first.createdAt.toIso8601String(),
            'lastTurnDate': last.createdAt.toIso8601String(),
            'firstPromptPreview': _truncate(firstPrompt, 80),
            'lastResponsePreview': _truncate(lastResponse, 80),
          };
        }).toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  // Get full conversation with all turns
  server.registerAction('getConversation', (params) async {
    final convUuid = params['uuid'];
    if (convUuid == null || convUuid.isEmpty) {
      return {
        'error': 'Missing uuid parameter',
        'hint': 'Use ?uuid=<conversation-uuid>',
      };
    }

    try {
      final repo = getIt<InvocationRepository<Invocation>>();
      final all = await repo.findAll();

      // Filter for this conversation
      final turns = all
          .where((inv) =>
            inv.implementer == 'claude_import' &&
            inv.metadata?['sourceConversationUuid'] == convUuid)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      if (turns.isEmpty) {
        return {'error': 'Conversation not found', 'uuid': convUuid};
      }

      // Estimate tokens (rough: 1 token ≈ 4 chars)
      int totalChars = 0;
      for (final turn in turns) {
        totalChars += (turn.input?['prompt'] as String?)?.length ?? 0;
        totalChars += (turn.output?['response'] as String?)?.length ?? 0;
      }
      final estimatedTokens = (totalChars / 4).round();

      return {
        'uuid': convUuid,
        'name': turns.first.metadata?['sourceConversationName'] ?? 'Unnamed',
        'turnCount': turns.length,
        'estimatedTokens': estimatedTokens,
        'firstTurnDate': turns.first.createdAt.toIso8601String(),
        'lastTurnDate': turns.last.createdAt.toIso8601String(),
        'turns': turns.map((inv) => {
          'uuid': inv.uuid,
          'createdAt': inv.createdAt.toIso8601String(),
          'prompt': inv.input?['prompt'],
          'response': inv.output?['response'],
        }).toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  // Export conversation as golden test data template
  server.registerAction('exportConversationForTest', (params) async {
    final convUuid = params['uuid'];
    if (convUuid == null || convUuid.isEmpty) {
      return {
        'error': 'Missing uuid parameter',
        'hint': 'Use ?uuid=<conversation-uuid>',
      };
    }

    try {
      final repo = getIt<InvocationRepository<Invocation>>();
      final all = await repo.findAll();

      // Filter for this conversation
      final turns = all
          .where((inv) =>
            inv.implementer == 'claude_import' &&
            inv.metadata?['sourceConversationUuid'] == convUuid)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      if (turns.isEmpty) {
        return {'error': 'Conversation not found', 'uuid': convUuid};
      }

      // Format for golden test data
      return {
        'id': 'conv_${convUuid.substring(0, 8)}',
        'description': 'TODO: Add description of what makes this conversation interesting',
        'conversation': {
          'uuid': convUuid,
          'name': turns.first.metadata?['sourceConversationName'] ?? 'Unnamed',
          'turn_count': turns.length,
          'first_turn_date': turns.first.createdAt.toIso8601String(),
          'last_turn_date': turns.last.createdAt.toIso8601String(),
          'turns': turns.asMap().entries.map((entry) {
            final idx = entry.key;
            final inv = entry.value;
            return {
              'turn_index': idx,
              'uuid': inv.uuid,
              'created_at': inv.createdAt.toIso8601String(),
              'prompt': inv.input?['prompt'],
              'response': inv.output?['response'],
            };
          }).toList(),
        },
        'expected_insights': [
          {
            'content': 'TODO: [Fact]. Because [reason].',
            'source_turns': [0],
            'notes': 'Add expected insights to extract from this conversation',
          }
        ],
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  // Extract atomic insights from a specific imported conversation
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

      // Get conversation turns
      final turns = all
          .where((inv) =>
            inv.implementer == 'claude_import' &&
            inv.metadata?['sourceConversationUuid'] == convUuid)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      if (turns.isEmpty) {
        return {'error': 'Conversation not found', 'uuid': convUuid};
      }

      // Convert to prompt/response pairs
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
        'conversationName': turns.first.metadata?['sourceConversationName'] ?? 'Unnamed',
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

  // Analyze conversations for test selection
  server.registerAction('analyzeConversationsForTests', (params) async {
    try {
      final repo = getIt<InvocationRepository<Invocation>>();
      final all = await repo.findAll();

      // Filter for claude_import
      final imported = all.where((inv) => inv.implementer == 'claude_import').toList();

      // Group by conversation UUID
      final Map<String, List<Invocation>> byConversation = {};
      for (final inv in imported) {
        final convUuid = inv.metadata?['sourceConversationUuid'] as String?;
        if (convUuid != null) {
          byConversation.putIfAbsent(convUuid, () => []).add(inv);
        }
      }

      // Score each conversation for test suitability
      final scored = byConversation.entries.map((entry) {
        final turns = entry.value..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        // Calculate metrics
        final turnCount = turns.length;
        int totalChars = 0;
        int technicalWords = 0;

        for (final turn in turns) {
          final prompt = turn.input?['prompt'] as String? ?? '';
          final response = turn.output?['response'] as String? ?? '';
          totalChars += prompt.length + response.length;

          // Count technical indicators
          final text = '$prompt $response'.toLowerCase();
          if (text.contains(RegExp(r'\b(function|class|api|database|service|component|implement|algorithm|pattern|architecture)\b'))) {
            technicalWords++;
          }
        }

        final avgCharsPerTurn = totalChars / turnCount;
        final estimatedTokens = (totalChars / 4).round();

        // Scoring:
        // - Multi-turn: 3+ turns (good), 5+ turns (excellent)
        // - Length: 200-1000 chars/turn (good range)
        // - Technical: more technical words = higher score
        double score = 0;

        if (turnCount >= 3) score += 30;
        if (turnCount >= 5) score += 20;
        if (avgCharsPerTurn >= 200 && avgCharsPerTurn <= 1000) score += 30;
        score += (technicalWords / turnCount) * 20; // Technical density

        final firstPrompt = turns.first.input?['prompt'] as String? ?? '';

        return {
          'uuid': entry.key,
          'name': turns.first.metadata?['sourceConversationName'] ?? 'Unnamed',
          'turnCount': turnCount,
          'estimatedTokens': estimatedTokens,
          'avgCharsPerTurn': avgCharsPerTurn.round(),
          'technicalDensity': (technicalWords / turnCount * 100).round(),
          'score': score.round(),
          'firstPrompt': _truncate(firstPrompt, 100),
        };
      }).toList()
        ..sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

      final limit = params['limit'] != null ? int.tryParse(params['limit']!) ?? 10 : 10;

      return {
        'total': scored.length,
        'criteria': {
          'turnCount': '3+ turns preferred, 5+ excellent',
          'avgLength': '200-1000 chars/turn ideal',
          'technical': 'Higher density of technical terms better',
        },
        'topCandidates': scored.take(limit).toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  // ── UI Automation Endpoints ──

  final uiAuto = UiAutomationService.instance;

  // Tap a widget by semantics label
  server.registerAction('ui/tap', (params) async {
    final target = params['target'];
    if (target == null || target.isEmpty) {
      return {'error': 'Missing target parameter', 'hint': 'Use ?target=chat_panel.mic_button'};
    }
    return await uiAuto.tap(target);
  });

  // Long-press a widget by semantics label
  server.registerAction('ui/long_press', (params) async {
    final target = params['target'];
    if (target == null || target.isEmpty) {
      return {'error': 'Missing target parameter'};
    }
    return await uiAuto.longPress(target);
  });

  // Type text into a text field by semantics label
  server.registerAction('ui/type', (params) async {
    final target = params['target'];
    final text = params['text'];
    if (target == null || target.isEmpty) {
      return {'error': 'Missing target parameter'};
    }
    if (text == null) {
      return {'error': 'Missing text parameter'};
    }
    final submit = params['submit']?.toLowerCase() == 'true';
    return await uiAuto.type(target, text, submit: submit);
  });

  // Slide a slider to a value
  server.registerAction('ui/slide', (params) async {
    final target = params['target'];
    final valueStr = params['value'];
    if (target == null || target.isEmpty) {
      return {'error': 'Missing target parameter'};
    }
    if (valueStr == null) {
      return {'error': 'Missing value parameter (0.0-1.0)'};
    }
    final value = double.tryParse(valueStr);
    if (value == null) {
      return {'error': 'Invalid value: $valueStr (expected 0.0-1.0)'};
    }
    return await uiAuto.slide(target, value);
  });

  // Get full semantics tree
  server.registerAction('ui/tree', (params) async {
    return uiAuto.getTree();
  });

  // Find widgets by label prefix
  server.registerAction('ui/find', (params) async {
    final label = params['label'] ?? '';
    final results = uiAuto.find(label);
    return {
      'query': label,
      'count': results.length,
      'widgets': results,
    };
  });
}
