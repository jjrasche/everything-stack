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
/// final llm = createService<InferenceService>('llm', llmConfig);
/// final tts = createService<TTSService>('tts', ttsConfig);
///
/// // Runtime switching - same function
/// await ServiceRegistry.switchProvider<InferenceService>(
///   'llm',
///   newConfig,
///   (config) => createService<InferenceService>('llm', config),
/// );
/// ```

import 'inference_service.dart';
import 'tts_service.dart';
import 'embedding_service.dart';
import 'service_registry.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/core/adaptation_state_repository.dart';
import 'package:everything_stack_template/core/feedback_repository.dart';
import 'implementations/groq_implementer.dart';
import 'implementations/flutter_tts_implementer.dart';
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
/// final llm = createService<InferenceService>('llm', config);
/// final tts = createService<TTSService>('tts', config);
/// ```
dynamic createService<T>(String serviceName, ServiceConfig config) {
  return switch (serviceName.toLowerCase()) {
    'llm' => createInferenceService(config),
    'tts' => createTTSService(config),
    'embedding' => createEmbeddingService(config),
    _ => throw UnknownServiceException('Unknown service: $serviceName'),
  };
}

// ============================================================================
// LLM Service Builder
// ============================================================================

InferenceService createInferenceService(ServiceConfig config) {
  return switch (config.provider.toLowerCase()) {
    'groq' => _buildGroqLLM(config),
    'claude' => _buildClaudeLLM(config),
    'local' => _buildLocalLLM(config),
    _ =>
      throw UnknownServiceException('Unknown LLM provider: ${config.provider}'),
  };
}

InferenceService _buildGroqLLM(ServiceConfig config) {
  // TODO: InferenceService requires concrete implementation
  // InferenceService is abstract and cannot be instantiated
  print(
      '⚠️ Groq LLM service builder - awaiting concrete InferenceService implementation');
  throw UnimplementedError('Groq LLM service builder not yet implemented');
}

InferenceService _buildClaudeLLM(ServiceConfig config) {
  // TODO: Implement Claude service
  print('⚠️ Claude LLM not yet implemented');
  throw UnimplementedError('Claude LLM not yet implemented');
}

InferenceService _buildLocalLLM(ServiceConfig config) {
  // TODO: Implement local LLM
  print('⚠️ Local LLM not yet implemented');
  throw UnimplementedError('Local LLM not yet implemented');
}

// ============================================================================
// TTS Service Builder
// ============================================================================

TTSService createTTSService(ServiceConfig config) {
  return switch (config.provider.toLowerCase()) {
    'flutter' => _buildFlutterTTS(config),
    'google' => _buildGoogleTTS(config),
    _ =>
      throw UnknownServiceException('Unknown TTS provider: ${config.provider}'),
  };
}

TTSService _buildFlutterTTS(ServiceConfig config) {
  // TODO: TTSService requires concrete implementation
  // TTSService is abstract and cannot be instantiated
  print(
      '⚠️ Flutter TTS service builder - awaiting concrete TTSService implementation');
  throw UnimplementedError('Flutter TTS service builder not yet implemented');
}

TTSService _buildGoogleTTS(ServiceConfig config) {
  final apiKey = config.credentials['apiKey'] as String?;
  if (apiKey == null || apiKey.isEmpty) {
    print('⚠️ Google TTS API key missing - falling back to Flutter');
    return _buildFlutterTTS(config);
  }
  // TODO: Implement Google TTS
  print('⚠️ Google TTS not yet implemented - falling back to Flutter');
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
    _ => throw UnknownServiceException(
        'Unknown embedding provider: ${config.provider}'),
  };
}

EmbeddingService _buildJinaEmbedding(ServiceConfig config) {
  final apiKey = config.credentials['apiKey'] as String?;
  if (apiKey == null || apiKey.isEmpty) {
    print('⚠️ Jina API key missing - embedding service unavailable');
    throw Exception('Jina API key required for embedding service');
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
        throw Exception(
            'Jina API error: ${response.statusCode} ${response.body}');
      }
      return response.body;
    },
  );
}

EmbeddingService _buildGeminiEmbedding(ServiceConfig config) {
  final apiKey = config.credentials['apiKey'] as String?;
  if (apiKey == null || apiKey.isEmpty) {
    print('⚠️ Gemini API key missing');
  }
  // TODO: Implement Gemini embedding
  print('⚠️ Gemini embedding not yet implemented');
  throw UnimplementedError('Gemini embedding not yet implemented');
}

EmbeddingService _buildLocalEmbedding(ServiceConfig config) {
  // TODO: Implement local embedding
  print('⚠️ Local embedding not yet implemented');
  throw UnimplementedError('Local embedding not yet implemented');
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
