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

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';

import 'services/blob_store.dart';
import 'services/file_service.dart';
import 'services/sync_service.dart';
import 'services/connectivity_service.dart';
import 'services/embedding_service.dart';
import 'services/jina_embedding_service_impl.dart';

// Conditional import for EmbeddingQueueService (native platforms only)
import 'services/embedding_queue_service.dart'
    if (dart.library.html) 'bootstrap/embedding_queue_service_web_stub.dart';
import 'services/stt_service.dart';
import 'services/tts_service.dart';
import 'services/llm_service.dart';
import 'services/groq_service.dart';
import 'services/flutter_tts_service.dart';
import 'services/coordinator.dart';
import 'services/tool_executor.dart';
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
import 'domain/llm_invocation_repository.dart';
import 'domain/tts_invocation_repository.dart';
import 'repositories/invocation_repository_impl.dart';
import 'repositories/adaptation_state_repository_impl.dart';
import 'repositories/feedback_repository_impl.dart';
import 'repositories/turn_repository_impl.dart';
import 'domain/adaptation_state_generic.dart';

// Conditional import for platform-specific BlobStore
import 'bootstrap/blob_store_factory_stub.dart'
    if (dart.library.io) 'bootstrap/blob_store_factory_io.dart'
    if (dart.library.html) 'bootstrap/blob_store_factory_web.dart';

// Conditional import for platform-specific Persistence
import 'bootstrap/persistence_factory_stub.dart'
    if (dart.library.io) 'bootstrap/persistence_factory_io.dart'
    if (dart.library.html) 'bootstrap/persistence_factory_web.dart';

import 'bootstrap/http_client.dart';
import 'bootstrap/timeout_http_client.dart';
import 'bootstrap/persistence_factory.dart';
import 'package:http/http.dart' as http;

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
    // Try .env file first (runtime), then fall back to compile-time
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

    // Fall back to compile-time environment
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
/// Global persistence factory instance.
/// Initialized by initializeEverythingStack() and used by repositories.
PersistenceFactory? _persistenceFactory;

/// Global embedding queue service instance.
/// Initialized by initializeEverythingStack() and used by NoteRepository.
EmbeddingQueueService? _embeddingQueueService;

/// Get the initialized persistence factory.
/// Throws if initializeEverythingStack() hasn't been called.
PersistenceFactory get persistenceFactory {
  if (_persistenceFactory == null) {
    throw StateError(
      'PersistenceFactory not initialized. Call initializeEverythingStack() first.',
    );
  }
  return _persistenceFactory!;
}

/// Get the initialized embedding queue service.
/// Returns null if not initialized (embeddings disabled).
EmbeddingQueueService? get embeddingQueueService => _embeddingQueueService;

Future<void> initializeEverythingStack({
  EverythingStackConfig? config,
}) async {
  // Load .env file (runtime environment variables)
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    // .env file is optional - may fail on web or when file not found
    // Fall back to compile-time environment variables
    // Silently ignore errors as we'll use compile-time env vars instead
  }

  final cfg = config ?? EverythingStackConfig.fromEnvironment();

  if (cfg.useMocks) {
    await _initializeMocks();
    return;
  }

  // 0. Create timeout-wrapped HTTP client (Layer 1 defense)
  final timeoutClient = TimeoutHttpClient(http.Client());
  final wrappedHttpClient = _wrapHttpClientWithTimeout(timeoutClient);

  // 1. Initialize Persistence (platform-specific: ObjectBox or IndexedDB)
  _persistenceFactory = await initializePersistence();

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

  // 6. Initialize EmbeddingService (optional - requires API key)
  if (cfg.jinaApiKey != null && cfg.jinaApiKey!.isNotEmpty) {
    EmbeddingService.instance = createJinaEmbeddingService(cfg.jinaApiKey!);
  } else if (cfg.geminiApiKey != null && cfg.geminiApiKey!.isNotEmpty) {
    EmbeddingService.instance = GeminiEmbeddingService(
      apiKey: cfg.geminiApiKey,
      httpClient: wrappedHttpClient,
    );
  }
  // else: keeps NullEmbeddingService default (embeddings disabled)

  // 7. EmbeddingQueueService deferred to Phase 1 (Note entity not yet implemented)

  // 8-11. STT/TTS/LLM Services (platform-specific)
  // Web platform: Uses browser APIs (SpeechSynthesis for TTS, Web Speech API for STT)
  // Native platforms: Uses external APIs (Google Cloud TTS, Deepgram STT)

  // Initialize TTS Service (cross-platform via flutter_tts)
  try {
    final invocationRepo = InvocationRepositoryImpl();
    TTSService.instance = FlutterTtsService(
      invocationRepository: invocationRepo,
    );
    await TTSService.instance.initialize();
  } catch (e) {
    print('Warning: TTS initialization failed: $e');
    // Falls back to NullTTSService
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
  print('Bootstrap complete: infrastructure services initialized');
}

/// Wrap TimeoutHttpClient to match HttpClientFunction signature.
///
/// This adapts the package:http Client to the HttpClientFunction type
/// expected by embedding services.
HttpClientFunction _wrapHttpClientWithTimeout(http.Client client) {
  return (String url, Map<String, String> headers, String body) async {
    final response = await client.post(
      Uri.parse(url),
      headers: headers,
      body: body,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body;
    }

    throw HttpClientException(
      'HTTP ${response.statusCode}: ${response.reasonPhrase}',
      statusCode: response.statusCode,
      body: response.body,
    );
  };
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
}

/// Dispose all services (call on app shutdown if needed).
Future<void> disposeEverythingStack() async {
  // Stop embedding queue first (flush pending tasks)
  if (_embeddingQueueService != null) {
    await _embeddingQueueService!.stop(flushPending: true);
  }

  // Dispose streaming services
  STTService.instance.dispose();
  TTSService.instance.dispose();
  LLMService.instance.dispose();

  // Dispose other services
  await _persistenceFactory?.close();
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
void setupServiceLocator() {
  // ========== External APIs (Abstraction-Respecting) ==========

  // EmbeddingService - loaded from config, respects abstraction
  getIt.registerSingleton<EmbeddingService>(
    EmbeddingService.instance,  // Already initialized by bootstrap
  );

  // LLMService - loaded from config, respects abstraction
  getIt.registerSingleton<LLMService>(
    LLMService.instance,  // Already initialized by bootstrap
  );

  // ========== Domain Repositories (Real, not in-memory for app) ==========

  getIt.registerSingleton<InvocationRepository<domain_invocation.Invocation>>(
    InvocationRepositoryImpl(),  // Real implementation (ObjectBox/IndexedDB, Phase 1)
  );

  getIt.registerSingleton<AdaptationStateRepository<AdaptationState>>(
    AdaptationStateRepositoryImpl(),  // Real implementation (ObjectBox/IndexedDB, Phase 1)
  );

  getIt.registerSingleton<FeedbackRepository>(
    FeedbackRepositoryImpl(),  // Real implementation (ObjectBox/IndexedDB, Phase 1)
  );

  getIt.registerSingleton<TurnRepository>(
    TurnRepositoryImpl.inMemory(),  // In-memory for now (Phase 1: ObjectBox/IndexedDB)
  );

  getIt.registerSingleton<LLMInvocationRepository>(
    LLMInvocationRepositoryImpl.inMemory(),  // In-memory for now
  );

  getIt.registerSingleton<TTSInvocationRepository>(
    TTSInvocationRepositoryImpl.inMemory(),  // In-memory for now
  );

  // ========== Trainable Selectors (Real implementations) ==========

  getIt.registerSingleton<NamespaceSelector>(
    NamespaceSelector(
      invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
      adaptationStateRepo: getIt<AdaptationStateRepository<AdaptationState>>(),
      feedbackRepo: getIt<FeedbackRepository>(),
    ),
  );

  getIt.registerSingleton<ToolSelector>(
    ToolSelector(
      invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
      adaptationStateRepo: getIt<AdaptationStateRepository<AdaptationState>>(),
      feedbackRepo: getIt<FeedbackRepository>(),
    ),
  );

  getIt.registerSingleton<ContextInjector>(
    ContextInjector(
      invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
      adaptationStateRepo: getIt<AdaptationStateRepository<AdaptationState>>(),
      feedbackRepo: getIt<FeedbackRepository>(),
    ),
  );

  getIt.registerSingleton<LLMConfigSelector>(
    LLMConfigSelector(
      invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
      adaptationStateRepo: getIt<AdaptationStateRepository<AdaptationState>>(),
      feedbackRepo: getIt<FeedbackRepository>(),
    ),
  );

  getIt.registerSingleton<LLMOrchestrator>(
    LLMOrchestrator(
      invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
      adaptationStateRepo: getIt<AdaptationStateRepository<AdaptationState>>(),
      feedbackRepo: getIt<FeedbackRepository>(),
    ),
  );

  getIt.registerSingleton<ResponseRenderer>(
    ResponseRenderer(
      invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
      adaptationStateRepo: getIt<AdaptationStateRepository<AdaptationState>>(),
      feedbackRepo: getIt<FeedbackRepository>(),
    ),
  );

  // ========== Tool Executor (Real agentic loop) ==========

  getIt.registerSingleton<ToolExecutor>(
    ToolExecutor(
      invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
    ),
  );

  // ========== Coordinator (Orchestrates all components) ==========

  getIt.registerSingleton<Coordinator>(
    Coordinator(
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
    ),
  );
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
    llmService ?? MockLLMService(),
  );

  // ========== Domain Repositories - Real (in-memory for speed) ==========

  getIt.registerSingleton<InvocationRepository<domain_invocation.Invocation>>(
    InvocationRepositoryImpl.inMemory(),  // In-memory for test speed
  );

  getIt.registerSingleton<AdaptationStateRepository<AdaptationState>>(
    AdaptationStateRepositoryImpl.inMemory(),  // In-memory for test speed
  );

  getIt.registerSingleton<FeedbackRepository>(
    FeedbackRepositoryImpl.inMemory(),  // In-memory for test speed
  );

  getIt.registerSingleton<TurnRepository>(
    TurnRepositoryImpl.inMemory(),  // In-memory for test speed
  );

  getIt.registerSingleton<LLMInvocationRepository>(
    LLMInvocationRepositoryImpl.inMemory(),  // In-memory for test speed
  );

  getIt.registerSingleton<TTSInvocationRepository>(
    TTSInvocationRepositoryImpl.inMemory(),  // In-memory for test speed
  );

  // ========== Trainable Selectors - Real implementations ==========

  getIt.registerSingleton<NamespaceSelector>(
    NamespaceSelector(
      invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
      adaptationStateRepo: getIt<AdaptationStateRepository<AdaptationState>>(),
      feedbackRepo: getIt<FeedbackRepository>(),
    ),
  );

  getIt.registerSingleton<ToolSelector>(
    ToolSelector(
      invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
      adaptationStateRepo: getIt<AdaptationStateRepository<AdaptationState>>(),
      feedbackRepo: getIt<FeedbackRepository>(),
    ),
  );

  getIt.registerSingleton<ContextInjector>(
    ContextInjector(
      invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
      adaptationStateRepo: getIt<AdaptationStateRepository<AdaptationState>>(),
      feedbackRepo: getIt<FeedbackRepository>(),
    ),
  );

  getIt.registerSingleton<LLMConfigSelector>(
    LLMConfigSelector(
      invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
      adaptationStateRepo: getIt<AdaptationStateRepository<AdaptationState>>(),
      feedbackRepo: getIt<FeedbackRepository>(),
    ),
  );

  getIt.registerSingleton<LLMOrchestrator>(
    LLMOrchestrator(
      invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
      adaptationStateRepo: getIt<AdaptationStateRepository<AdaptationState>>(),
      feedbackRepo: getIt<FeedbackRepository>(),
    ),
  );

  getIt.registerSingleton<ResponseRenderer>(
    ResponseRenderer(
      invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
      adaptationStateRepo: getIt<AdaptationStateRepository<AdaptationState>>(),
      feedbackRepo: getIt<FeedbackRepository>(),
    ),
  );

  // ========== Tool Executor - Real ==========

  getIt.registerSingleton<ToolExecutor>(
    ToolExecutor(
      invocationRepo: getIt<InvocationRepository<domain_invocation.Invocation>>(),
    ),
  );

  // ========== Coordinator - Real (real trainables, mocked externals) ==========

  getIt.registerSingleton<Coordinator>(
    Coordinator(
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
    ),
  );
}

// ============================================================================
// Mock Services for Testing
// ============================================================================

class MockEmbeddingService implements EmbeddingService {
  @override
  Future<List<double>> generate(String text) async {
    return List.filled(384, 0.5);  // Mock embedding
  }

  @override
  Future<List<List<double>>> generateBatch(List<String> texts) async {
    return texts.map((_) => List.filled(384, 0.5)).toList();  // Mock batch embeddings
  }
}

class MockLLMService implements LLMService {
  @override
  Future<void> initialize() async {}

  @override
  bool get isReady => true;

  @override
  void dispose() {}

  @override
  Stream<String> chat({
    required List<Message> history,
    required String userMessage,
    String? systemPrompt,
    int? maxTokens,
  }) async* {
    yield 'Mock response';
  }

  @override
  Future<LLMResponse> chatWithTools({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<LLMTool>? tools,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    return LLMResponse(
      id: 'mock_123',
      content: 'Task created successfully',
      toolCalls: [],
      tokensUsed: 100,
    );
  }

  @override
  Future<String> recordInvocation(dynamic invocation) async {
    return 'mock_invocation';
  }

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {}

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async {
    return {'status': 'baseline'};
  }

  @override
  Widget buildFeedbackUI(String invocationId) {
    throw UnimplementedError();
  }
}
