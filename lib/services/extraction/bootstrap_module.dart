import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import '../../bootstrap/bootstrap_module.dart';
import '../../bootstrap.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../domain/atomic_insight.dart';
import '../../domain/atomic_insight_repository.dart';
import '../../domain/prompt_version.dart';
import '../../domain/prompt_version_repository.dart';
import '../embedding_service.dart';
import '../inference_service.dart';
import '../prompt/prompt_registry.dart';
import '../prompt/prompt_mutator.dart';
import '../prompt/prompt_validator.dart';
import 'atomic_insight_extractor.dart';
import '../../training/extraction/extraction_evaluator.dart';
import '../../training/extraction/extraction_improvement_loop.dart';

class ExtractionModule extends BootstrapModule {
  @override
  Future<void> register(GetIt getIt, EverythingStackConfig config) async {
    try {
      _registerRepositories(getIt);
      _registerPipeline(getIt);
    } catch (e) {
      debugPrint('⚠️ Extraction initialization failed: $e');
    }
  }

  void _registerRepositories(GetIt getIt) {
    final atomicInsightAdapter = getIt<PersistenceAdapter<AtomicInsight>>();
    final atomicInsightRepo = AtomicInsightRepository(
      adapter: atomicInsightAdapter,
      embeddingService: EmbeddingService.instance,
      embeddingQueueService: embeddingQueueService,
    );
    getIt.registerSingleton<AtomicInsightRepository>(atomicInsightRepo);

    final promptVersionAdapter = getIt<PersistenceAdapter<PromptVersion>>();
    final promptVersionRepo = PromptVersionRepository(
      adapter: promptVersionAdapter,
    );
    getIt.registerSingleton<PromptVersionRepository>(promptVersionRepo);

    debugPrint('✅ Extraction: repositories registered');
  }

  void _registerPipeline(GetIt getIt) {
    if (!getIt.isRegistered<InferenceService>()) {
      debugPrint('⏭️  Extraction pipeline skipped (no InferenceService)');
      return;
    }

    final inferenceService = getIt<InferenceService>();
    final promptVersionRepo = getIt<PromptVersionRepository>();
    final atomicInsightRepo = getIt<AtomicInsightRepository>();

    final promptRegistry = PromptRegistry(
      repo: promptVersionRepo,
      componentType: 'extraction_prompt',
      hardcodedDefault: AtomicInsightExtractor.defaultSystemPrompt,
    );
    getIt.registerSingleton<PromptRegistry>(promptRegistry);

    final extractor = AtomicInsightExtractor(
      insightRepo: atomicInsightRepo,
      inferenceService: inferenceService,
      promptRegistry: promptRegistry,
    );
    getIt.registerSingleton<AtomicInsightExtractor>(extractor);

    final evaluator = ExtractionEvaluator(
      inferenceService: inferenceService,
    );
    getIt.registerSingleton<ExtractionEvaluator>(evaluator);

    final improvementLoop = ExtractionImprovementLoop(
      extractor: extractor,
      evaluator: evaluator,
      promptRegistry: promptRegistry,
      mutator: PromptMutator(inferenceService: inferenceService),
      validator: PromptValidator(),
    );
    getIt.registerSingleton<ExtractionImprovementLoop>(improvementLoop);

    debugPrint('✅ Extraction: pipeline registered');
  }
}
