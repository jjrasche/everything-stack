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
/// 3. FileService (depends on BlobStore)
/// 4. ConnectivityService
/// 5. SyncService (optional, requires Supabase credentials)
/// 6. EmbeddingService (optional, requires API key)

library;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

// Conditional import for ObjectBox (native platforms only)
import 'package:objectbox/objectbox.dart'
    if (dart.library.html) 'bootstrap/objectbox_stub.dart';

import 'services/blob_store.dart';
import 'services/file_service.dart';
import 'services/sync_service.dart';
import 'services/connectivity_service.dart';
import 'services/embedding_service.dart';

// Conditional import for EmbeddingQueueService (native platforms only)
import 'services/embedding_queue_service.dart'
    if (dart.library.html) 'bootstrap/embedding_queue_service_web_stub.dart';
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
import 'persistence/event_repository_in_memory.dart';
import 'persistence/objectbox/system_event_objectbox_adapter.dart'
    if (dart.library.html) 'persistence/event_repository_in_memory.dart';
import 'persistence/indexeddb/system_event_indexeddb_adapter.dart';
import 'tools/task/task_tools.dart';
import 'services/trainables/namespace_selector.dart';
import 'services/trainables/tool_selector.dart';
import 'services/trainables/context_injector.dart';
import 'services/trainables/llm_config_selector.dart';
import 'services/trainables/llm_orchestrator.dart';
import 'services/trainables/response_renderer.dart';
import 'domain/invocation.dart' as domain_invocation;
import 'core/invocation_repository.dart';
import 'core/adaptation_state_repository.dart';
import 'core/feedback_repository.dart';
import 'core/turn_repository.dart';
// Conditional imports for ObjectBox adapters (native platforms only)
import 'persistence/objectbox/invocation_objectbox_adapter.dart'
    if (dart.library.html) 'persistence/objectbox/invocation_objectbox_adapter_stub.dart';
import 'persistence/objectbox/adaptation_state_objectbox_adapter.dart'
    if (dart.library.html) 'persistence/objectbox/adaptation_state_objectbox_adapter_stub.dart';
import 'persistence/objectbox/feedback_objectbox_adapter.dart'
    if (dart.library.html) 'persistence/objectbox/feedback_objectbox_adapter_stub.dart';
import 'persistence/objectbox/turn_objectbox_adapter.dart'
    if (dart.library.html) 'persistence/objectbox/turn_objectbox_adapter_stub.dart';
import 'persistence/indexeddb/invocation_indexeddb_adapter.dart';
import 'persistence/indexeddb/adaptation_state_indexeddb_adapter.dart';
import 'persistence/indexeddb/feedback_indexeddb_adapter.dart';
import 'persistence/indexeddb/turn_indexeddb_adapter.dart';
// Conditional import for ObjectBox factory (native platforms only)
import 'bootstrap/objectbox_store_factory.dart'
    if (dart.library.html) 'bootstrap/objectbox_store_factory_stub.dart';
import 'bootstrap/indexeddb_factory.dart';
import 'bootstrap/test_config.dart';

// Conditional import for platform-specific BlobStore
import 'bootstrap/blob_store_factory_stub.dart'
    if (dart.library.io) 'bootstrap/blob_store_factory_io.dart'
    if (dart.library.html) 'bootstrap/blob_store_factory_web.dart';

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

    // 2. OS environment variables (CI/CD pipelines)
    final osValue = Platform.environment[key];
    if (osValue != null && osValue.isNotEmpty) {
      return osValue;
    }

    // 3. Compile-time environment (--dart-define)
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
    return _initializeServices(cfg);
  } catch (e, st) {
    debugPrint('❌ [Bootstrap] FATAL ERROR during initialization: $e');
    debugPrint('Stack trace: $st');
    rethrow;
  }
}

Future<void> _initializeServices(EverythingStackConfig cfg) async {
  try {

  // Check if running integration tests
  const isIntegrationTest =
      String.fromEnvironment('INTEGRATION_TEST', defaultValue: 'false') == 'true';

  if (cfg.useMocks) {
    await _initializeMocks();
    return;
  }

  if (isIntegrationTest) {
    debugPrint('🧪 [INTEGRATION TEST MODE] Using mock external services');
  }

  // 0. Initialize Firebase Crashlytics (cross-platform: Android, iOS, Web)
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

  // 1. Create timeout-wrapped HTTP client (Layer 1 defense)
  // Note: Currently unused. Will be used for embedding service HTTP client in future phases.
  // final timeoutClient = TimeoutHttpClient(http.Client());
  // final wrappedHttpClient = _wrapHttpClientWithTimeout(timeoutClient);

  // 2. Initialize Persistence (platform-specific: ObjectBox or IndexedDB)
  if (kIsWeb) {
    // Web: IndexedDB
    debugPrint('💾 Initializing IndexedDB for web platform...');
    final db = await openIndexedDB();

    // Create and register adapters
    final invocationAdapter = InvocationIndexedDBAdapter(db);
    final adaptationStateAdapter = AdaptationStateIndexedDBAdapter(db);
    final feedbackAdapter = FeedbackIndexedDBAdapter(db);
    final turnAdapter = TurnIndexedDBAdapter(db);

    // Register repositories in GetIt
    getIt.registerSingleton<InvocationRepository<domain_invocation.Invocation>>(
      invocationAdapter,
    );
    getIt.registerSingleton<AdaptationStateRepository>(
      adaptationStateAdapter,
    );
    getIt.registerSingleton<FeedbackRepository>(
      feedbackAdapter,
    );
    getIt.registerSingleton<TurnRepository>(
      turnAdapter,
    );
  } else {
    // Native: ObjectBox
    debugPrint('💾 Initializing ObjectBox for native platform...');
    final store = await openObjectBoxStore();

    // Register store for direct access (TaskRepository needs it)
    getIt.registerSingleton<Store>(store, instanceName: 'objectBoxStore');

    // Create and register adapters
    final invocationAdapter = InvocationObjectBoxAdapter(store);
    final adaptationStateAdapter = AdaptationStateObjectBoxAdapter(store);
    final feedbackAdapter = FeedbackObjectBoxAdapter(store);
    final turnAdapter = TurnObjectBoxAdapter(store);

    // Register repositories in GetIt
    getIt.registerSingleton<InvocationRepository<domain_invocation.Invocation>>(
      invocationAdapter,
    );
    getIt.registerSingleton<AdaptationStateRepository>(
      adaptationStateAdapter,
    );
    getIt.registerSingleton<FeedbackRepository>(
      feedbackAdapter,
    );
    getIt.registerSingleton<TurnRepository>(
      turnAdapter,
    );
  }

  // 2. Initialize BlobStore (platform-specific)
  final blobStore = createPlatformBlobStore();
  await blobStore.initialize();
  BlobStore.instance = blobStore;

  // 3. Initialize FileService (depends on BlobStore)
  final fileService = RealFileService(blobStore: blobStore);
  await fileService.initialize();
  FileService.instance = fileService;

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
  final invocationRepo = getIt<InvocationRepository<domain_invocation.Invocation>>();
  ServiceRegistry.register<InvocationRepository<domain_invocation.Invocation>>(
    'invocation_repo',
    invocationRepo,
  );

  // 10. Initialize TTS Service
  if (isIntegrationTest) {
    debugPrint('🔊 [TEST] Using mock TTS service');
    TTSService.instance = MockTTSServiceForTests();
  } else {
    final ttsConfig = ServiceConfig(
      provider: cfg.ttsProvider ?? 'flutter',
      credentials: cfg.googleTtsApiKey != null ? {'apiKey': cfg.googleTtsApiKey} : {},
    );
    await _initializeService<TTSService>(
      serviceName: 'tts',
      config: ttsConfig,
      setInstance: (service) { TTSService.instance = service; },
      shouldInitialize: (service) => true,
      getType: (service) => service.runtimeType,
    );
  }

  // 11. Initialize LLM Service
  if (isIntegrationTest) {
    debugPrint('🤖 [TEST] Using mock LLM service');
    LLMService.instance = MockLLMServiceForTests();
  } else {
    final llmConfig = ServiceConfig(
      provider: cfg.llmProvider ?? 'groq',
      credentials: {if (cfg.groqApiKey != null) 'apiKey': cfg.groqApiKey!},
    );
    await _initializeService<LLMService>(
      serviceName: 'llm',
      config: llmConfig,
      setInstance: (service) { LLMService.instance = service; },
      shouldInitialize: (service) => true,
      getType: (service) => service.runtimeType,
    );
  }

  // 12. Initialize Embedding Service
  if (isIntegrationTest) {
    debugPrint('📊 [TEST] Using mock embedding service');
    EmbeddingService.instance = MockEmbeddingServiceForTests();
  } else {
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
  }

  // 13. Initialize Audio Recording Service (Microphone Input)
  try {
    await AudioRecordingService.instance.initialize();
    debugPrint('✅ Audio: AudioRecordingService');
  } catch (e) {
    debugPrint('⚠️ Audio recording service init failed: $e');
  }

  // 14. Initialize STT Service (Speech-to-Text)
  if (isIntegrationTest) {
    debugPrint('🎤 [TEST] Using mock STT service');
    // For testing, we use a mock that doesn't require actual speech input
    STTService.instance = MockSTTServiceForTests();
  } else {
    if (cfg.deepgramApiKey != null && cfg.deepgramApiKey!.isNotEmpty) {
      debugPrint('🎤 [STT] Initializing DeepgramSTTService');
      final sttService = DeepgramSTTService(
        apiKey: cfg.deepgramApiKey!,
        invocationRepository: getIt<InvocationRepository<domain_invocation.Invocation>>(),
      );
      await sttService.initialize();
      STTService.instance = sttService;
      debugPrint('✅ STT: DeepgramSTTService');
    } else {
      debugPrint('⚠️ Deepgram API key missing');
      debugPrint('ℹ️ STT: disabled');
      STTService.instance = NullSTTService();
    }
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

/// Initialize with mock services (for testing).
Future<void> _initializeMocks() async {
  final mockBlobStore = MockBlobStore();
  await mockBlobStore.initialize();
  BlobStore.instance = mockBlobStore;

  final mockFileService = MockFileService(blobStore: mockBlobStore);
  await mockFileService.initialize();
  FileService.instance = mockFileService;

  ConnectivityService.instance = MockConnectivityService();
  SyncService.instance = MockSyncService();
  EmbeddingService.instance = MockEmbeddingService();

  // Initialize streaming services for tests
  STTService.instance = MockSTTServiceForTests();
  TTSService.instance = MockTTSServiceForTests();
  LLMService.instance = MockLLMServiceForTests();
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

  // Dispose streaming services
  STTService.instance.dispose();
  TTSService.instance.dispose();
  LLMService.instance.dispose();
  AudioRecordingService.instance.dispose();

  // Dispose other services
  // Note: ObjectBox Store can be safely disposed, IndexedDB cleanup is handled by browser
  if (!kIsWeb) {
    try {
      final store = getIt<Store>(instanceName: 'objectBoxStore');
      store.close();  // Store.close() is synchronous, no await needed
    } catch (e) {
      debugPrint('⚠️ Store not registered in GetIt, skipping disposal');
    }
  }
  FileService.instance.dispose();
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

    // LLMService - loaded from config, respects abstraction
    // Skip if already registered (e.g., by tests with mocks)
    if (!getIt.isRegistered<LLMService>()) {
      getIt.registerSingleton<LLMService>(
        LLMService.instance,  // Already initialized by bootstrap
      );
    }
    debugPrint('✅ [setupServiceLocator] LLMService registered');

    // ========== Domain Repositories (Already registered in initializeEverythingStack) ==========
    // InvocationRepository, AdaptationStateRepository, FeedbackRepository, TurnRepository
    // are already registered as singletons in initializeEverythingStack().
    // They don't need to be re-registered here.

    // ========== Trainable Selectors (Real implementations) ==========
    // Repositories are already registered in initializeEverythingStack()

    debugPrint('🔍 [setupServiceLocator] Registering NamespaceSelector...');
    getIt.registerSingleton<NamespaceSelector>(
      NamespaceSelector(
        invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
        adaptationStateRepo: getIt<AdaptationStateRepository>(),
        feedbackRepo: getIt<FeedbackRepository>(),
      ),
    );
    debugPrint('✅ [setupServiceLocator] NamespaceSelector registered');

    getIt.registerSingleton<ToolSelector>(
      ToolSelector(
        invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
        adaptationStateRepo: getIt<AdaptationStateRepository>(),
        feedbackRepo: getIt<FeedbackRepository>(),
      ),
    );

    getIt.registerSingleton<ContextInjector>(
      ContextInjector(
        invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
        adaptationStateRepo: getIt<AdaptationStateRepository>(),
        feedbackRepo: getIt<FeedbackRepository>(),
      ),
    );

    getIt.registerSingleton<LLMConfigSelector>(
      LLMConfigSelector(
        invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
        adaptationStateRepo: getIt<AdaptationStateRepository>(),
        feedbackRepo: getIt<FeedbackRepository>(),
      ),
    );

    getIt.registerSingleton<LLMOrchestrator>(
      LLMOrchestrator(
        invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
        adaptationStateRepo: getIt<AdaptationStateRepository>(),
        feedbackRepo: getIt<FeedbackRepository>(),
      ),
    );

    getIt.registerSingleton<ResponseRenderer>(
      ResponseRenderer(
        invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
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

    // ========== Event Bus (Write-through persistence + pub/sub) ==========
    debugPrint('🔍 [setupServiceLocator] Initializing EventBus...');

    // Create platform-specific EventRepository
    late EventRepository eventRepository;
    if (kIsWeb) {
      debugPrint('📝 EventBus: Using IndexedDB adapter (web)');
      eventRepository = SystemEventRepositoryIndexedDBAdapter(await openIndexedDB());
    } else {
      debugPrint('📝 EventBus: Using ObjectBox adapter (native)');
      final store = await openObjectBoxStore();
      eventRepository = SystemEventRepositoryObjectBoxAdapter(store);
    }
    getIt.registerSingleton<EventRepository>(eventRepository);

    // Create EventBus with repository
    final eventBus = EventBusImpl(repository: eventRepository);
    getIt.registerSingleton<EventBus>(eventBus);
    debugPrint('✅ [setupServiceLocator] EventBus registered');

    // ========== Tool Executor (Real agentic loop) ==========

    getIt.registerSingleton<ToolExecutor>(
      ToolExecutor(
        invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
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
      toolExecutor: getIt<ToolExecutor>(),
      invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
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

/// Setup GetIt for integration testing.
///
/// Registers real internal components but mocks external APIs.
/// Call this in test setUp() to create a test-specific GetIt instance.
///
/// Example:
/// ```dart
/// void main() {
///   group('Coordinator E2E', () {
///     setUp(() {
///       setupServiceLocatorForTesting();
///     });
///
///     test('Real orchestration with mocked externals', () async {
///       final coordinator = getIt<Coordinator>();
///       // ...
///     });
///   });
/// }
/// ```
void setupServiceLocatorForTesting({
  EmbeddingService? embeddingService,
  LLMService? llmService,
}) {
  getIt.reset();

  // ========== External APIs - Mocked for testing ==========

  getIt.registerSingleton<EmbeddingService>(
    embeddingService ?? MockEmbeddingService(),
  );

  getIt.registerSingleton<LLMService>(
    llmService ?? MockLLMServiceForTests(),
  );

  // ========== Domain Repositories ==========
  // Note: Repository registrations are handled by setupEverythingStack()
  // Test classes that need repositories should use setupEverythingStack() or mock them separately

  // ========== Trainable Selectors - Skipped for test setup ==========
  // These require repositories which are not available in test mode
  // Tests should either:
  // 1. Use setupEverythingStack() for full integration
  // 2. Mock these selectors individually if needed

  // ========== Tool Registry ==========

  getIt.registerSingleton<ToolRegistry>(ToolRegistry());

  // ========== Tool Executor & Coordinator - Skipped for test setup ==========
  // These require repositories and selectors which are not available in test mode
  // Tests should use setupEverythingStack() for full integration testing
}

// ============================================================================
// Mock Services for Testing
// ============================================================================

