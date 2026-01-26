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
// import 'package:sentry_flutter/sentry_flutter.dart';  // DISABLED: Pulls in JNI (Java) on Windows
import 'package:objectbox/objectbox.dart' hide HnswIndex;

import 'services/blob_store.dart';
import 'services/sync_service.dart';
import 'services/connectivity_service.dart';
import 'services/embedding_service.dart';
import 'services/embedding_queue_service.dart';
import 'services/audio_recording_service.dart';
import 'services/audio_storage.dart';
import 'services/stt_service.dart';
import 'services/tts_service.dart';
import 'services/inference_service.dart';
import 'services/implementations/llm_implementer.dart';
import 'services/implementations/stt_implementer.dart';
import 'services/implementations/tts_implementer.dart';
import 'services/implementations/groq_implementer.dart';
import 'services/implementations/deepgram_implementer.dart';
import 'services/implementations/deepgram_flux_implementer.dart';
import 'services/implementations/flutter_tts_implementer.dart';
import 'services/implementations/google_cloud_tts_implementer.dart';
import 'services/service_registry.dart';
import 'services/service_builders.dart';
import 'services/coordinator.dart';
import 'services/context_selector.dart';
import 'services/tool_executor.dart';
import 'services/tool_registry.dart';
import 'services/event_bus.dart';
import 'services/event_bus_impl.dart';
import 'services/chunking_service.dart';
import 'services/chunking/semantic_chunker.dart';
import 'services/chunking/chunking_config.dart';
import 'services/chunking/chunk_entity.dart';
import 'services/semantic_search/semantic_search_service.dart';
import 'services/semantic_search/entity_loader_impl.dart';
import 'services/hnsw_index.dart';
import 'core/persistence/persistence_adapter.dart';
import 'tools/task/repositories/task_repository.dart';
import 'tools/timer/repositories/timer_repository.dart';
import 'tools/regulation/repositories/person_repository.dart';
import 'tools/regulation/repositories/regulation_entry_repository.dart';
import 'tools/regulation/repositories/commitment_repository.dart';
import 'tools/regulation/repositories/commitment_log_repository.dart';
import 'core/event_repository.dart';
import 'tools/task/task_tools.dart';
import 'tools/timer/timer_tools.dart';
import 'tools/regulation/regulation_tools.dart';
import 'core/invocation.dart';
import 'core/invocation_repository.dart';
import 'core/entity_repository.dart';
import 'core/adaptation_state_repository.dart';
import 'core/feedback_repository.dart';
import 'core/platform_detector.dart';
import 'bootstrap/implementer_selector.dart';
import 'domain/audio_file.dart';
import 'services/enrichment/enrichment_runner.dart';
import 'services/enrichment/enrichment_worker.dart';
import 'services/enrichment/semantic_enrichment_worker.dart';
import 'core/enrichment_queue_item.dart';
import 'core/enrichment_queue_repository.dart';
import 'core/repository_registry.dart';
import 'persistence/objectbox/audio_file_objectbox_adapter.dart'
    if (dart.library.html) 'persistence/indexeddb/stub.dart';

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

  // 0. Initialize Sentry (DISABLED: Pulls in JNI/Java on Windows)
  // Re-enable for production when Sentry crash reporting needed
  /*
  const isTestMode = bool.fromEnvironment('TEST_MODE', defaultValue: false);
  if (isTestMode) {
    debugPrint('⚠️ Skipping Sentry initialization (TEST_MODE=true)');
  } else {
    const sentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');
    if (sentryDsn.isEmpty) {
      debugPrint('⚠️ SENTRY_DSN not configured - crash reporting disabled');
    } else {
      try {
        // await SentryFlutter.init(...);
        debugPrint('✅ Sentry initialized - crashes will be reported');
      } catch (e) {
        debugPrint('⚠️ Sentry initialization failed: $e');
      }
    }
  }
  */

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

  // 10. STT Service (Speech-to-Text)
  debugPrint('🎤 [STT] Initializing STTService with implementers');
  final sttImplementers = <String, STTImplementer>{};
  if (cfg.deepgramApiKey != null && cfg.deepgramApiKey!.isNotEmpty) {
    // Batch API (legacy) - uses POST to /v1/listen
    sttImplementers['deepgram_batch'] = DeepgramImplementer(
      apiKey: cfg.deepgramApiKey!,
      model: 'nova-2',  // Batch model
    );
    debugPrint('   ✅ DeepgramImplementer (batch) registered');

    // Flux WebSocket API (default) - real-time streaming with turn detection
    sttImplementers['deepgram_flux'] = DeepgramFluxImplementer(
      apiKey: cfg.deepgramApiKey!,
      model: 'flux-general-en',  // Flux model for streaming STT
    );
    debugPrint('   ✅ DeepgramFluxImplementer (streaming) registered');
  }

  if (sttImplementers.isNotEmpty) {
    // Use Flux as default (streaming with turn detection)
    // Fall back to batch if Flux not available
    final defaultSTT = sttImplementers.containsKey('deepgram_flux')
      ? 'deepgram_flux'
      : selectCompatibleImplementer(sttImplementers, 'STT');
    debugPrint('   📍 Platform: $currentPlatform, Selected: $defaultSTT');

    final sttService = STTService(
      implementers: sttImplementers,
      defaultImplementer: defaultSTT,
      invocationRepo: invocationRepo,
      adaptationStateRepo: getIt<AdaptationStateRepository>(),
      feedbackRepo: getIt<FeedbackRepository>(),
    );
    getIt.registerSingleton<STTService>(sttService);
    debugPrint('   ✅ STTService registered with ${sttImplementers.length} implementer(s)');
  } else {
    debugPrint('   ⏭️  STTService skipped (no API key configured)');
  }

  // 11. TTS Service (Text-to-Speech)
  debugPrint('🔊 [TTS] Initializing TTSService with implementers');
  final ttsImplementers = <String, TTSImplementer>{
    'flutter_tts': FlutterTtsImplementer(),
  };

  // Add Google Cloud TTS if API key provided (fallback for Linux, works everywhere)
  if (cfg.googleTtsApiKey != null && cfg.googleTtsApiKey!.isNotEmpty) {
    ttsImplementers['google_cloud_tts'] = GoogleCloudTTSImplementer(
      apiKey: cfg.googleTtsApiKey!,
    );
    debugPrint('   ✅ GoogleCloudTTSImplementer registered');
  }

  // Auto-select first implementer compatible with current platform
  final defaultTTS = selectCompatibleImplementer(ttsImplementers, 'TTS');
  debugPrint('   📍 Platform: $currentPlatform, Selected: $defaultTTS');

  final ttsService = TTSService(
    implementers: ttsImplementers,
    defaultImplementer: defaultTTS,
    invocationRepo: invocationRepo,
    adaptationStateRepo: getIt<AdaptationStateRepository>(),
    feedbackRepo: getIt<FeedbackRepository>(),
  );
  getIt.registerSingleton<TTSService>(ttsService);
  debugPrint('   ✅ TTSService registered with ${ttsImplementers.length} implementer(s)');

  // 12. LLM Service (Inference)
  debugPrint('🧠 [LLM] Initializing InferenceService with implementers');
  final llmImplementers = <String, LLMImplementer>{};
  if (cfg.groqApiKey != null && cfg.groqApiKey!.isNotEmpty) {
    llmImplementers['groq'] = GroqImplementer(apiKey: cfg.groqApiKey!);
    debugPrint('   ✅ GroqImplementer registered');
  }

  if (llmImplementers.isNotEmpty) {
    // Auto-select first implementer compatible with current platform
    final defaultLLM = selectCompatibleImplementer(llmImplementers, 'LLM');
    debugPrint('   📍 Platform: $currentPlatform, Selected: $defaultLLM');

    final llmService = InferenceService(
      implementers: llmImplementers,
      defaultImplementer: defaultLLM,
      invocationRepo: invocationRepo,
      adaptationStateRepo: getIt<AdaptationStateRepository>(),
      feedbackRepo: getIt<FeedbackRepository>(),
    );
    getIt.registerSingleton<InferenceService>(llmService);
    debugPrint('   ✅ InferenceService registered with ${llmImplementers.length} implementer(s)');
  } else {
    debugPrint('   ⏭️  InferenceService skipped (no API key configured)');
  }

  // 13. Initialize Embedding Service
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

  // 14. Initialize Semantic Search Infrastructure (ChunkingService + SemanticSearchService)
  debugPrint('🔍 Initializing semantic search infrastructure...');
  try {
    // Create HNSW index
    final hnswIndex = HnswIndex(dimensions: 384);

    // Create parent and child chunkers
    final parentChunker = SemanticChunker(config: ChunkingConfig.parent());
    final childChunker = SemanticChunker(config: ChunkingConfig.child());

    // Get ChunkEntity box from persistence
    final store = getIt<Store>();
    final chunkBox = store.box<ChunkEntity>();

    // Create ChunkingService
    final chunkingService = ChunkingService(
      index: hnswIndex,
      embeddingService: EmbeddingService.instance,
      parentChunker: parentChunker,
      childChunker: childChunker,
      chunkBox: chunkBox,
    );
    getIt.registerSingleton<ChunkingService>(chunkingService);
    debugPrint('✅ ChunkingService initialized');

    // Register HNSW index for direct access
    getIt.registerSingleton<HnswIndex>(hnswIndex);
    debugPrint('✅ HNSW index registered');

    // Create SemanticSearchService
    final entityLoader = EntityLoaderImpl();
    final semanticSearchService = SemanticSearchService(
      index: hnswIndex,
      embeddingService: EmbeddingService.instance,
      entityLoader: entityLoader,
      chunkingService: chunkingService,
    );
    getIt.registerSingleton<SemanticSearchService>(semanticSearchService);
    debugPrint('✅ SemanticSearchService initialized');

    // Create RepositoryRegistry for worker entity lookups
    final repoRegistry = RepositoryRegistry();
    getIt.registerSingleton<RepositoryRegistry>(repoRegistry);
    debugPrint('✅ RepositoryRegistry initialized');

    // Create EnrichmentQueueRepository (adapter created by platform-specific code)
    // Note: EnrichmentQueue adapter is registered by persistence initialization
    EnrichmentQueueRepository? enrichmentQueueRepo;
    EnrichmentRunner? enrichmentRunner;
    try {
      final enrichmentQueueAdapter = getIt<EnrichmentQueueAdapter>();
      enrichmentQueueRepo = EnrichmentQueueRepository(adapter: enrichmentQueueAdapter);
      getIt.registerSingleton<EnrichmentQueueRepository>(enrichmentQueueRepo);
      debugPrint('✅ EnrichmentQueueRepository initialized');

      // Create EnrichmentRunner with workers
      enrichmentRunner = EnrichmentRunner(
        queueRepo: enrichmentQueueRepo,
        workers: [
          SemanticEnrichmentWorker(
            chunkingService: chunkingService,
            repoRegistry: repoRegistry,
          ),
        ],
        batchSize: 10,
      );
      getIt.registerSingleton<EnrichmentRunner>(enrichmentRunner);
      debugPrint('✅ EnrichmentRunner initialized with SemanticEnrichmentWorker');

      // Initialize runner (startup recovery)
      await enrichmentRunner.initialize();
      debugPrint('✅ EnrichmentRunner startup recovery complete');
    } catch (e) {
      debugPrint('⚠️ EnrichmentRunner initialization failed: $e');
      debugPrint('   Continuing without async enrichment...');
    }

    // Wire InvocationRepository with SemanticIndexableHandler and EnrichmentRunner
    try {
      final adapterRegistration = getIt<InvocationRepository<Invocation>>();

      // Create EntityRepository with semantic indexing handler and enrichment runner
      // This wraps the adapter with SemanticIndexableHandler for automatic chunking
      final invocationRepo = createInvocationRepository(
        adapter: adapterRegistration as PersistenceAdapter<Invocation>,
        embeddingService: EmbeddingService.instance,
        chunkingService: chunkingService,
        enrichmentRunner: enrichmentRunner,
      );

      // Register EntityRepository (NOT InvocationRepository - different types!)
      // EntityRepository has the handlers, InvocationRepository is the bare adapter
      getIt.registerSingleton<EntityRepository<Invocation>>(invocationRepo);
      debugPrint('✅ InvocationRepository wired with SemanticIndexableHandler (EntityRepository)');

      // Register invocation repo in RepositoryRegistry for worker entity lookups
      repoRegistry.register<Invocation>(invocationRepo);
      debugPrint('✅ Invocation registered in RepositoryRegistry');
    } catch (e) {
      debugPrint('⚠️ Failed to wire InvocationRepository handler: $e');
      // Don't rethrow - handler wiring is optional, semantic search works without it
    }
  } catch (e) {
    debugPrint('⚠️ Semantic search initialization failed: $e');
  }

  // 14. Initialize Audio Recording Service (Microphone Input)
  try {
    await AudioRecordingService.instance.initialize();
    debugPrint('✅ Audio: AudioRecordingService');
  } catch (e) {
    debugPrint('⚠️ Audio recording service init failed: $e');
  }

  // 15. Initialize Audio Storage Service
  try {
    // Wrap AudioFile adapter in EntityRepository now that EmbeddingService is ready
    final audioFileAdapter = getIt<AudioFileObjectBoxAdapter>();
    final audioFileRepo = EntityRepository<AudioFile>(
      adapter: audioFileAdapter,
      embeddingService: EmbeddingService.instance,
    );
    getIt.registerSingleton<EntityRepository<AudioFile>>(audioFileRepo);

    final audioStorage = AudioStorage(audioFileRepo);
    getIt.registerSingleton<AudioStorage>(audioStorage);
    debugPrint('✅ Audio: AudioStorage');
  } catch (e) {
    debugPrint('⚠️ Audio storage service init failed: $e');
  }

  // 14. Initialize STT Service (Speech-to-Text) with implementers
  // TODO: STTService initialization
  // Requires concrete implementation (STTService is abstract)
  // debugPrint('🎤 [STT] Initializing STTService with implementers');
  // final sttImplementers = <String, STTImplementer>{};
  //
  // // Add Deepgram implementer if API key provided
  // if (cfg.deepgramApiKey != null && cfg.deepgramApiKey!.isNotEmpty) {
  //   sttImplementers['deepgram'] = DeepgramImplementer(apiKey: cfg.deepgramApiKey!);
  //   debugPrint('✅ STT: DeepgramImplementer registered');
  // }
  //
  // // Only register if we have implementers
  // if (sttImplementers.isNotEmpty) {
  //   final sttService = STTService(
  //     implementers: sttImplementers,
  //     defaultImplementer: 'deepgram',
  //     invocationRepo: getIt<InvocationRepository<Invocation>>(),
  //     adaptationStateRepo: getIt<AdaptationStateRepository>(),
  //     feedbackRepo: getIt<FeedbackRepository>(),
  //   );
  //   getIt.registerSingleton<STTService>(sttService);
  //   debugPrint('✅ STT: STTService (deepgram)');
  // } else {
  //   debugPrint('⚠️ Deepgram API key missing');
  //   debugPrint('ℹ️ STT: disabled');
  //   // Register a disabled STT service (empty implementer map)
  //   final nullSttService = STTService(
  //     implementers: {},
  //     defaultImplementer: 'null',
  //     invocationRepo: getIt<InvocationRepository<Invocation>>(),
  //     adaptationStateRepo: getIt<AdaptationStateRepository>(),
  //     feedbackRepo: getIt<FeedbackRepository>(),
  //   );
  //   getIt.registerSingleton<STTService>(nullSttService);
  // }

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

    // Check service registration status (registered in bootstrap if API keys present)
    final hasInference = getIt.isRegistered<InferenceService>();
    final hasTTS = getIt.isRegistered<TTSService>();
    final hasSTT = getIt.isRegistered<STTService>();
    debugPrint('📊 [setupServiceLocator] Service status: Inference=$hasInference, TTS=$hasTTS, STT=$hasSTT');

    // ========== Domain Repositories (Already registered in initializeEverythingStack) ==========
    // InvocationRepository, AdaptationStateRepository, FeedbackRepository, TurnRepository
    // are already registered as singletons in initializeEverythingStack().
    // They don't need to be re-registered here.

    // ========== Trainable Selectors (Removed - dead code) ==========
    // These classes were deleted in Phase 8 cleanup
    // TODO: Coordinator needs refactoring to remove dependency on these
    // For now, commented out to allow app to compile for semantic search testing

    // debugPrint('🔍 [setupServiceLocator] Registering NamespaceSelector...');
    // getIt.registerSingleton<NamespaceSelector>(...)
    // debugPrint('✅ [setupServiceLocator] NamespaceSelector registered');

    // ========== Tool Registry ==========

    getIt.registerSingleton<ToolRegistry>(ToolRegistry());

    // ========== Task Repository (Owns adapter selection internally) ==========

    final taskRepo = TaskRepository();
    getIt.registerSingleton<TaskRepository>(taskRepo);

    // Register task tools with registry
    registerTaskTools(getIt<ToolRegistry>(), taskRepo);

    // ========== Timer Repository (Owns adapter selection internally) ==========

    final timerRepo = TimerRepository();
    getIt.registerSingleton<TimerRepository>(timerRepo);

    // Register timer tools with registry
    registerTimerTools(getIt<ToolRegistry>(), timerRepo);
    debugPrint('✅ [setupServiceLocator] Timer tools registered (timer.set, timer.cancel, timer.list)');

    // ========== Regulation Repositories (Owns adapter selection internally) ==========

    final personRepo = PersonRepository();
    getIt.registerSingleton<PersonRepository>(personRepo);

    final regulationEntryRepo = RegulationEntryRepository();
    getIt.registerSingleton<RegulationEntryRepository>(regulationEntryRepo);

    final commitmentRepo = CommitmentRepository();
    getIt.registerSingleton<CommitmentRepository>(commitmentRepo);

    final commitmentLogRepo = CommitmentLogRepository();
    getIt.registerSingleton<CommitmentLogRepository>(commitmentLogRepo);

    // Register regulation tools with registry
    registerRegulationTools(
      getIt<ToolRegistry>(),
      personRepo,
      regulationEntryRepo,
      commitmentRepo,
      commitmentLogRepo,
    );
    debugPrint('✅ [setupServiceLocator] Regulation tools registered (regulation.log_entry, regulation.log_commitment, commitment.create, commitment.list)');

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
        toolRegistry: getIt<ToolRegistry>(),
        eventBus: eventBus,
      ),
    );

    // ========== Tool Selector (Deferred - needs semantic indexing) ==========
    // TODO: Register ToolSelector once semantic indexing of tool invocations is implemented
    // Currently it's just a stub that returns all tools

    // ========== Context Selector (Trainable context gathering) ==========
    debugPrint('🔍 [setupServiceLocator] Registering ContextSelector...');

    final contextSelector = ContextSelector(
      invocationRepo: getIt<EntityRepository<Invocation>>(),
      embeddingService: EmbeddingService.instance,
    );
    getIt.registerSingleton<ContextSelector>(contextSelector);
    debugPrint('✅ [setupServiceLocator] ContextSelector registered');

    // ========== Coordinator (Multi-turn context management) ==========
    // Only register if InferenceService and TTSService exist
    if (getIt.isRegistered<InferenceService>() && getIt.isRegistered<TTSService>()) {
      debugPrint('🔍 [setupServiceLocator] Registering Coordinator...');

      final coordinator = Coordinator(
        embeddingService: EmbeddingService.instance,
        llmService: getIt<InferenceService>(),
        ttsService: getIt<TTSService>(),
        toolExecutor: getIt<ToolExecutor>(),
        contextSelector: getIt<ContextSelector>(),
        invocationRepo: getIt<InvocationRepository<Invocation>>(),
        eventBus: getIt<EventBus>(),
      );
      getIt.registerSingleton<Coordinator>(coordinator);
      coordinator.initialize();
      debugPrint('✅ [setupServiceLocator] Coordinator registered and initialized');
    } else {
      debugPrint('⏭️ [setupServiceLocator] Coordinator skipped (InferenceService/TTSService not registered)');
    }

    debugPrint('🎉 [setupServiceLocator] ALL SERVICES REGISTERED SUCCESSFULLY');
  } catch (e, st) {
    debugPrint('❌ [setupServiceLocator] ERROR: $e');
    debugPrint('Stack trace: $st');
    rethrow;
  }
}