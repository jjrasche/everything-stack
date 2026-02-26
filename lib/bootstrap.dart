library;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';

import 'bootstrap/bootstrap_module.dart';
import 'bootstrap/persistence_module.dart';
import 'bootstrap/ai_services_module.dart';
import 'bootstrap/embedding_module.dart';
import 'bootstrap/audio_module.dart';
import 'bootstrap/application_module.dart';
import 'services/semantic_search/bootstrap_module.dart';
import 'services/extraction/bootstrap_module.dart';
import 'services/memory/bootstrap_module.dart';
import 'services/debug/debug_bootstrap.dart';
import 'services/embedding_queue_service.dart';

final getIt = GetIt.instance;

final List<BootstrapModule> _modules = [
  PersistenceModule(),
  AiServicesModule(),
  EmbeddingModule(),
  SemanticSearchModule(),
  AudioModule(),
  ExtractionModule(),
  MemoryModule(),
  ApplicationModule(),
];

EmbeddingQueueService? _embeddingQueueService;
EmbeddingQueueService? get embeddingQueueService => _embeddingQueueService;

Future<void> initializeEverythingStack({
  EverythingStackConfig? config,
}) async {
  await _loadEnvironment();
  final cfg = config ?? EverythingStackConfig.fromEnvironment();

  for (final module in _modules) {
    final moduleName = module.runtimeType.toString();
    try {
      await module.register(getIt, cfg);
      debugPrint('✅ $moduleName');
    } catch (e, st) {
      debugPrint('❌ $moduleName: $e\n$st');
      rethrow;
    }
  }

  await initializeDebugInfrastructure();
}

Future<void> disposeEverythingStack() async {
  if (_embeddingQueueService != null) {
    await _embeddingQueueService!.stop(flushPending: true);
  }

  for (final module in _modules.reversed) {
    await module.dispose(getIt);
  }
}

Future<void> _loadEnvironment() async {
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    debugPrint('ℹ️ .env not found, using compile-time env vars');
  }
}

class EverythingStackConfig {
  final String? supabaseUrl;
  final String? supabaseAnonKey;
  final String? jinaApiKey;
  final String? geminiApiKey;
  final String? deepgramApiKey;
  final String? googleTtsApiKey;
  final String? claudeApiKey;
  final String? groqApiKey;
  final String? llmProvider;
  final String? ttsProvider;
  final String? sttProvider;
  final String? embeddingProvider;
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

  static const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _jinaApiKey = String.fromEnvironment('JINA_API_KEY');
  static const _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _deepgramApiKey = String.fromEnvironment('DEEPGRAM_API_KEY');
  static const _googleTtsApiKey = String.fromEnvironment('GOOGLE_TTS_API_KEY');
  static const _claudeApiKey = String.fromEnvironment('CLAUDE_API_KEY');
  static const _groqApiKey = String.fromEnvironment('GROQ_API_KEY');

  static String? _envOrNull(String key) {
    String? runtimeValue;
    try {
      runtimeValue = dotenv.maybeGet(key);
    } catch (_) {
      runtimeValue = null;
    }
    if (runtimeValue != null && runtimeValue.isNotEmpty) {
      return runtimeValue;
    }

    return switch (key) {
      'SUPABASE_URL' => _supabaseUrl.isEmpty ? null : _supabaseUrl,
      'SUPABASE_ANON_KEY' => _supabaseAnonKey.isEmpty ? null : _supabaseAnonKey,
      'JINA_API_KEY' => _jinaApiKey.isEmpty ? null : _jinaApiKey,
      'GEMINI_API_KEY' => _geminiApiKey.isEmpty ? null : _geminiApiKey,
      'DEEPGRAM_API_KEY' => _deepgramApiKey.isEmpty ? null : _deepgramApiKey,
      'GOOGLE_TTS_API_KEY' =>
        _googleTtsApiKey.isEmpty ? null : _googleTtsApiKey,
      'CLAUDE_API_KEY' => _claudeApiKey.isEmpty ? null : _claudeApiKey,
      'GROQ_API_KEY' => _groqApiKey.isEmpty ? null : _groqApiKey,
      _ => null,
    };
  }

  bool get hasSyncConfig =>
      supabaseUrl != null &&
      supabaseUrl!.isNotEmpty &&
      supabaseAnonKey != null &&
      supabaseAnonKey!.isNotEmpty;

  bool get hasEmbeddingConfig =>
      (jinaApiKey != null && jinaApiKey!.isNotEmpty) ||
      (geminiApiKey != null && geminiApiKey!.isNotEmpty);
}

/// Backward compatibility — callers that still call both functions.
Future<void> setupServiceLocator() async {}
