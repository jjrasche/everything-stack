import 'package:get_it/get_it.dart';
import 'bootstrap_module.dart';
import '../bootstrap.dart';
import '../core/invocation.dart';
import '../core/invocation_repository.dart';
import '../core/entity_repository.dart';
import '../core/event_repository.dart';
import '../services/embedding_service.dart';
import '../services/inference_service.dart';
import '../services/tts_service.dart';
import '../services/execution_loop.dart';
import '../services/context_selector.dart';
import '../services/tool_executor.dart';
import '../services/tool_registry.dart';
import '../services/event_bus.dart';
import '../services/event_bus_impl.dart';
import '../services/semantic_search/semantic_search_service.dart';
import '../tools/task/repositories/task_repository.dart';
import '../tools/timer/repositories/timer_repository.dart';
import '../tools/regulation/repositories/person_repository.dart';
import '../tools/regulation/repositories/regulation_entry_repository.dart';
import '../tools/regulation/repositories/commitment_repository.dart';
import '../tools/regulation/repositories/commitment_log_repository.dart';
import '../tools/task/task_tools.dart';
import '../tools/timer/timer_tools.dart';
import '../tools/regulation/regulation_tools.dart';
import 'persistence_web.dart'
    if (dart.library.io) 'persistence_native.dart';

class ApplicationModule extends BootstrapModule {
  @override
  Future<void> register(GetIt getIt, EverythingStackConfig config) async {
    _registerTools(getIt);
    await _registerEventBus(getIt);
    _registerContextSelector(getIt);
    _registerExecutionLoop(getIt);
  }

  void _registerTools(GetIt getIt) {
    getIt.registerSingleton<ToolRegistry>(ToolRegistry());

    final taskRepo = TaskRepository();
    getIt.registerSingleton<TaskRepository>(taskRepo);
    registerTaskTools(getIt<ToolRegistry>(), taskRepo);

    final timerRepo = TimerRepository();
    getIt.registerSingleton<TimerRepository>(timerRepo);
    registerTimerTools(getIt<ToolRegistry>(), timerRepo);

    final personRepo = PersonRepository();
    getIt.registerSingleton<PersonRepository>(personRepo);
    final regulationEntryRepo = RegulationEntryRepository();
    getIt.registerSingleton<RegulationEntryRepository>(regulationEntryRepo);
    final commitmentRepo = CommitmentRepository();
    getIt.registerSingleton<CommitmentRepository>(commitmentRepo);
    final commitmentLogRepo = CommitmentLogRepository();
    getIt.registerSingleton<CommitmentLogRepository>(commitmentLogRepo);
    registerRegulationTools(
      getIt<ToolRegistry>(),
      personRepo,
      regulationEntryRepo,
      commitmentRepo,
      commitmentLogRepo,
    );
  }

  Future<void> _registerEventBus(GetIt getIt) async {
    final eventRepository = await createEventRepository();
    getIt.registerSingleton<EventRepository>(eventRepository);

    final eventBus = EventBusImpl(repository: eventRepository);
    getIt.registerSingleton<EventBus>(eventBus);

    getIt.registerSingleton<ToolExecutor>(ToolExecutor(
      toolRegistry: getIt<ToolRegistry>(),
      eventBus: eventBus,
    ));
  }

  void _registerContextSelector(GetIt getIt) {
    if (!getIt.isRegistered<EntityRepository<Invocation>>() ||
        !getIt.isRegistered<SemanticSearchService>()) {
      return;
    }

    getIt.registerSingleton<ContextSelector>(ContextSelector(
      invocationRepo: getIt<EntityRepository<Invocation>>(),
      embeddingService: EmbeddingService.instance,
      semanticSearchService: getIt<SemanticSearchService>(),
    ));
  }

  void _registerExecutionLoop(GetIt getIt) {
    if (!getIt.isRegistered<InferenceService>() ||
        !getIt.isRegistered<TTSService>()) {
      return;
    }

    final executionLoop = ExecutionLoop(
      inferenceService: getIt<InferenceService>(),
      ttsService: getIt<TTSService>(),
      invocationRepo: getIt<InvocationRepository<Invocation>>(),
      eventBus: getIt<EventBus>(),
    );
    getIt.registerSingleton<ExecutionLoop>(executionLoop);
    executionLoop.initialize();
  }

  @override
  Future<void> dispose(GetIt getIt) async {
    try {
      getIt<ExecutionLoop>().dispose();
    } catch (_) {}
    try {
      getIt<EventBus>().dispose();
    } catch (_) {}
  }
}
