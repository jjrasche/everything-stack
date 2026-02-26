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
    _registerRepositories(getIt);
    if (getIt.isRegistered<InferenceService>()) {
      _registerPipeline(getIt);
    }
  }

  void _registerRepositories(GetIt getIt) {
    final atomicInsightRepo = AtomicInsightRepository(
      adapter: getIt<PersistenceAdapter<AtomicInsight>>(),
      embeddingService: EmbeddingService.instance,
      embeddingQueueService: embeddingQueueService,
    );
    getIt.registerSingleton<AtomicInsightRepository>(atomicInsightRepo);

    final promptVersionRepo = PromptVersionRepository(
      adapter: getIt<PersistenceAdapter<PromptVersion>>(),
    );
    getIt.registerSingleton<PromptVersionRepository>(promptVersionRepo);
  }

  void _registerPipeline(GetIt getIt) {
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

    getIt.registerSingleton<ExtractionImprovementLoop>(
      ExtractionImprovementLoop(
        extractor: extractor,
        evaluator: evaluator,
        promptRegistry: promptRegistry,
        mutator: PromptMutator(inferenceService: inferenceService),
        validator: PromptValidator(),
      ),
    );
  }
}
