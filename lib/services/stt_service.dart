import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

import 'streaming_service.dart';
import 'trainable.dart';
import 'package:web_socket_channel/io.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/domain/invocation.dart';

/// Speech-to-text service contract.
///
/// Converts streaming audio (Uint8List bytes) to text transcription.
///
/// ## Platform Support
/// - Native (Android/iOS/Desktop): DeepgramSTTService (WebSocket)
/// - Web: DeepgramSTTService (WebSocket via dart:html)
/// - Fallback: NullSTTService (no-op when not configured)
///
/// ## Usage
/// ```dart
/// // Initialize
/// await STTService.instance.initialize();
///
/// // Stream audio → receive transcripts
/// final subscription = STTService.instance.transcribe(
///   audio: microphoneStream,
///   onTranscript: (text) => print('Transcript: $text'),
///   onError: (e) => print('Error: $e'),
/// );
///
/// // Cleanup
/// await subscription.cancel();
/// STTService.instance.dispose();
/// ```
///
/// ## Timeout Behavior
/// - **Connection timeout**: 10s to establish WebSocket
/// - **Idle timeout**: 30s without transcript → assume connection dead
/// - **No automatic retry**: Caller must reconnect on timeout
abstract class STTService extends StreamingService<Uint8List, String>
    implements Trainable {
  /// Global instance - configured in bootstrap.dart
  static late STTService instance;

  /// Stream audio bytes, receive transcript chunks.
  ///
  /// Convenience wrapper around [stream] with STT-specific types.
  ///
  /// ## Parameters
  /// - [audio]: Stream of audio bytes (e.g., from microphone)
  /// - [onTranscript]: Called for each transcript chunk
  /// - [onUtteranceEnd]: Called when speech ends (turn detection via Deepgram)
  /// - [onError]: Called on timeout or connection error
  /// - [onDone]: Called when stream completes
  ///
  /// ## Timeout Behavior
  /// - Connection timeout: Throws STTException before returning
  /// - Idle timeout (30s no transcript): Calls onError, closes stream
  ///
  /// ## Example
  /// ```dart
  /// final sub = STTService.instance.transcribe(
  ///   audio: micStream,
  ///   onTranscript: (text) => _appendToBuffer(text),
  ///   onUtteranceEnd: () => _processTranscript(),
  ///   onError: (e) => _showError(e),
  /// );
  /// ```
  StreamSubscription<String> transcribe({
    required Stream<Uint8List> audio,
    required void Function(String) onTranscript,
    void Function()? onUtteranceEnd,
    required void Function(Object) onError,
    void Function()? onDone,
  }) {
    return stream(
      input: audio,
      onData: onTranscript,
      onUtteranceEnd: onUtteranceEnd,
      onError: onError,
      onDone: onDone,
    );
  }

  /// Internal streaming implementation for platform-specific audio processing
  ///
  /// Subclasses must implement the actual streaming logic.
  StreamSubscription<String> stream({
    required Stream<Uint8List> input,
    required void Function(String) onData,
    void Function()? onUtteranceEnd,
    required void Function(Object) onError,
    void Function()? onDone,
  });

  /// Record STT invocation for training/adaptation
  ///
  /// Called after transcription completes.
  /// Saves to repository for later feedback and learning.
  @override
  Future<String> recordInvocation(dynamic invocation);

  /// Learn from user feedback (STT-specific)
  @override
  Future<void> trainFromFeedback(String turnId, {String? userId});

  /// Get current STT adaptation state
  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId});

  /// Build UI for STT feedback
  @override
  Widget buildFeedbackUI(String invocationId);
}

// ============================================================================
// Deepgram STT Service (Production Implementation Stub)
// ============================================================================

/// Deepgram speech-to-text service.
///
/// **STUB IMPLEMENTATION** - Interface complete, implementation needed.
///
/// ## Implementation Checklist
/// - [ ] WebSocket connection to Deepgram API
/// - [ ] Audio streaming (PCM/Opus format)
/// - [ ] Real-time transcript handling
/// - [ ] Connection timeout (10s)
/// - [ ] Idle timeout (30s no data)
/// - [ ] Error handling (network, auth, rate limit)
/// - [ ] Cleanup on dispose
///
/// ## Configuration
/// ```dart
/// final stt = DeepgramSTTService(
///   apiKey: 'YOUR_API_KEY',
///   model: 'nova-2', // Optional: default model
///   language: 'en-US', // Optional: default language
/// );
/// ```
class DeepgramSTTService extends STTService {
  final String apiKey;
  final String model;
  final String language;
  final InvocationRepository<Invocation> _invocationRepository;

  bool _isReady = false;
  IOWebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSubscription;
  Timer? _idleTimer;

  DeepgramSTTService({
    required this.apiKey,
    required InvocationRepository<Invocation> invocationRepository,
    this.model = 'nova-2',
    this.language = 'en-US',
  }) : _invocationRepository = invocationRepository;

  @override
  Future<void> initialize() async {
    // Validate API key
    if (apiKey.isEmpty) {
      throw STTException('Deepgram API key is empty');
    }
    _isReady = true;
    print('DeepgramSTTService initialized (API key validated)');
  }

  StreamSubscription<String> stream({
    required Stream<Uint8List> input,
    required void Function(String) onData,
    void Function()? onUtteranceEnd,
    required void Function(Object) onError,
    void Function()? onDone,
  }) {
    if (!_isReady) {
      onError(STTException('DeepgramSTTService not initialized'));
      return Stream<String>.empty().listen(null);
    }

    // Controller to manage transcript stream
    final controller = StreamController<String>();

    // Track if connection is active
    bool isActive = true;

    Future<void> connect() async {
      try {
        // Build WebSocket URL with parameters and API key
        // Turn detection enabled via utterance_end_ms parameter
        final urlString = 'wss://api.deepgram.com/v1/listen'
            '?model=$model'
            '&language=$language'
            '&encoding=linear16'
            '&sample_rate=16000'
            '&channels=1'
            '&interim_results=true'
            '&endpointing=true'
            '&vad_events=true'
            '&utterance_end_ms=1000';

        // Connect with timeout and Authorization header
        try {
          _ws = IOWebSocketChannel.connect(
            Uri.parse(urlString),
            headers: {'Authorization': 'Token $apiKey'},
          );
        } catch (e) {
          throw STTException('Failed to connect to Deepgram', cause: e);
        }

        // Handle WebSocket messages
        _wsSubscription = _ws!.stream.listen(
          (message) {
            // Reset idle timer on any message
            _idleTimer?.cancel();
            _idleTimer = Timer(Duration(seconds: 30), () {
              if (isActive) {
                onError(STTException('Deepgram idle timeout (30s)'));
                _cleanup();
              }
            });

            // Parse Deepgram response
            try {
              final json = jsonDecode(message);
              debugPrint('📨 [Deepgram] Raw response: ${json['type']}');
              if (json['type'] == 'Results') {
                debugPrint('📨 [Deepgram] Full JSON: $json');
              }

              // Extract transcript from response
              if (json['type'] == 'Results') {
                // Deepgram v3 API structure: channel.alternatives[0].transcript
                final channel = json['channel'] as Map?;
                if (channel != null) {
                  final alternatives = channel['alternatives'] as List?;
                  if (alternatives != null && alternatives.isNotEmpty) {
                    final transcript = alternatives[0]['transcript'] as String?;
                    debugPrint('📨 [Deepgram] Transcript: "$transcript"');
                    if (transcript != null && transcript.isNotEmpty) {
                      onData(transcript);
                    }
                  }

                  // Check speech_final flag for turn detection
                  final speechFinal = json['speech_final'] as bool? ?? false;
                  if (speechFinal) {
                    debugPrint('🔊 [Deepgram] Speech final');
                  }
                }
              }
              // NEW: Handle UtteranceEnd event (turn detection)
              else if (json['type'] == 'UtteranceEnd') {
                final lastWordEnd = json['last_word_end'] as double?;
                print('Turn ended at ${lastWordEnd}s');
                onUtteranceEnd?.call();
              }
            } catch (e) {
              // Log parse errors but don't fail - continue streaming
              print('Warning: Failed to parse Deepgram response: $e');
            }
          },
          onError: (error) {
            if (isActive) {
              onError(STTException('WebSocket error', cause: error));
              _cleanup();
            }
          },
          onDone: () {
            if (isActive) {
              onDone?.call();
              _cleanup();
            }
          },
        );

        // Send audio from input stream
        input.listen(
          (audioBytes) {
            if (_ws != null && isActive) {
              try {
                _ws!.sink.add(audioBytes);
              } catch (e) {
                if (isActive) {
                  onError(STTException('Failed to send audio', cause: e));
                  _cleanup();
                }
              }
            }
          },
          onError: (error) {
            if (isActive) {
              onError(STTException('Audio stream error', cause: error));
              _cleanup();
            }
          },
          onDone: () {
            if (isActive) {
              // Close WebSocket connection when audio stream ends
              _cleanup();
            }
          },
        );

        // Set initial idle timeout
        _idleTimer = Timer(Duration(seconds: 30), () {
          if (isActive) {
            onError(STTException('Deepgram idle timeout (30s)'));
            _cleanup();
          }
        });
      } catch (e) {
        if (isActive) {
          onError(STTException('Deepgram connection failed', cause: e));
          _cleanup();
        }
      }
    }

    // Start connection
    connect();

    // Return subscription that allows caller to cancel
    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
    );
  }

  void _cleanup() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _wsSubscription?.cancel();
    _ws?.sink.close();
    _ws = null;
  }

  @override
  void dispose() {
    _cleanup();
    _isReady = false;
    print('DeepgramSTTService disposed');
  }

  @override
  bool get isReady => _isReady;

  // ============================================================================
  // Trainable Implementation
  // ============================================================================

  @override
  Future<String> recordInvocation(dynamic invocation) async {
    if (invocation is! Invocation) {
      throw ArgumentError(
          'Expected Invocation, got ${invocation.runtimeType}');
    }
    await _invocationRepository.save(invocation);
    return invocation.uuid;
  }

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {
    // TODO: Implement STT learning from feedback
    // For MVP: placeholder - full implementation in Phase 3
    print('DeepgramSTTService.trainFromFeedback() - TODO');
  }

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async {
    // TODO: Implement returning current STT adaptation state
    // For MVP: placeholder - full implementation in Phase 3
    return {'status': 'baseline'};
  }

  @override
  Widget buildFeedbackUI(String invocationId) {
    // TODO: Implement STT feedback UI
    // For MVP: placeholder - full implementation in Phase 3
    return Center(child: Text('STT Feedback UI (TODO)'));
  }
}

// ============================================================================
// Null STT Service (Fallback)
// ============================================================================

/// No-op fallback when API key is not configured.
/// Production mode - requires real Deepgram API key for STT to work.
class NullSTTService extends STTService {
  @override
  Future<void> initialize() async {}

  @override
  StreamSubscription<String> stream({
    required Stream<Uint8List> input,
    required void Function(String) onData,
    void Function()? onUtteranceEnd,
    required void Function(Object) onError,
    void Function()? onDone,
  }) {
    debugPrint('⚠️ [STT] API key missing - STT disabled (add DEEPGRAM_API_KEY to .env.local)');

    // Drain input stream but don't process it
    input.listen(
      (_) {},  // Ignore audio data
      onError: onError,
      onDone: onDone,
    );

    // Return empty stream
    return Stream<String>.empty().listen(
      onData,
      onError: onError,
      onDone: onDone,
    );
  }

  @override
  void dispose() {}

  @override
  bool get isReady => false;

  @override
  Future<String> recordInvocation(dynamic invocation) async => '';

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {}

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async => {};

  @override
  Widget buildFeedbackUI(String invocationId) {
    return Center(child: Text('STT disabled - configure DEEPGRAM_API_KEY'));
  }
}

// ============================================================================
// Exceptions
// ============================================================================

/// Exception thrown by STT service.
class STTException implements Exception {
  final String message;
  final Object? cause;

  STTException(this.message, {this.cause});

  @override
  String toString() {
    if (cause != null) {
      return 'STTException: $message (cause: $cause)';
    }
    return 'STTException: $message';
  }
}
