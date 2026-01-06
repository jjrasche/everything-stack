/// # Bootstrap
///
/// Single entry point for initializing all Everything Stack services.
/// Handles platform-specific setup and proper initialization order.
///
/// ## Usage
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await initializeEverythingStack();
///   runApp(ProviderScope(child: MyApp()));
/// }
/// ```
///
/// ## Configuration
/// Pass configuration via parameters or compile-time environment:
/// ```
/// flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///             --dart-define=SUPABASE_ANON_KEY=your-key \
///             --dart-define=JINA_API_KEY=your-key
/// ```
///
/// ## Initialization Order
/// 1. Persistence (platform-specific: ObjectBox or IndexedDB)
/// 2. BlobStore (platform-specific: FileSystem or IndexedDB)
/// 3. ConnectivityService
/// 4. SyncService (optional, requires Supabase credentials)
/// 5. EmbeddingService (optional, requires API key)

library;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'services/blob_store.dart';
import 'services/sync_service.dart';
import 'services/connectivity_service.dart';
import 'services/embedding_service.dart';
import 'services/embedding_queue_service.dart';
import 'services/audio_recording_service.dart';
import 'services/stt_service.dart';
import 'services/tts_service.dart';
import 'services/llm_service.dart';
import 'services/service_registry.dart';
import 'services/service_builders.dart';
import 'services/coordinator.dart';
import 'services/tool_executor.dart';
import 'services/tool_registry.dart';
import 'services/event_bus.dart';
import 'services/event_bus_impl.dart';
import 'tools/task/repositories/task_repository.dart';
import 'core/event_repository.dart';
import 'tools/task/task_tools.dart';
import 'core/invocation.dart';
import 'core/invocation_repository.dart';
import 'core/adaptation_state_repository.dart';
import 'core/feedback_repository.dart';
import 'services/implementations/groq_implementer.dart';
import 'services/implementations/deepgram_implementer.dart';
import 'services/implementations/flutter_tts_implementer.dart';
import 'services/implementations/llm_implementer.dart';
import 'services/implementations/stt_implementer.dart';
import 'services/implementations/tts_implementer.dart';
import 'services/trainables/namespace_selector.dart';
import 'services/trainables/tool_selector.dart';
import 'services/trainables/context_injector.dart';
import 'services/trainables/llm_config_selector.dart';
import 'services/trainables/llm_orchestrator.dart';
import 'services/trainables/response_renderer.dart';

// Platform-specific persistence initialization (ObjectBox or IndexedDB)
import 'bootstrap/persistence_web.dart'
    if (dart.library.io) 'bootstrap/persistence_native.dart';

// Platform-specific BlobStore factory
import 'bootstrap/blob_store_factory_web.dart'
    if (dart.library.io) 'bootstrap/blob_store_factory_io.dart';

// Platform-specific EmbeddingTaskStore factory
import 'services/embedding_task_store_web.dart'
    if (dart.library.io) 'services/embedding_task_store_native.dart';

/// Configuration for Everything Stack initialization.
class EverythingStackConfig {
  /// Supabase project URL (optional - sync disabled if not provided)
  final String? supabaseUrl;

  /// Supabase anonymous key (optional - sync disabled if not provided)
  final String? supabaseAnonKey;

  /// Jina AI API key for embeddings (optional - mock used if not provided)
  final String? jinaApiKey;

  /// Gemini API key for embeddings (alternative to Jina)
  final String? geminiApiKey;

  /// Deepgram API key for speech-to-text (optional - STT disabled if not provided)
  final String? deepgramApiKey;

  /// Google Cloud API key for text-to-speech (optional - TTS disabled if not provided)
  final String? googleTtsApiKey;

  /// Anthropic API key for Claude LLM (optional - LLM disabled if not provided)
  final String? claudeApiKey;

  /// Groq API key for Groq LLM (optional - uses Claude if not provided)
  final String? groqApiKey;

  /// LLM provider to use: 'groq', 'claude', 'local' (default: 'groq')
  final String? llmProvider;

  /// TTS provider to use: 'flutter', 'google', 'azure' (default: 'flutter')
  final String? ttsProvider;

  /// STT provider to use: 'deepgram', 'google', 'local' (default: 'deepgram')
  final String? sttProvider;

  /// Embedding provider to use: 'jina', 'gemini', 'local' (default: 'jina')
  final String? embeddingProvider;

  /// Whether to use mock services (for testing)
  final bool useMocks;

  const EverythingStackConfig({
    this.supabaseUrl,
    this.supabaseAnonKey,
    this.jinaApiKey,
    this.geminiApiKey,
    this.deepgramApiKey,
    this.googleTtsApiKey,
    this.claudeApiKey,
    this.groqApiKey,
    this.llmProvider,
    this.ttsProvider,
    this.sttProvider,
    this.embeddingProvider,
    this.useMocks = false,
  });

  /// Create config from compile-time environment variables.
  ///
  /// Use with: flutter run --dart-define=SUPABASE_URL=xxx ...
  factory EverythingStackConfig.fromEnvironment() {
    return EverythingStackConfig(
      supabaseUrl: _envOrNull('SUPABASE_URL'),
      supabaseAnonKey: _envOrNull('SUPABASE_ANON_KEY'),
      jinaApiKey: _envOrNull('JINA_API_KEY'),
      geminiApiKey: _envOrNull('GEMINI_API_KEY'),
      deepgramApiKey: _envOrNull('DEEPGRAM_API_KEY'),
      googleTtsApiKey: _envOrNull('GOOGLE_TTS_API_KEY'),
      claudeApiKey: _envOrNull('CLAUDE_API_KEY'),
      groqApiKey: _envOrNull('GROQ_API_KEY'),
    );
  }

  // Compile-time environment variable helpers.
  // String.fromEnvironment must be const, so we need separate declarations.
  static const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _jinaApiKey = String.fromEnvironment('JINA_API_KEY');
  static const _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _deepgramApiKey = String.fromEnvironment('DEEPGRAM_API_KEY');
  static const _googleTtsApiKey = String.fromEnvironment('GOOGLE_TTS_API_KEY');
  static const _claudeApiKey = String.fromEnvironment('CLAUDE_API_KEY');
  static const _groqApiKey = String.fromEnvironment('GROQ_API_KEY');

  static String? _envOrNull(String key) {
    // Try sources in order:
    // 1. .env file (local development)
    String? runtimeValue;
    try {
      runtimeValue = dotenv.maybeGet(key);
    } catch (e) {
      // dotenv may not be initialized on web or in some environments
      runtimeValue = null;
    }
    if (runtimeValue != null && runtimeValue.isNotEmpty) {
      return runtimeValue;
    }

    // 2. Compile-time environment (--dart-define)
    switch (key) {
      case 'SUPABASE_URL':
        return _supabaseUrl.isEmpty ? null : _supabaseUrl;
      case 'SUPABASE_ANON_KEY':
        return _supabaseAnonKey.isEmpty ? null : _supabaseAnonKey;
      case 'JINA_API_KEY':
        return _jinaApiKey.isEmpty ? null : _jinaApiKey;
      case 'GEMINI_API_KEY':
        return _geminiApiKey.isEmpty ? null : _geminiApiKey;
      case 'DEEPGRAM_API_KEY':
        return _deepgramApiKey.isEmpty ? null : _deepgramApiKey;
      case 'GOOGLE_TTS_API_KEY':
        return _googleTtsApiKey.isEmpty ? null : _googleTtsApiKey;
      case 'CLAUDE_API_KEY':
        return _claudeApiKey.isEmpty ? null : _claudeApiKey;
      case 'GROQ_API_KEY':
        return _groqApiKey.isEmpty ? null : _groqApiKey;
      default:
        return null;
    }
  }

  /// Whether Supabase sync is configured
  bool get hasSyncConfig =>
      supabaseUrl != null &&
      supabaseUrl!.isNotEmpty &&
      supabaseAnonKey != null &&
      supabaseAnonKey!.isNotEmpty;

  /// Whether embedding service is configured
  bool get hasEmbeddingConfig =>
      (jinaApiKey != null && jinaApiKey!.isNotEmpty) ||
      (geminiApiKey != null && geminiApiKey!.isNotEmpty);
}

/// Initialize all Everything Stack services.
///
/// Call this once at app startup before runApp().
/// Services are initialized in dependency order.
///
/// Example:
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await initializeEverythingStack();
///   runApp(ProviderScope(child: MyApp()));
/// }
/// ```
///
/// With configuration:
/// ```dart
/// await initializeEverythingStack(
///   config: EverythingStackConfig(
///     supabaseUrl: 'https://xxx.supabase.co',
///     supabaseAnonKey: 'your-key',
///     jinaApiKey: 'your-jina-key',
///   ),
/// );
/// ```
/// Global embedding queue service instance.
/// Initialized by initializeEverythingStack() and used by NoteRepository.
EmbeddingQueueService? _embeddingQueueService;

/// Get the initialized embedding queue service.
/// Returns null if not initialized (embeddings disabled).
EmbeddingQueueService? get embeddingQueueService => _embeddingQueueService;

/// DRY helper to initialize a service: create → initialize → register
///
/// Handles the common 3-step pattern for all services to avoid boilerplate.
/// Supports optional initialization (e.g., EmbeddingService skips if Null).
///
/// Usage:
/// ```dart
/// await _initializeService<TTSService>(
///   serviceName: 'tts',
///   config: ttsConfig,
///   setInstance: (service) { TTSService.instance = service; },
///   shouldInitialize: (service) => true,
///   getType: (service) => service.runtimeType,
/// );
/// ```
Future<void> _initializeService<T>({
  required String serviceName,
  required ServiceConfig config,
  required Function(T) setInstance,
  required bool Function(T) shouldInitialize,
  required Type Function(T) getType,
}) async {
  try {
    final service = createService<T>(serviceName, config);
    setInstance(service);

    if (shouldInitialize(service)) {
      await service.initialize();
      debugPrint('✅ ${serviceName.toUpperCase()}: ${getType(service)}');
    } else {
      debugPrint('ℹ️ ${serviceName.toUpperCase()}: disabled');
    }

    ServiceRegistry.register<T>(serviceName, service);
  } catch (e) {
    debugPrint('⚠️ $serviceName init failed: $e');
  }
}

Future<void> initializeEverythingStack({
  EverythingStackConfig? config,
}) async {
  debugPrint('═══════════════════════════════════════════════════════');
  debugPrint('🚀 [Bootstrap] Starting Everything Stack initialization');
  debugPrint('═══════════════════════════════════════════════════════');

  // Load .env file for local development (bundled as asset in pubspec.yaml)
  // In .gitignore so it won't be committed to git
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('✅ [Bootstrap] Loaded .env with API keys');
  } catch (e) {
    // .env file is optional - may not exist on fresh clone
    debugPrint('ℹ️ [Bootstrap] .env not found, falling back to compile-time env vars');
  }

  try {
    final cfg = config ?? EverythingStackConfig.fromEnvironment();
    debugPrint('✅ [Bootstrap] Configuration loaded successfully');
    debugPrint('🔑 Config loaded - Deepgram key present: ${cfg.deepgramApiKey != null}');
    debugPrint('🔑 Config loaded - Groq key present: ${cfg.groqApiKey != null}');
    return _initializeServices(cfg);
  } catch (e, st) {
    debugPrint('❌ [Bootstrap] FATAL ERROR during initialization: $e');
    debugPrint('Stack trace: $st');
    rethrow;
  }
}

Future<void> _initializeServices(EverythingStackConfig cfg) async {
  try {

  // 0. Initialize Firebase Crashlytics (cross-platform: Android, iOS, Web)
  // Skip Firebase in test environment (TEST_MODE dart-define flag set when running tests)
  const isTestMode = bool.fromEnvironment('TEST_MODE', defaultValue: false);
  if (isTestMode) {
    debugPrint('⚠️ Skipping Firebase initialization (TEST_MODE=true)');
  } else {
    try {
      // Initialize Firebase (auto-config on native, web uses default project)
      await Firebase.initializeApp();
      debugPrint('✅ Firebase Core initialized');

      // Enable Crashlytics crash reporting
      // This catches all uncaught exceptions and sends them to Firebase
      FlutterError.onError = (errorDetails) {
        FirebaseCrashlytics.instance.recordFlutterError(errorDetails);
      };

      // Also capture async errors
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      debugPrint('✅ Crashlytics enabled - crashes will be reported to Firebase');
    } catch (e) {
      debugPrint('⚠️ Firebase/Crashlytics initialization failed: $e');
      debugPrint('   Continuing without crash reporting...');
    }
  }

  // 1. Create timeout-wrapped HTTP client (Layer 1 defense)
  // Note: Currently unused. Will be used for embedding service HTTP client in future phases.
  // final timeoutClient = TimeoutHttpClient(http.Client());
  // final wrappedHttpClient = _wrapHttpClientWithTimeout(timeoutClient);

  // 2. Initialize Persistence (platform-specific: ObjectBox or IndexedDB)
  debugPrint('💾 Initializing persistence layer...');
  await initializePersistence(getIt);

  // 3. Initialize BlobStore (platform-specific)
  final blobStore = createPlatformBlobStore();
  await blobStore.initialize();
  BlobStore.instance = blobStore;

  // 4. Initialize ConnectivityService
  final connectivityService = ConnectivityPlusService();
  await connectivityService.initialize();
  ConnectivityService.instance = connectivityService;

  // 5. Initialize SyncService (optional - requires Supabase config)
  if (cfg.hasSyncConfig) {
    final syncService = SupabaseSyncService(
      supabaseUrl: cfg.supabaseUrl!,
      supabaseAnonKey: cfg.supabaseAnonKey!,
    );
    await syncService.initialize();
    SyncService.instance = syncService;
  }
  // else: keeps MockSyncService default

  // 6. EmbeddingQueueService deferred to Phase 1 (Note entity not yet implemented)

  // 8-11. STT/TTS/LLM Services (platform-specific)
  // Web platform: Uses browser APIs (SpeechSynthesis for TTS, Web Speech API for STT)
  // Native platforms: Uses external APIs (Google Cloud TTS, Deepgram STT)

  // 9. Register invocation repository in service registry (shared by all services)
  // Note: Repository is already registered as singleton in GetIt above.
  // This registers it in the old ServiceRegistry for backward compatibility.
  final invocationRepo = getIt<InvocationRepository<Invocation>>();
  ServiceRegistry.register<InvocationRepository<Invocation>>(
    'invocation_repo',
    invocationRepo,
  );

  // 10. Initialize TTS Service with implementers
  debugPrint('🔊 [TTS] Initializing TTSService with implementers');
  final ttsImplementers = <String, TTSImplementer>{
    'flutter': FlutterTtsImplementer(),
  };
  final ttsService = TTSService(
    implementers: ttsImplementers,
    defaultImplementer: 'flutter',
    invocationRepo: getIt<InvocationRepository<Invocation>>(),
    adaptationStateRepo: getIt<AdaptationStateRepository>(),
    feedbackRepo: getIt<FeedbackRepository>(),
  );
  getIt.registerSingleton<TTSService>(ttsService);
  debugPrint('✅ TTS: TTSService (flutter)');

  // 11. Initialize LLM Service with implementers
  debugPrint('🧠 [LLM] Initializing LLMService with implementers');
  final llmImplementers = <String, LLMImplementer>{};

  // Add Groq implementer if API key provided
  if (cfg.groqApiKey != null && cfg.groqApiKey!.isNotEmpty) {
    llmImplementers['groq'] = GroqImplementer(apiKey: cfg.groqApiKey!);
    debugPrint('✅ LLM: GroqImplementer registered');
  }

  // Default to Groq if available, otherwise error
  final defaultLLMImplementer = llmImplementers.isNotEmpty ? 'groq' : 'null';
  if (llmImplementers.isEmpty) {
    debugPrint('⚠️ No LLM API keys provided - LLM will not function');
  }

  final llmService = LLMService(
    implementers: llmImplementers,
    defaultImplementer: defaultLLMImplementer,
    invocationRepo: getIt<InvocationRepository<Invocation>>(),
    adaptationStateRepo: getIt<AdaptationStateRepository>(),
    feedbackRepo: getIt<FeedbackRepository>(),
  );
  getIt.registerSingleton<LLMService>(llmService);
  debugPrint('✅ LLM: LLMService (default: $defaultLLMImplementer)');

  // 12. Initialize Embedding Service
  final embeddingConfig = ServiceConfig(
    provider: cfg.embeddingProvider ?? 'jina',
    credentials: {
      if (cfg.jinaApiKey != null) 'apiKey': cfg.jinaApiKey!,
      if (cfg.geminiApiKey != null) 'apiKey': cfg.geminiApiKey!,
    },
  );
  await _initializeService<EmbeddingService>(
    serviceName: 'embedding',
    config: embeddingConfig,
    setInstance: (service) { EmbeddingService.instance = service; },
    shouldInitialize: (service) => service is! NullEmbeddingService,
    getType: (service) => service.runtimeType,
  );

  // 13. Initialize Audio Recording Service (Microphone Input)
  try {
    await AudioRecordingService.instance.initialize();
    debugPrint('✅ Audio: AudioRecordingService');
  } catch (e) {
    debugPrint('⚠️ Audio recording service init failed: $e');
  }

  // 14. Initialize STT Service (Speech-to-Text) with implementers
  debugPrint('🎤 [STT] Initializing STTService with implementers');
  final sttImplementers = <String, STTImplementer>{};

  // Add Deepgram implementer if API key provided
  if (cfg.deepgramApiKey != null && cfg.deepgramApiKey!.isNotEmpty) {
    sttImplementers['deepgram'] = DeepgramImplementer(apiKey: cfg.deepgramApiKey!);
    debugPrint('✅ STT: DeepgramImplementer registered');
  }

  // Only register if we have implementers
  if (sttImplementers.isNotEmpty) {
    final sttService = STTService(
      implementers: sttImplementers,
      defaultImplementer: 'deepgram',
      invocationRepo: getIt<InvocationRepository<Invocation>>(),
      adaptationStateRepo: getIt<AdaptationStateRepository>(),
      feedbackRepo: getIt<FeedbackRepository>(),
    );
    getIt.registerSingleton<STTService>(sttService);
    debugPrint('✅ STT: STTService (deepgram)');
  } else {
    debugPrint('⚠️ Deepgram API key missing');
    debugPrint('ℹ️ STT: disabled');
    // Register a disabled STT service (empty implementer map)
    final nullSttService = STTService(
      implementers: {},
      defaultImplementer: 'null',
      invocationRepo: getIt<InvocationRepository<Invocation>>(),
      adaptationStateRepo: getIt<AdaptationStateRepository>(),
      feedbackRepo: getIt<FeedbackRepository>(),
    );
    getIt.registerSingleton<STTService>(nullSttService);
  }

  // Note: Domain repositories (Task, Timer, Personality, Namespace) are initialized
  // by the application layer, not bootstrap. This allows for platform-specific
  // persistence handling and dependency injection.
  //
  // Bootstrap sets up infrastructure services (Persistence, BlobStore, Sync, etc).
  // Application layer creates domain repositories and ContextManager.
  //
  // See: lib/providers/ for Riverpod provider setup with repositories
  // See: lib/main.dart for ContextManager initialization
  debugPrint('\n✅ Bootstrap complete: infrastructure services initialized');
  } catch (e, st) {
    debugPrint('❌ [Bootstrap] FATAL ERROR during service initialization: $e');
    debugPrint('Stack trace:\n$st');
    debugPrint('═══════════════════════════════════════════════════════');
    rethrow;
  }
}

/// Dispose all services (call on app shutdown if needed).
Future<void> disposeEverythingStack() async {
  // Stop embedding queue first (flush pending tasks)
  if (_embeddingQueueService != null) {
    await _embeddingQueueService!.stop(flushPending: true);
  }

  // Dispose Coordinator and EventBus
  try {
    final coordinator = getIt<Coordinator>();
    coordinator.dispose();
  } catch (e) {
    debugPrint('⚠️ Coordinator not registered, skipping disposal');
  }

  try {
    final eventBus = getIt<EventBus>();
    eventBus.dispose();
  } catch (e) {
    debugPrint('⚠️ EventBus not registered, skipping disposal');
  }

  // Note: Streaming services (STT/TTS/LLM) don't have dispose() - implementers are stateless
  // AudioRecordingService still needs disposal
  AudioRecordingService.instance.dispose();

  // Dispose persistence (platform-specific cleanup)
  disposePersistence(getIt);

  // Dispose other services
  BlobStore.instance.dispose();
  ConnectivityService.instance.dispose();
  SyncService.instance.dispose();
}

// ============================================================================
// GetIt Service Locator Setup
// ============================================================================

final getIt = GetIt.instance;

/// Setup GetIt service locator with all application services.
///
/// Call this after initializeEverythingStack() to register domain services.
/// This respects abstraction layers - external APIs are factory methods,
/// internal components are real implementations.
///
/// Example:
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await initializeEverythingStack();
///   setupServiceLocator();
///   runApp(MyApp());
/// }
/// ```
Future<void> setupServiceLocator() async {
  debugPrint('[setupServiceLocator] 🚀🚀🚀 FUNCTION CALLED - STARTING SERVICE REGISTRATION');
  debugPrint('🚀 [setupServiceLocator] Starting service registration...');

  try {
    // ========== External APIs (Abstraction-Respecting) ==========

    // EmbeddingService - loaded from config, respects abstraction
    getIt.registerSingleton<EmbeddingService>(
      EmbeddingService.instance,  // Already initialized by bootstrap
    );
    debugPrint('✅ [setupServiceLocator] EmbeddingService registered');

    // LLMService - Already registered in _initializeServices
    // (Composition pattern: Service holds Map<String, LLMImplementer>)
    debugPrint('✅ [setupServiceLocator] LLMService already registered from bootstrap');

    // TTSService - Already registered in _initializeServices
    debugPrint('✅ [setupServiceLocator] TTSService already registered from bootstrap');

    // STTService - Already registered in _initializeServices
    debugPrint('✅ [setupServiceLocator] STTService already registered from bootstrap');

    // ========== Domain Repositories (Already registered in initializeEverythingStack) ==========
    // InvocationRepository, AdaptationStateRepository, FeedbackRepository, TurnRepository
    // are already registered as singletons in initializeEverythingStack().
    // They don't need to be re-registered here.

    // ========== Trainable Selectors (Real implementations) ==========
    // Repositories are already registered in initializeEverythingStack()

    debugPrint('🔍 [setupServiceLocator] Registering NamespaceSelector...');
    getIt.registerSingleton<NamespaceSelector>(
      NamespaceSelector(
        invocationRepo: getIt<InvocationRepository<Invocation>>(),
        adaptationStateRepo: getIt<AdaptationStateRepository>(),
        feedbackRepo: getIt<FeedbackRepository>(),
      ),
    );
    debugPrint('✅ [setupServiceLocator] NamespaceSelector registered');

    getIt.registerSingleton<ToolSelector>(
      ToolSelector(
        invocationRepo: getIt<InvocationRepository<Invocation>>(),
        adaptationStateRepo: getIt<AdaptationStateRepository>(),
        feedbackRepo: getIt<FeedbackRepository>(),
      ),
    );

    getIt.registerSingleton<ContextInjector>(
      ContextInjector(
        invocationRepo: getIt<InvocationRepository<Invocation>>(),
        adaptationStateRepo: getIt<AdaptationStateRepository>(),
        feedbackRepo: getIt<FeedbackRepository>(),
      ),
    );

    getIt.registerSingleton<LLMConfigSelector>(
      LLMConfigSelector(
        invocationRepo: getIt<InvocationRepository<Invocation>>(),
        adaptationStateRepo: getIt<AdaptationStateRepository>(),
        feedbackRepo: getIt<FeedbackRepository>(),
      ),
    );

    getIt.registerSingleton<LLMOrchestrator>(
      LLMOrchestrator(
        invocationRepo: getIt<InvocationRepository<Invocation>>(),
        adaptationStateRepo: getIt<AdaptationStateRepository>(),
        feedbackRepo: getIt<FeedbackRepository>(),
      ),
    );

    getIt.registerSingleton<ResponseRenderer>(
      ResponseRenderer(
        invocationRepo: getIt<InvocationRepository<Invocation>>(),
        adaptationStateRepo: getIt<AdaptationStateRepository>(),
        feedbackRepo: getIt<FeedbackRepository>(),
      ),
    );

    // ========== Tool Registry ==========

    getIt.registerSingleton<ToolRegistry>(ToolRegistry());

    // ========== Task Repository (Owns adapter selection internally) ==========

    final taskRepo = TaskRepository();
    getIt.registerSingleton<TaskRepository>(taskRepo);

    // Register task tools with registry
    registerTaskTools(getIt<ToolRegistry>(), taskRepo);

    // ========== Event Bus (Pub/sub with persistence) ==========
    debugPrint('🔍 [setupServiceLocator] Initializing EventBus...');

    // Create EventRepository and EventBus
    final eventRepository = await createEventRepository();
    getIt.registerSingleton<EventRepository>(eventRepository);

    final eventBus = EventBusImpl(repository: eventRepository);
    getIt.registerSingleton<EventBus>(eventBus);
    debugPrint('✅ [setupServiceLocator] EventBus registered');

    // ========== Tool Executor (Real agentic loop) ==========

    getIt.registerSingleton<ToolExecutor>(
      ToolExecutor(
        invocationRepo: getIt<InvocationRepository<Invocation>>(),
        toolRegistry: getIt<ToolRegistry>(),
      ),
    );

    // ========== Coordinator (Orchestrates all components) ==========
    debugPrint('🔍 [setupServiceLocator] Registering Coordinator...');
    final coordinator = Coordinator(
      namespaceSelector: getIt<NamespaceSelector>(),
      toolSelector: getIt<ToolSelector>(),
      contextInjector: getIt<ContextInjector>(),
      llmConfigSelector: getIt<LLMConfigSelector>(),
      llmOrchestrator: getIt<LLMOrchestrator>(),
      responseRenderer: getIt<ResponseRenderer>(),
      embeddingService: getIt<EmbeddingService>(),
      llmService: getIt<LLMService>(),
      ttsService: getIt<TTSService>(),
      toolExecutor: getIt<ToolExecutor>(),
      invocationRepo: getIt<InvocationRepository<Invocation>>(),
      eventBus: getIt<EventBus>(),
    );
    getIt.registerSingleton<Coordinator>(coordinator);

    // Initialize Coordinator event listeners
    coordinator.initialize();
    debugPrint('✅ [setupServiceLocator] Coordinator registered and initialized');
    debugPrint('🎉 [setupServiceLocator] ALL SERVICES REGISTERED SUCCESSFULLY');
  } catch (e, st) {
    debugPrint('❌ [setupServiceLocator] ERROR: $e');
    debugPrint('Stack trace: $st');
    rethrow;
  }
}