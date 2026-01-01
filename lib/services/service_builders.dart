/// # Service Builders
///
/// Single source of truth for creating any service with multiple implementations.
/// Used by bootstrap AND runtime switching - zero duplication.
///
/// One generic function handles all services.
///
/// Usage:
/// ```dart
/// // Bootstrap - create any service
/// final llm = createService<LLMService>('llm', llmConfig);
/// final tts = createService<TTSService>('tts', ttsConfig);
///
/// // Runtime switching - same function
/// await ServiceRegistry.switchProvider<LLMService>(
///   'llm',
///   newConfig,
///   (config) => createService<LLMService>('llm', config),
/// );
/// ```

import 'llm_service.dart';
import 'tts_service.dart';
import 'embedding_service.dart';
import 'groq_service.dart';
import 'flutter_tts_service.dart';
import 'service_registry.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/domain/invocation.dart';
import 'package:http/http.dart' as http;

// ============================================================================
// Generic Service Factory - Single Entry Point
// ============================================================================

/// Create any service based on service name and config.
///
/// Dispatches to the right builder based on service type.
/// Single source of truth - used for both bootstrap and runtime switching.
///
/// Example:
/// ```dart
/// final llm = createService<LLMService>('llm', config);
/// final tts = createService<TTSService>('tts', config);
/// ```
dynamic createService<T>(String serviceName, ServiceConfig config) {
  return switch (serviceName.toLowerCase()) {
    'llm' => createLLMService(config),
    'tts' => createTTSService(config),
    'embedding' => createEmbeddingService(config),
    _ => throw UnknownServiceException('Unknown service: $serviceName'),
  };
}

// ============================================================================
// LLM Service Builder
// ============================================================================

LLMService createLLMService(ServiceConfig config) {
  return switch (config.provider.toLowerCase()) {
    'groq' => _buildGroqLLM(config),
    'claude' => _buildClaudeLLM(config),
    'local' => _buildLocalLLM(config),
    _ => NullLLMService(),
  };
}

LLMService _buildGroqLLM(ServiceConfig config) {
  final apiKey = config.credentials['apiKey'] as String?;
  if (apiKey == null || apiKey.isEmpty) {
    print('⚠️ Groq API key missing');
    return NullLLMService();
  }

  final invocationRepo = ServiceRegistry.getOrNull<InvocationRepository<Invocation>>('invocation_repo');
  if (invocationRepo == null) {
    print('⚠️ Invocation repository not registered');
    return NullLLMService();
  }

  return GroqService(
    apiKey: apiKey,
    invocationRepository: invocationRepo,
  );
}

LLMService _buildClaudeLLM(ServiceConfig config) {
  // TODO: Implement Claude service
  print('⚠️ Claude LLM not yet implemented');
  return NullLLMService();
}

LLMService _buildLocalLLM(ServiceConfig config) {
  // TODO: Implement local LLM
  print('⚠️ Local LLM not yet implemented');
  return NullLLMService();
}

// ============================================================================
// TTS Service Builder
// ============================================================================

TTSService createTTSService(ServiceConfig config) {
  return switch (config.provider.toLowerCase()) {
    'flutter' => _buildFlutterTTS(config),
    'google' => _buildGoogleTTS(config),
    _ => NullTTSService(),
  };
}

TTSService _buildFlutterTTS(ServiceConfig config) {
  final invocationRepo = ServiceRegistry.getOrNull<InvocationRepository<Invocation>>('invocation_repo');
  if (invocationRepo == null) {
    print('⚠️ Invocation repository not registered');
    return NullTTSService();
  }

  return FlutterTtsService(
    invocationRepository: invocationRepo,
  );
}

TTSService _buildGoogleTTS(ServiceConfig config) {
  final apiKey = config.credentials['apiKey'] as String?;
  if (apiKey == null || apiKey.isEmpty) {
    print('⚠️ Google TTS API key missing, falling back to Flutter');
    return _buildFlutterTTS(config);
  }
  // TODO: Implement Google TTS
  print('⚠️ Google TTS not yet implemented');
  return _buildFlutterTTS(config);
}

// ============================================================================
// Embedding Service Builder
// ============================================================================

EmbeddingService createEmbeddingService(ServiceConfig config) {
  return switch (config.provider.toLowerCase()) {
    'jina' => _buildJinaEmbedding(config),
    'gemini' => _buildGeminiEmbedding(config),
    'local' => _buildLocalEmbedding(config),
    _ => NullEmbeddingService(),
  };
}

EmbeddingService _buildJinaEmbedding(ServiceConfig config) {
  final apiKey = config.credentials['apiKey'] as String?;
  if (apiKey == null || apiKey.isEmpty) {
    print('⚠️ Jina API key missing');
    return NullEmbeddingService();
  }

  return JinaEmbeddingService(
    apiKey: apiKey,
    httpClient: (url, headers, body) async {
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: body,
      );
      if (response.statusCode != 200) {
        throw Exception('Jina API error: ${response.statusCode} ${response.body}');
      }
      return response.body;
    },
  );
}

EmbeddingService _buildGeminiEmbedding(ServiceConfig config) {
  final apiKey = config.credentials['apiKey'] as String?;
  if (apiKey == null || apiKey.isEmpty) {
    print('⚠️ Gemini API key missing');
    return NullEmbeddingService();
  }
  // TODO: Implement Gemini embedding
  print('⚠️ Gemini embedding not yet implemented');
  return NullEmbeddingService();
}

EmbeddingService _buildLocalEmbedding(ServiceConfig config) {
  // TODO: Implement local embedding
  print('⚠️ Local embedding not yet implemented');
  return NullEmbeddingService();
}

// ============================================================================
// Exceptions
// ============================================================================

class UnknownServiceException implements Exception {
  final String message;

  UnknownServiceException(this.message);

  @override
  String toString() => 'UnknownServiceException: $message';
}
