import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import '../../bootstrap/bootstrap_module.dart';
import '../../bootstrap.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../../domain/proposition.dart';
import '../../domain/proposition_repository.dart';
import '../inference_service.dart';
import '../../services/slm/runners/filter_runner.dart';
import 'working_memory_service.dart';
import 'encoder.dart';
import 'stages/normalize_stage.dart';
import 'stages/segment_stage.dart';
import 'stages/cohere_stage.dart';
import 'stages/recohere_stage.dart';
import 'stages/filter_stage.dart';
import 'stages/decontextualize_stage.dart';
import 'stages/dedup_stage.dart';

class MemoryModule extends BootstrapModule {
  @override
  Future<void> register(GetIt getIt, EverythingStackConfig config) async {
    try {
      _registerRepository(getIt);
      _registerEncoder(getIt);
    } catch (e) {
      debugPrint('⚠️ Memory system initialization failed: $e');
    }
  }

  void _registerRepository(GetIt getIt) {
    final propositionAdapter = getIt<PersistenceAdapter<Proposition>>();
    final propositionRepo = PropositionRepository(
      adapter: propositionAdapter,
    );
    getIt.registerSingleton<PropositionRepository>(propositionRepo);

    final wmService = WorkingMemoryService();
    getIt.registerSingleton<WorkingMemoryService>(wmService);
  }

  void _registerEncoder(GetIt getIt) {
    if (!getIt.isRegistered<InferenceService>()) {
      debugPrint('⏭️  Encoder skipped (no InferenceService)');
      return;
    }

    final inferenceService = getIt<InferenceService>();
    final decontextStage = DecontextualizeStage(
      chatClient: inferenceService,
    );
    final encoder = Encoder(
      normalizeStage: NormalizeStage(),
      segmentStage: SegmentStage(),
      cohereStage: CohereStage(chatClient: inferenceService),
      recoherStage: RecoherStage(),
      filterStage: FilterStage(filterRunner: _PassthroughFilterRunner()),
      decontextualizeStage: decontextStage,
      dedupStage: DedupStage(
        chatClient: inferenceService,
        decontextualizeStage: decontextStage,
      ),
    );
    getIt.registerSingleton<Encoder>(encoder);
    debugPrint('✅ Memory: Encoder + WorkingMemory registered');
  }
}

class _PassthroughFilterRunner implements FilterRunner {
  @override
  Future<FilterPrediction> predict(String spanText) async =>
      FilterPrediction(extractScore: 1.0, skipScore: 0.0);
}
