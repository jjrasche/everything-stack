/// CLI bootstrap for extraction pipeline scripts.
///
/// Builds on shared_bootstrap.dart, adding AtomicInsight-specific
/// wiring for extraction, evaluation, and prompt improvement.
///
/// Usage:
///   import 'script_bootstrap.dart';
///   final pipeline = await initializeExtractionPipeline();
///   try { ... } finally { pipeline.dispose(); }

import 'package:objectbox/objectbox.dart';

import '../lib/persistence/objectbox/atomic_insight_objectbox_adapter.dart';
import '../lib/persistence/objectbox/prompt_version_objectbox_adapter.dart';

import '../lib/services/inference_service.dart';
import '../lib/services/embedding_service.dart';
import '../lib/services/extraction/atomic_insight_extractor.dart';
import '../lib/training/extraction/extraction_evaluator.dart';
import '../lib/training/extraction/extraction_improvement_loop.dart';
import '../lib/services/prompt/prompt_registry.dart';
import '../lib/services/prompt/prompt_mutator.dart';
import '../lib/services/prompt/prompt_validator.dart';

import '../lib/domain/atomic_insight_repository.dart';
import '../lib/domain/prompt_version_repository.dart';

export 'shared_bootstrap.dart';

// ============ Typed Containers ============

/// All wired services needed by extraction pipeline scripts.
/// Avoids GetIt dependency for CLI tools.
class ExtractionPipeline {
  final Store store;
  final InferenceService inferenceService;
  final AtomicInsightRepository insightRepo;
  final PromptVersionRepository promptVersionRepo;
  final PromptRegistry promptRegistry;
  final AtomicInsightExtractor extractor;
  final ExtractionEvaluator evaluator;
  final PromptMutator mutator;
  final PromptValidator validator;
  final ExtractionImprovementLoop improvementLoop;

  ExtractionPipeline({
    required this.store,
    required this.inferenceService,
    required this.insightRepo,
    required this.promptVersionRepo,
    required this.promptRegistry,
    required this.extractor,
    required this.evaluator,
    required this.mutator,
    required this.validator,
    required this.improvementLoop,
  });

  void dispose() {
    store.close();
  }
}

// ============ Orchestrator ============

/// Initialize extraction pipeline for CLI scripts.
///
/// Loads .env, opens ObjectBox, wires all services.
/// Caller MUST call pipeline.dispose() in a finally block.
Future<ExtractionPipeline> initializeExtractionPipeline() async {
  printProductionWarning();
  await loadEnvironment();
  final store = await openScriptStore();
  final inferenceService = createInferenceService(store);
  return wireExtractionPipeline(store, inferenceService);
}

// ============ Concept Functions ============

void printProductionWarning() {
  print('');
  print('WARNING: Writing insights to production ObjectBox store.');
  print('         Extracted insights will persist in your database.');
  print('');
}

ExtractionPipeline wireExtractionPipeline(
  Store store,
  InferenceService inferenceService,
) {
  // NullEmbeddingService disables semantic dedup intentionally.
  // Golden evaluation needs ALL extractions, not filtered against
  // production data. When extractFromConversation gains a skipDedup
  // param, switch to that instead.
  final insightRepo = AtomicInsightRepository(
    adapter: AtomicInsightObjectBoxAdapter(store),
    embeddingService: NullEmbeddingService(),
  );

  final promptVersionRepo = PromptVersionRepository(
    adapter: PromptVersionObjectBoxAdapter(store),
    embeddingService: NullEmbeddingService(),
  );

  final promptRegistry = PromptRegistry(
    repo: promptVersionRepo,
    componentType: 'extraction_prompt',
    hardcodedDefault: AtomicInsightExtractor.defaultSystemPrompt,
  );

  final extractor = AtomicInsightExtractor(
    insightRepo: insightRepo,
    inferenceService: inferenceService,
    promptRegistry: promptRegistry,
  );

  final evaluator = ExtractionEvaluator(
    inferenceService: inferenceService,
  );

  final mutator = PromptMutator(
    inferenceService: inferenceService,
  );

  final validator = PromptValidator();

  final improvementLoop = ExtractionImprovementLoop(
    extractor: extractor,
    evaluator: evaluator,
    promptRegistry: promptRegistry,
    mutator: mutator,
    validator: validator,
  );

  return ExtractionPipeline(
    store: store,
    inferenceService: inferenceService,
    insightRepo: insightRepo,
    promptVersionRepo: promptVersionRepo,
    promptRegistry: promptRegistry,
    extractor: extractor,
    evaluator: evaluator,
    mutator: mutator,
    validator: validator,
    improvementLoop: improvementLoop,
  );
}
