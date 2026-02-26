import 'package:get_it/get_it.dart';
import 'debug_server.dart';
import 'screenshot_service.dart';
import 'vlm_analyzer.dart';
import '../chunking_service.dart';
import '../hnsw_index.dart';
import '../semantic_search/semantic_search_service.dart';
import '../extraction/atomic_insight_extractor.dart';
import '../../training/extraction/extraction_evaluator.dart';
import '../../training/extraction/extraction_improvement_loop.dart';
import '../prompt/prompt_registry.dart';
import '../../core/debug/debug.dart';
import 'actions/registry_actions.dart';
import 'actions/screenshot_actions.dart';
import 'actions/event_injection_actions.dart';
import 'actions/ui_automation_actions.dart';
import '../semantic_search/debug_actions.dart';
import '../chunking/debug_actions.dart';
import '../extraction/debug_actions.dart';
import '../../tools/import/debug_actions.dart';

Future<void> initializeDebugInfrastructure() async {
  print('🔧 [Debug] Initializing debug infrastructure...');

  final server = DebugServer.instance;
  final getIt = GetIt.instance;
  final registry = DebugRegistry.instance;

  _initializeVlm();
  _registerIntrospectables(registry, getIt);
  _registerStateProviders(server, getIt, registry);

  registerRegistryActions(server, registry);
  registerScreenshotActions(server, getIt);
  registerEventInjectionActions(server, getIt);
  registerUiAutomationActions(server);
  registerSearchDebugActions(server, getIt);
  registerChunkDebugActions(server, getIt);
  registerExtractionDebugActions(server, getIt);
  registerConversationDebugActions(server, getIt);

  server.setScreenshotCallback(() async {
    return await ScreenshotService.instance.capture(context: 'debug-request');
  });

  await server.start(port: 9999);

  print('✅ [Debug] Debug infrastructure ready on http://localhost:9999');
}

void _initializeVlm() {
  VlmAnalyzer.instance.autoInitialize();
}

void _registerIntrospectables(DebugRegistry registry, GetIt getIt) {
  final registrations = <String, Object? Function()>{
    'ChunkingService': () => _tryGet<ChunkingService>(getIt),
    'AtomicInsightExtractor': () => _tryGet<AtomicInsightExtractor>(getIt),
    'ExtractionEvaluator': () => _tryGet<ExtractionEvaluator>(getIt),
    'PromptRegistry': () => _tryGet<PromptRegistry>(getIt),
    'ExtractionImprovementLoop': () => _tryGet<ExtractionImprovementLoop>(getIt),
  };

  for (final entry in registrations.entries) {
    final component = entry.value();
    if (component is DebugIntrospectable) {
      registry.register(component);
    }
  }
}

T? _tryGet<T extends Object>(GetIt getIt) {
  try {
    return getIt<T>();
  } catch (_) {
    return null;
  }
}

void _registerStateProviders(
  DebugServer server,
  GetIt getIt,
  DebugRegistry registry,
) {
  server.registerStateProvider('_registry', () => registry.getAllState());

  server.registerStateProvider('hnswIndex', () {
    try {
      final index = getIt<HnswIndex>();
      return {'size': index.size, 'dimensions': 384};
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  server.registerStateProvider('chunking', () {
    return registry.getState('chunking') ?? {'error': 'not registered'};
  });

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
}
