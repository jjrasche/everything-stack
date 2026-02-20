library;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
// import 'package:sentry_flutter/sentry_flutter.dart';  // DISABLED: Pulls in JNI (Java) on Windows

// Conditional ObjectBox import: Stub on web (default), real package on native
// IMPORTANT: Do NOT import stubs unconditionally - causes type mismatch bugs!
// The stub Store class conflicts with the real ObjectBox Store type.
import 'bootstrap/objectbox_stub_ignore.dart' as objectbox
    if (dart.library.io) 'package:objectbox/objectbox.dart';

import 'services/blob_store.dart';
import 'services/sync_service.dart';
import 'services/connectivity_service.dart';
import 'services/embedding_service.dart';
import 'services/tokenizer_service.dart';
import 'services/embedding_queue_service.dart';
import 'services/debug/debug_bootstrap.dart';
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
import 'services/execution_loop.dart';
import 'services/context_selector.dart';
import 'services/trainables/model_selector.dart';
import 'services/voice_traits.dart';
import 'services/context_capacity.dart';
import 'services/tool_executor.dart';
import 'services/tool_registry.dart';
import 'services/event_bus.dart';
import 'services/event_bus_impl.dart';
import 'services/chunking_service.dart';
import 'services/chunking/semantic_chunker.dart';
import 'services/chunking/chunking_config.dart';
import 'core/chunk_repository.dart';
// Conditional import: web stub default, native adapter if dart.library.io
import 'persistence/indexeddb/chunk_indexeddb_adapter.dart'
    if (dart.library.io) 'persistence/objectbox/chunk_objectbox_adapter.dart';
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
import 'domain/atomic_insight.dart';
import 'domain/atomic_insight_repository.dart';
import 'services/extraction/atomic_insight_extractor.dart';
import 'training/extraction/extraction_evaluator.dart';
import 'training/extraction/extraction_improvement_loop.dart';
import 'services/prompt/prompt_registry.dart';
import 'services/prompt/prompt_mutator.dart';
import 'services/prompt/prompt_validator.dart';
import 'domain/prompt_version.dart';
import 'domain/prompt_version_repository.dart';
import 'domain/proposition.dart';
import 'domain/proposition_repository.dart';
import 'services/memory/working_memory_service.dart';
import 'services/memory/encoder.dart';
import 'services/memory/stages/normalize_stage.dart';
import 'services/memory/stages/segment_stage.dart';
import 'services/memory/stages/cohere_stage.dart';
import 'services/memory/stages/recohere_stage.dart';
import 'services/memory/stages/filter_stage.dart';
import 'services/slm/runners/filter_runner.dart';
import 'services/memory/stages/decontextualize_stage.dart';
import 'services/memory/stages/dedup_stage.dart';
import 'services/enrichment/enrichment_runner.dart';
import 'services/enrichment/enrichment_worker.dart';
import 'services/enrichment/semantic_enrichment_worker.dart';
import 'core/enrichment_queue_item.dart';
import 'core/enrichment_queue_repository.dart';
import 'core/repository_registry.dart';
// AudioFile adapter registered in platform-specific persistence files
// Native: persistence/objectbox/audio_file_objectbox_adapter.dart
// Web: persistence/indexeddb/audio_file_indexeddb_adapter.dart

// Platform-specific persistence initialization (ObjectBox or IndexedDB)
import 'bootstrap/persistence_web.dart'
    if (dart.library.io) 'bootstrap/persistence_native.dart';

// Platform-specific BlobStore factory
import 'bootstrap/blob_store_factory_web.dart'
    if (dart.library.io) 'bootstrap/blob_store_factory_io.dart';

// Platform-specific EmbeddingTaskStore factory
import 'services/embedding_task_store_web.dart'
    if (dart.library.io) 'services/embedding_task_store_native.dart';

// Platform-specific HnswIndexStore (persistence for pre-built HNSW index)
import 'services/hnsw_index_store.dart';
import 'services/hnsw_index_store_web.dart'
    if (dart.library.io) 'services/hnsw_index_store_native.dart';

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
    debugPrint(
        'ℹ️ [Bootstrap] .env not found, falling back to compile-time env vars');
  }

  try {
    final cfg = config ?? EverythingStackConfig.fromEnvironment();
    debugPrint('✅ [Bootstrap] Configuration loaded successfully');
    debugPrint(
        '🔑 Config loaded - Deepgram key present: ${cfg.deepgramApiKey != null}');
    debugPrint(
        '🔑 Config loaded - Groq key present: ${cfg.groqApiKey != null}');
    return _initializeServices(cfg);
  } catch (e, st) {
    debugPrint('❌ [Bootstrap] FATAL ERROR during initialization: $e');
    debugPrint('Stack trace: $st');
    rethrow;
  }
}

Future<void> _initializeServices(EverythingStackConfig cfg) async {
  try {
    debugPrint('💾 Initializing persistence layer...');
    debugPrint('🔍 [bootstrap] Before calling initializePersistence:');
    debugPrint('   getIt hashCode: ${getIt.hashCode}');
    debugPrint('   GetIt.instance hashCode: ${GetIt.instance.hashCode}');
    await initializePersistence(getIt);
    debugPrint('🔍 [bootstrap] After initializePersistence:');
    debugPrint('   getIt hashCode: ${getIt.hashCode}');
    debugPrint('   objectbox.Store registered in getIt? ${getIt.isRegistered<objectbox.Store>()}');
    debugPrint('   objectbox.Store registered in GetIt.instance? ${GetIt.instance.isRegistered<objectbox.Store>()}');

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
        model: 'nova-2', // Batch model
      );
      debugPrint('   ✅ DeepgramImplementer (batch) registered');

      // Flux WebSocket API (default) - real-time streaming with turn detection
      sttImplementers['deepgram_flux'] = DeepgramFluxImplementer(
        apiKey: cfg.deepgramApiKey!,
        model: 'flux-general-en', // Flux model for streaming STT
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
      debugPrint(
          '   ✅ STTService registered with ${sttImplementers.length} implementer(s)');
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
    debugPrint(
        '   ✅ TTSService registered with ${ttsImplementers.length} implementer(s)');

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
      debugPrint(
          '   ✅ InferenceService registered with ${llmImplementers.length} implementer(s)');
    } else {
      debugPrint('   ⏭️  InferenceService skipped (no API key configured)');
    }

    // 13. Initialize Embedding Service
    debugPrint('🔍 [bootstrap] Before EmbeddingService init: objectbox.Store registered? ${getIt.isRegistered<objectbox.Store>()}');
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
      setInstance: (service) {
        EmbeddingService.instance = service;
      },
      shouldInitialize: (service) => service is! NullEmbeddingService,
      getType: (service) => service.runtimeType,
    );
    debugPrint('🔍 [bootstrap] After EmbeddingService init: objectbox.Store registered? ${getIt.isRegistered<objectbox.Store>()}');

    // 14. Initialize Semantic Search Infrastructure (ChunkingService + SemanticSearchService)
    // NOTE: Disabled on Web - ObjectBox (dart:ffi) not available on Web platform
    if (!kIsWeb) {
      debugPrint('🔍 Initializing semantic search infrastructure...');
      try {
        // Try loading pre-built HNSW index from cache (fast path: ~100ms)
        // Fall back to creating empty index if not cached
        final indexStore = createHnswIndexStore(_getIndexStorePath());
        final loadResult = await indexStore.loadIndex();

        HnswIndex hnswIndex;
        bool needsRebuild = false;

        if (loadResult.isLoaded) {
          // Fast path: Use cached index directly
          hnswIndex = loadResult.index!;
          debugPrint('⚡ HNSW index loaded from cache: ${hnswIndex.size} vectors');
          debugPrint('   ${loadResult.metadata}');
        } else {
          // Cache not available - will need to rebuild
          hnswIndex = HnswIndex(dimensions: 384);
          needsRebuild = true;
          if (loadResult.hasFailed) {
            debugPrint('⚠️ Cache load failed: ${loadResult.error}');
          } else {
            debugPrint('📭 No cached index found');
          }
        }

      final parentChunker = SemanticChunker(config: ChunkingConfig.parent());
      final childChunker = SemanticChunker(config: ChunkingConfig.child());

      debugPrint('🔍 [semantic search] Retrieving ChunkRepository from GetIt...');
      final chunkRepo = getIt<ChunkRepository>();
      debugPrint('   ✓ ChunkRepository retrieved successfully');

      final chunkingService = ChunkingService(
        index: hnswIndex,
        embeddingService: EmbeddingService.instance,
        tokenizerService: TokenizerService.instance,
        parentChunker: parentChunker,
        childChunker: childChunker,
        chunkRepo: chunkRepo,
      );
      getIt.registerSingleton<ChunkingService>(chunkingService);
      debugPrint('✅ ChunkingService initialized');

      // Rebuild from database if cache wasn't available
      if (needsRebuild) {
        debugPrint('🔄 Rebuilding HNSW index from database...');
        final stopwatch = Stopwatch()..start();

        final loadedChunks = await chunkingService.rebuildIndexFromStorage();
        stopwatch.stop();
        debugPrint('✅ HNSW index rebuilt with $loadedChunks chunks (${stopwatch.elapsedMilliseconds}ms)');

        // Save for next startup (background, don't block)
        if (hnswIndex.size > 0) {
          indexStore.saveIndex(hnswIndex).then((_) {
            debugPrint('💾 HNSW index cached for next startup');
          }).catchError((e) {
            debugPrint('⚠️ Failed to cache HNSW index: $e');
          });
        }
      }

      // Register index store for later updates (e.g., after new entities indexed)
      getIt.registerSingleton<HnswIndexStore>(indexStore);

      getIt.registerSingleton<HnswIndex>(hnswIndex);
      debugPrint('✅ HNSW index registered (${hnswIndex.size} vectors)');

      final entityLoader = EntityLoaderImpl();
      entityLoader.registerDefaults(); // Register Invocation lookup (add more as needed)
      final semanticSearchService = SemanticSearchService(
        index: hnswIndex,
        embeddingService: EmbeddingService.instance,
        entityLoader: entityLoader,
        chunkingService: chunkingService,
      );
      getIt.registerSingleton<SemanticSearchService>(semanticSearchService);
      debugPrint('✅ SemanticSearchService initialized');

      final repoRegistry = RepositoryRegistry();
      getIt.registerSingleton<RepositoryRegistry>(repoRegistry);
      debugPrint('✅ RepositoryRegistry initialized');

      // Note: EnrichmentQueue adapter is registered by persistence initialization
      EnrichmentQueueRepository? enrichmentQueueRepo;
      EnrichmentRunner? enrichmentRunner;
      try {
        final enrichmentQueueAdapter = getIt<EnrichmentQueueAdapter>();
        enrichmentQueueRepo =
            EnrichmentQueueRepository(adapter: enrichmentQueueAdapter);
        getIt.registerSingleton<EnrichmentQueueRepository>(enrichmentQueueRepo);
        debugPrint('✅ EnrichmentQueueRepository initialized');

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
        debugPrint(
            '✅ EnrichmentRunner initialized with SemanticEnrichmentWorker');

        // Initialize runner (startup recovery)
        await enrichmentRunner.initialize();
        debugPrint('✅ EnrichmentRunner startup recovery complete');
      } catch (e) {
        debugPrint('⚠️ EnrichmentRunner initialization failed: $e');
        debugPrint('   Continuing without async enrichment...');
      }

      // Wire InvocationRepository with SemanticIndexableHandler and EnrichmentRunner
      try {
        debugPrint('🔍 Attempting to wire InvocationRepository...');
        final adapterRegistration = getIt<InvocationRepository<Invocation>>();
        debugPrint('   ✓ Retrieved InvocationRepository from GetIt');

        debugPrint('   🔍 Creating EntityRepository wrapper...');
        final invocationRepo = createInvocationRepository(
          adapter: adapterRegistration as PersistenceAdapter<Invocation>,
          embeddingService: EmbeddingService.instance,
          chunkingService: chunkingService,
          enrichmentRunner: enrichmentRunner,
        );
        debugPrint('   ✓ EntityRepository created successfully');

        // Register EntityRepository (NOT InvocationRepository - different types!)
        // EntityRepository has the handlers, InvocationRepository is the bare adapter
        debugPrint('   🔍 Registering EntityRepository<Invocation>...');
        getIt.registerSingleton<EntityRepository<Invocation>>(invocationRepo);
        debugPrint(
            '✅ InvocationRepository wired with SemanticIndexableHandler (EntityRepository)');

        repoRegistry.register<Invocation>(invocationRepo);
        debugPrint('✅ Invocation registered in RepositoryRegistry');
      } catch (e, stackTrace) {
        debugPrint('⚠️ Failed to wire InvocationRepository handler: $e');
        debugPrint('   Stack trace: $stackTrace');
        // CRITICAL: Rethrow because ContextSelector requires EntityRepository<Invocation>
        rethrow;
      }
      } catch (e, stackTrace) {
        debugPrint('⚠️ Semantic search initialization failed: $e');
        debugPrint('   Stack trace: $stackTrace');
        // CRITICAL: If EntityRepository<Invocation> wasn't registered, tests will fail
        if (!getIt.isRegistered<EntityRepository<Invocation>>()) {
          debugPrint('   ❌ FATAL: EntityRepository<Invocation> not registered - rethrowing');
          rethrow;
        }
      }
    } else {
      debugPrint(
          '⚠️  Semantic search disabled on Web (ObjectBox/dart:ffi not available)');
      debugPrint('   App will function without semantic search capabilities');
    }

    // 15. Initialize Audio Recording Service (Microphone Input)
    try {
      await AudioRecordingService.instance.initialize();
      debugPrint('✅ Audio: AudioRecordingService');
    } catch (e) {
      debugPrint('⚠️ Audio recording service init failed: $e');
    }

    // 15. Initialize Audio Storage Service
    try {
      // Wrap AudioFile adapter in EntityRepository now that EmbeddingService is ready
      final audioFileAdapter = getIt<PersistenceAdapter<AudioFile>>();
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

    // 16. Initialize AtomicInsight Repository and Extractor
    try {
      final atomicInsightAdapter = getIt<PersistenceAdapter<AtomicInsight>>();
      final atomicInsightRepo = AtomicInsightRepository(
        adapter: atomicInsightAdapter,
        embeddingService: EmbeddingService.instance,
        embeddingQueueService: embeddingQueueService,
      );
      getIt.registerSingleton<AtomicInsightRepository>(atomicInsightRepo);
      debugPrint('✅ AtomicInsight: Repository registered');

      // PromptVersion repository for versioned prompt storage
      final promptVersionAdapter = getIt<PersistenceAdapter<PromptVersion>>();
      final promptVersionRepo = PromptVersionRepository(
        adapter: promptVersionAdapter,
      );
      getIt.registerSingleton<PromptVersionRepository>(promptVersionRepo);
      debugPrint('✅ PromptVersion: Repository registered');

      if (getIt.isRegistered<InferenceService>()) {
        final inferenceService = getIt<InferenceService>();

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
        debugPrint('✅ AtomicInsight: Extractor registered');

        final evaluator = ExtractionEvaluator(
          inferenceService: inferenceService,
        );
        getIt.registerSingleton<ExtractionEvaluator>(evaluator);
        debugPrint('✅ AtomicInsight: Evaluator registered');

        final mutator = PromptMutator(inferenceService: inferenceService);
        final validator = PromptValidator();
        final improvementLoop = ExtractionImprovementLoop(
          extractor: extractor,
          evaluator: evaluator,
          promptRegistry: promptRegistry,
          mutator: mutator,
          validator: validator,
        );
        getIt.registerSingleton<ExtractionImprovementLoop>(improvementLoop);
        debugPrint('✅ AtomicInsight: Improvement loop registered');
      } else {
        debugPrint('⚠️ AtomicInsight: InferenceService not available, extractor/evaluator skipped');
      }
    } catch (e) {
      debugPrint('⚠️ AtomicInsight initialization failed: $e');
    }

    // 17. Initialize Memory System (Encoder + Working Memory)
    try {
      final propositionAdapter = getIt<PersistenceAdapter<Proposition>>();
      final propositionRepo = PropositionRepository(
        adapter: propositionAdapter,
      );
      getIt.registerSingleton<PropositionRepository>(propositionRepo);

      final wmService = WorkingMemoryService();
      getIt.registerSingleton<WorkingMemoryService>(wmService);

      if (getIt.isRegistered<InferenceService>()) {
        final inferenceService = getIt<InferenceService>();
        final decontextStage = DecontextualizeStage(
          chatClient: inferenceService,
        );
        final encoder = Encoder(
          normalizeStage: NormalizeStage(),
          segmentStage: SegmentStage(),
          cohereStage: CohereStage(chatClient: inferenceService),
          recoherStage: RecoherStage(),
          // FilterRunner provided after SLM model is trained and deployed
          filterStage: FilterStage(filterRunner: _PassthroughFilterRunner()),
          decontextualizeStage: decontextStage,
          dedupStage: DedupStage(
            chatClient: inferenceService,
            decontextualizeStage: decontextStage,
          ),
        );
        getIt.registerSingleton<Encoder>(encoder);
        debugPrint('✅ Memory: Encoder + WorkingMemory registered');
      } else {
        debugPrint('⚠️ Memory: InferenceService not available, encoder skipped');
      }
    } catch (e) {
      debugPrint('⚠️ Memory system initialization failed: $e');
    }

    // Domain repositories (Task, Timer, etc.) are initialized by the
    // application layer, not bootstrap. See lib/providers/ and lib/main.dart.
    await initializeDebugInfrastructure();

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

  try {
    final executionLoop = getIt<ExecutionLoop>();
    executionLoop.dispose();
  } catch (e) {
    debugPrint('⚠️ ExecutionLoop not registered, skipping disposal');
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

  disposePersistence(getIt);

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
  debugPrint(
      '[setupServiceLocator] 🚀🚀🚀 FUNCTION CALLED - STARTING SERVICE REGISTRATION');
  debugPrint('🚀 [setupServiceLocator] Starting service registration...');

  try {
    // ========== External APIs (Abstraction-Respecting) ==========

    // EmbeddingService - loaded from config, respects abstraction
    getIt.registerSingleton<EmbeddingService>(
      EmbeddingService.instance, // Already initialized by bootstrap
    );
    debugPrint('✅ [setupServiceLocator] EmbeddingService registered');

    // TokenizerService - for accurate GPT token counting
    getIt.registerSingleton<TokenizerService>(TokenizerService.instance);
    debugPrint('✅ [setupServiceLocator] TokenizerService registered');

    // Check service registration status (registered in bootstrap if API keys present)
    final hasInference = getIt.isRegistered<InferenceService>();
    final hasTTS = getIt.isRegistered<TTSService>();
    final hasSTT = getIt.isRegistered<STTService>();
    debugPrint(
        '📊 [setupServiceLocator] Service status: Inference=$hasInference, TTS=$hasTTS, STT=$hasSTT');

    // ========== Domain Repositories (Already registered in initializeEverythingStack) ==========
    // InvocationRepository, AdaptationStateRepository, FeedbackRepository, TurnRepository
    // are already registered as singletons in initializeEverythingStack().
    // They don't need to be re-registered here.

    // ========== Trainable Selectors (Removed - dead code) ==========
    // These classes were deleted in Phase 8 cleanup
    // TODO: ExecutionLoop needs refactoring to remove dependency on these
    // For now, commented out to allow app to compile for semantic search testing

    // debugPrint('🔍 [setupServiceLocator] Registering NamespaceSelector...');
    // getIt.registerSingleton<NamespaceSelector>(...)
    // debugPrint('✅ [setupServiceLocator] NamespaceSelector registered');

    // ========== Tool Registry ==========

    getIt.registerSingleton<ToolRegistry>(ToolRegistry());

    // ========== Task Repository (Owns adapter selection internally) ==========

    final taskRepo = TaskRepository();
    getIt.registerSingleton<TaskRepository>(taskRepo);

    registerTaskTools(getIt<ToolRegistry>(), taskRepo);

    // ========== Timer Repository (Owns adapter selection internally) ==========

    final timerRepo = TimerRepository();
    getIt.registerSingleton<TimerRepository>(timerRepo);

    registerTimerTools(getIt<ToolRegistry>(), timerRepo);
    debugPrint(
        '✅ [setupServiceLocator] Timer tools registered (timer.set, timer.cancel, timer.list)');

    // ========== Regulation Repositories (Owns adapter selection internally) ==========

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
    debugPrint(
        '✅ [setupServiceLocator] Regulation tools registered (regulation.log_entry, regulation.log_commitment, commitment.create, commitment.list)');

    // ========== Event Bus (Pub/sub with persistence) ==========
    debugPrint('🔍 [setupServiceLocator] Initializing EventBus...');

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
      semanticSearchService: getIt<SemanticSearchService>(),
    );
    getIt.registerSingleton<ContextSelector>(contextSelector);
    debugPrint('✅ [setupServiceLocator] ContextSelector registered');

    // ========== Model Selector (Thompson Sampling model selection) ==========
    debugPrint('🔍 [setupServiceLocator] Registering ModelSelector...');

    Map<String, List<String>> availableModels = {};
    if (getIt.isRegistered<InferenceService>()) {
      availableModels = getIt<InferenceService>().getAvailableModels();
      debugPrint('   📋 Available models from implementers:');
      for (final entry in availableModels.entries) {
        debugPrint('      ${entry.key}: ${entry.value.join(", ")}');
      }
    } else {
      debugPrint('   ⚠️ InferenceService not registered, using empty model list');
    }

    final modelSelector = ModelSelector(availableModels: availableModels);
    getIt.registerSingleton<ModelSelector>(modelSelector);
    debugPrint('✅ [setupServiceLocator] ModelSelector registered');

    // ========== VoiceTraits (Contrastive few-shot examples) ==========
    debugPrint('🔍 [setupServiceLocator] Registering VoiceTraits...');
    VoiceTraits? voiceTraits;
    if (getIt.isRegistered<SemanticSearchService>() &&
        getIt.isRegistered<FeedbackRepository>()) {
      voiceTraits = VoiceTraits(
        searchService: getIt<SemanticSearchService>(),
        invocationRepo: getIt<InvocationRepository<Invocation>>(),
        feedbackRepo: getIt<FeedbackRepository>(),
      );
      getIt.registerSingleton<VoiceTraits>(voiceTraits);
      debugPrint('✅ [setupServiceLocator] VoiceTraits registered');
    } else {
      debugPrint('⏭️ [setupServiceLocator] VoiceTraits skipped (dependencies not registered)');
    }

    // ========== ContextCapacity (Token budget management) ==========
    debugPrint('🔍 [setupServiceLocator] Registering ContextCapacity...');
    final contextCapacity = ContextCapacity();
    getIt.registerSingleton<ContextCapacity>(contextCapacity);
    debugPrint('✅ [setupServiceLocator] ContextCapacity registered');

    // ========== ExecutionLoop (Multi-turn context management) ==========
    // Only register if InferenceService and TTSService exist
    if (getIt.isRegistered<InferenceService>() &&
        getIt.isRegistered<TTSService>()) {
      debugPrint('🔍 [setupServiceLocator] Registering ExecutionLoop...');

      final executionLoop = ExecutionLoop(
        embeddingService: EmbeddingService.instance,
        llmService: getIt<InferenceService>(),
        ttsService: getIt<TTSService>(),
        toolExecutor: getIt<ToolExecutor>(),
        contextSelector: getIt<ContextSelector>(),
        modelSelector: getIt<ModelSelector>(),
        voiceTraits: voiceTraits,
        contextCapacity: contextCapacity,
        invocationRepo: getIt<InvocationRepository<Invocation>>(),
        eventBus: getIt<EventBus>(),
      );
      getIt.registerSingleton<ExecutionLoop>(executionLoop);
      executionLoop.initialize();
      debugPrint(
          '✅ [setupServiceLocator] ExecutionLoop registered and initialized');
    } else {
      debugPrint(
          '⏭️ [setupServiceLocator] ExecutionLoop skipped (InferenceService/TTSService not registered)');
    }

    debugPrint('🎉 [setupServiceLocator] ALL SERVICES REGISTERED SUCCESSFULLY');
  } catch (e, st) {
    debugPrint('❌ [setupServiceLocator] ERROR: $e');
    debugPrint('Stack trace: $st');
    rethrow;
  }
}

/// Get the path for storing the HNSW index cache.
///
/// On native platforms, this returns the ObjectBox database directory
/// so the index is stored alongside the database data.
/// On web, returns empty string (web store ignores path).
String _getIndexStorePath() {
  if (kIsWeb) {
    return ''; // Web store doesn't use file path
  }

  // On native platforms, use the default ObjectBox directory
  // The HNSW index file will be stored alongside the ObjectBox database
  // This avoids needing to access the Store instance before it's fully initialized
  return 'objectbox';
}

/// Extracts all spans until trained FilterRunner is deployed.
class _PassthroughFilterRunner implements FilterRunner {
  @override
  Future<FilterPrediction> predict(String spanText) async =>
      FilterPrediction(extractScore: 1.0, skipScore: 0.0);
}
