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
    _registerRepository(getIt);
    if (getIt.isRegistered<InferenceService>()) {
      _registerEncoder(getIt);
    }
  }

  void _registerRepository(GetIt getIt) {
    getIt.registerSingleton<PropositionRepository>(PropositionRepository(
      adapter: getIt<PersistenceAdapter<Proposition>>(),
    ));
    getIt.registerSingleton<WorkingMemoryService>(WorkingMemoryService());
  }

  void _registerEncoder(GetIt getIt) {
    final inferenceService = getIt<InferenceService>();
    final decontextStage = DecontextualizeStage(
      chatClient: inferenceService,
    );
    getIt.registerSingleton<Encoder>(Encoder(
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
    ));
  }
}

class _PassthroughFilterRunner implements FilterRunner {
  @override
  Future<FilterPrediction> predict(String spanText) async =>
      FilterPrediction(extractScore: 1.0, skipScore: 0.0);
}
