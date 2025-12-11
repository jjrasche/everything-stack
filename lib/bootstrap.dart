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
/// 1. BlobStore (platform-specific: FileSystem or IndexedDB)
/// 2. FileService (depends on BlobStore)
/// 3. ConnectivityService
/// 4. SyncService (optional, requires Supabase credentials)
/// 5. EmbeddingService (optional, requires API key)

library;

import 'services/blob_store.dart';
import 'services/file_service.dart';
import 'services/sync_service.dart';
import 'services/connectivity_service.dart';
import 'services/embedding_service.dart';

// Conditional import for platform-specific BlobStore
import 'bootstrap/blob_store_factory_stub.dart'
    if (dart.library.io) 'bootstrap/blob_store_factory_io.dart'
    if (dart.library.html) 'bootstrap/blob_store_factory_web.dart';

import 'bootstrap/http_client.dart';

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

  /// Whether to use mock services (for testing)
  final bool useMocks;

  const EverythingStackConfig({
    this.supabaseUrl,
    this.supabaseAnonKey,
    this.jinaApiKey,
    this.geminiApiKey,
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
    );
  }

  // Compile-time environment variable helpers.
  // String.fromEnvironment must be const, so we need separate declarations.
  static const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _jinaApiKey = String.fromEnvironment('JINA_API_KEY');
  static const _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  static String? _envOrNull(String key) {
    switch (key) {
      case 'SUPABASE_URL':
        return _supabaseUrl.isEmpty ? null : _supabaseUrl;
      case 'SUPABASE_ANON_KEY':
        return _supabaseAnonKey.isEmpty ? null : _supabaseAnonKey;
      case 'JINA_API_KEY':
        return _jinaApiKey.isEmpty ? null : _jinaApiKey;
      case 'GEMINI_API_KEY':
        return _geminiApiKey.isEmpty ? null : _geminiApiKey;
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
Future<void> initializeEverythingStack({
  EverythingStackConfig? config,
}) async {
  final cfg = config ?? EverythingStackConfig.fromEnvironment();

  if (cfg.useMocks) {
    await _initializeMocks();
    return;
  }

  // 1. Initialize BlobStore (platform-specific)
  final blobStore = createPlatformBlobStore();
  await blobStore.initialize();
  BlobStore.instance = blobStore;

  // 2. Initialize FileService (depends on BlobStore)
  final fileService = RealFileService(blobStore: blobStore);
  await fileService.initialize();
  FileService.instance = fileService;

  // 3. Initialize ConnectivityService
  final connectivityService = ConnectivityPlusService();
  await connectivityService.initialize();
  ConnectivityService.instance = connectivityService;

  // 4. Initialize SyncService (optional - requires Supabase config)
  if (cfg.hasSyncConfig) {
    final syncService = SupabaseSyncService(
      supabaseUrl: cfg.supabaseUrl!,
      supabaseAnonKey: cfg.supabaseAnonKey!,
    );
    await syncService.initialize();
    SyncService.instance = syncService;
  }
  // else: keeps MockSyncService default

  // 5. Initialize EmbeddingService (optional - requires API key)
  if (cfg.jinaApiKey != null && cfg.jinaApiKey!.isNotEmpty) {
    EmbeddingService.instance = JinaEmbeddingService(
      apiKey: cfg.jinaApiKey,
      httpClient: defaultHttpClient,
    );
  } else if (cfg.geminiApiKey != null && cfg.geminiApiKey!.isNotEmpty) {
    EmbeddingService.instance = GeminiEmbeddingService(
      apiKey: cfg.geminiApiKey,
      httpClient: defaultHttpClient,
    );
  }
  // else: keeps MockEmbeddingService default
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
  FileService.instance.dispose();
  BlobStore.instance.dispose();
  ConnectivityService.instance.dispose();
  SyncService.instance.dispose();
}
