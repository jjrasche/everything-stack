import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;
import 'timeout_config.dart';
import 'trainable.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/domain/invocation.dart';

/// Text-to-speech service contract.
///
/// Converts text to streaming audio (Uint8List bytes).
///
/// ## Platform Support
/// - Native (Android/iOS/Desktop): GoogleTTSService (HTTP streaming)
/// - Web: GoogleTTSService (HTTP streaming via dart:html)
/// - Fallback: NullTTSService (no-op when not configured)
///
/// ## Usage
/// ```dart
/// // Initialize
/// await TTSService.instance.initialize();
///
/// // Synthesize text → receive audio chunks
/// await for (final audioChunk in TTSService.instance.synthesize('Hello world')) {
///   audioPlayer.add(audioChunk);
/// }
///
/// // Cleanup
/// TTSService.instance.dispose();
/// ```
///
/// ## Timeout Behavior
/// - **Connection timeout**: 10s to establish HTTP connection
/// - **Streaming idle timeout**: 5s without audio chunk → assume connection stalled
/// - **No automatic retry**: Caller must retry on timeout
abstract class TTSService implements Trainable {
  /// Global instance (default: NullTTSService)
  ///
  /// Replace with GoogleTTSService in bootstrap:
  /// ```dart
  /// TTSService.instance = GoogleTTSService(apiKey: '...');
  /// await TTSService.instance.initialize();
  /// ```
  static TTSService instance = NullTTSService();

  /// Initialize platform resources and authenticate.
  ///
  /// Call this before using [synthesize].
  /// May throw if initialization fails.
  Future<void> initialize();

  /// Synthesize text into streaming audio.
  ///
  /// Returns a stream of audio bytes (PCM, MP3, or Opus depending on service).
  ///
  /// ## Parameters
  /// - [text]: Text to synthesize
  /// - [voice]: Optional voice ID (default: service-specific)
  /// - [languageCode]: Optional language code (default: 'en-US')
  ///
  /// ## Timeout Behavior
  /// - Connection timeout (10s): Throws TTSException if can't connect
  /// - Streaming idle timeout (5s): Throws TTSException if no chunk received
  ///
  /// ## Example
  /// ```dart
  /// try {
  ///   await for (final chunk in tts.synthesize('Hello world')) {
  ///     audioPlayer.add(chunk);
  ///   }
  /// } on TTSException catch (e) {
  ///   print('TTS failed: $e');
  ///   // Retry or show error
  /// }
  /// ```
  Stream<Uint8List> synthesize(
    String text, {
    String? voice,
    String? languageCode,
  });

  /// Synthesize text and automatically record invocation (trainable pattern)
  ///
  /// This is the method used by Coordinator. It:
  /// 1. Synthesizes the text to speech
  /// 2. Consumes audio chunks (sends to player)
  /// 3. Records invocation with correlationId for training
  /// 4. Handles errors gracefully (doesn't crash orchestration)
  ///
  /// ## Parameters
  /// - [text]: Text to synthesize
  /// - [correlationId]: Conversation turn ID for linking to orchestration
  ///
  /// ## Returns
  /// Completes when synthesis is done and invocation is recorded.
  Future<void> synthesizeAndLog({
    required String text,
    required String correlationId,
  });

  /// Cleanup resources.
  ///
  /// Always call this when done with the service.
  /// Safe to call multiple times.
  void dispose();

  /// Check if service is ready to use.
  ///
  /// Returns true after successful [initialize], false after [dispose].
  bool get isReady;

  /// Record TTS invocation for training/adaptation
  ///
  /// Called after synthesis completes.
  /// Saves to repository for later feedback and learning.
  @override
  Future<String> recordInvocation(dynamic invocation);

  /// Learn from user feedback (TTS-specific)
  @override
  Future<void> trainFromFeedback(String turnId, {String? userId});

  /// Get current TTS adaptation state
  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId});

  /// Build UI for TTS feedback
  @override
  Widget buildFeedbackUI(String invocationId);
}

// ============================================================================
// Google Cloud TTS Service (Production Implementation Stub)
// ============================================================================

/// Google Cloud text-to-speech service.
///
/// **STUB IMPLEMENTATION** - Interface complete, implementation needed.
///
/// ## Implementation Checklist
/// - [ ] HTTP streaming to Google Cloud TTS API
/// - [ ] Authentication (API key or service account)
/// - [ ] Voice selection (Neural2, Studio, Standard)
/// - [ ] Audio format (LINEAR16, MP3, OGG_OPUS)
/// - [ ] Connection timeout (10s)
/// - [ ] Streaming idle timeout (5s no chunk)
/// - [ ] Error handling (network, auth, rate limit)
///
/// ## Configuration
/// ```dart
/// final tts = GoogleTTSService(
///   apiKey: 'YOUR_API_KEY',
///   defaultVoice: 'en-US-Neural2-A', // Optional
///   audioEncoding: AudioEncoding.linear16, // Optional
/// );
/// ```
class GoogleTTSService extends TTSService {
  final String apiKey;
  final String defaultVoice;
  final String audioEncoding;
  final InvocationRepository<Invocation> _invocationRepository;

  bool _isReady = false;
  final http.Client _httpClient = http.Client();

  GoogleTTSService({
    required this.apiKey,
    required InvocationRepository<Invocation> invocationRepository,
    this.defaultVoice = 'en-US-Neural2-A',
    this.audioEncoding = 'LINEAR16',
  }) : _invocationRepository = invocationRepository;

  @override
  Future<void> initialize() async {
    // Validate API key
    if (apiKey.isEmpty) {
      throw TTSException('Google Cloud TTS API key is empty');
    }
    _isReady = true;
    print('GoogleTTSService initialized (API key validated)');
  }

  @override
  Stream<Uint8List> synthesize(
    String text, {
    String? voice,
    String? languageCode,
  }) async* {
    if (!_isReady) {
      throw TTSException('GoogleTTSService not initialized');
    }

    if (text.isEmpty) {
      throw TTSException('Synthesis text cannot be empty');
    }

    final voiceId = voice ?? defaultVoice;
    final lang = languageCode ?? 'en-US';

    try {
      // Prepare request
      final url = Uri.parse(
        'https://texttospeech.googleapis.com/v1/text:synthesize?key=$apiKey',
      );

      final requestBody = {
        'input': {'text': text},
        'voice': {
          'languageCode': lang,
          'name': voiceId,
        },
        'audioConfig': {
          'audioEncoding': audioEncoding,
          'sampleRateHertz': audioEncoding == 'LINEAR16' ? 16000 : null,
        },
      };

      // Make HTTP request with timeout
      final response = await _httpClient
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(TimeoutConfig.ttsGeneration);

      // Check for errors
      if (response.statusCode != 200) {
        throw TTSException(
          'Google TTS API error: ${response.statusCode}',
          cause: response.body,
        );
      }

      // Parse response
      final responseJson = jsonDecode(response.body);
      final audioContent = responseJson['audioContent'] as String?;

      if (audioContent == null) {
        throw TTSException('No audio content in response');
      }

      // Decode base64 audio
      final audioBytes = base64Decode(audioContent);

      // Yield the audio bytes as a single chunk
      // (For streaming, could split into smaller chunks if needed)
      yield audioBytes;
    } on TTSException {
      rethrow;
    } catch (e) {
      throw TTSException('Google TTS synthesis failed', cause: e);
    }
  }

  @override
  void dispose() {
    _httpClient.close();
    _isReady = false;
    print('GoogleTTSService disposed');
  }

  @override
  bool get isReady => _isReady;

  @override
  Future<void> synthesizeAndLog({
    required String text,
    required String correlationId,
  }) async {
    // TODO: Implement synthesizeAndLog for GoogleTTSService
    // For MVP: delegate to synthesize() and consume audio stream
    // Then record invocation with correlationId
    print('GoogleTTSService.synthesizeAndLog() - TODO');
  }

  // ============================================================================
  // Trainable Implementation
  // ============================================================================

  @override
  Future<String> recordInvocation(dynamic invocation) async {
    if (invocation is! Invocation) {
      throw ArgumentError('Expected Invocation, got ${invocation.runtimeType}');
    }
    await _invocationRepository.save(invocation);
    return invocation.uuid;
  }

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {
    // TODO: Implement TTS learning from feedback
    // For MVP: placeholder - full implementation in Phase 3
    print('GoogleTTSService.trainFromFeedback() - TODO');
  }

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async {
    // TODO: Implement returning current TTS adaptation state
    // For MVP: placeholder - full implementation in Phase 3
    return {'status': 'baseline'};
  }

  @override
  Widget buildFeedbackUI(String invocationId) {
    // TODO: Implement TTS feedback UI
    // For MVP: placeholder - full implementation in Phase 3
    return Center(child: Text('TTS Feedback UI (TODO)'));
  }
}

// ============================================================================
// Null TTS Service (Safe Fallback)
// ============================================================================

/// Null Object implementation for TTS service.
///
/// Used when TTS is not configured.
/// Fails gracefully without crashing the app.
class NullTTSService extends TTSService {
  @override
  Future<void> initialize() async {
    print('Warning: TTSService not configured (using NullTTSService)');
  }

  @override
  Stream<Uint8List> synthesize(
    String text, {
    String? voice,
    String? languageCode,
  }) async* {
    print('Warning: TTS unavailable - using NullTTSService');
    throw TTSException('TTS not configured');
  }

  @override
  Future<void> synthesizeAndLog({
    required String text,
    required String correlationId,
  }) async {
    print(
        '⚠️  [NullTTSService] TTS not configured - skipping synthesis for: "$text"');
    // No-op: TTS not configured, so we don't do anything
    // This allows orchestration to continue without crashing
  }

  @override
  void dispose() {}

  @override
  bool get isReady => false;

  @override
  Future<String> recordInvocation(dynamic invocation) async {
    throw TTSException('TTS not configured');
  }

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {
    throw TTSException('TTS not configured');
  }

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async {
    throw TTSException('TTS not configured');
  }

  @override
  Widget buildFeedbackUI(String invocationId) {
    return Center(child: Text('TTS not configured'));
  }
}

// ============================================================================
// Exceptions
// ============================================================================

/// Exception thrown by TTS service.
class TTSException implements Exception {
  final String message;
  final Object? cause;

  TTSException(this.message, {this.cause});

  @override
  String toString() {
    if (cause != null) {
      return 'TTSException: $message (cause: $cause)';
    }
    return 'TTSException: $message';
  }
}
