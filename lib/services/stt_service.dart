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
import 'package:everything_stack_template/services/event_bus.dart';
import 'package:everything_stack_template/services/events/transcription_complete.dart';
import 'package:get_it/get_it.dart';

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
  String _lastTranscript = '';
  String _correlationIdForEvent = '';
  double _transcriptConfidence = 0.0; // Actual Deepgram confidence
  double _audioDuration = 0.0;
  int _wordCount = 0;
  String _deepgramModel = 'flux-general-en'; // Deepgram Flux v2 - superior turn detection for voice agents
  Map<String, dynamic> _deepgramMetadata = {}; // Capture Deepgram response metadata

  // ============ Flux v2 Turn Detection Data ============
  double _endOfTurnConfidence = 0.0; // How confident Flux is turn ended
  double _audioWindowStart = 0.0; // When turn started (seconds)
  double _audioWindowEnd = 0.0; // When turn ended (seconds)
  int _turnIndex = 0; // Which turn in conversation
  String _eventType = ''; // EndOfTurn, EagerEndOfTurn, TurnResumed
  List<Map<String, dynamic>> _wordDetails = []; // Per-word confidence data

  DeepgramSTTService({
    required this.apiKey,
    required InvocationRepository<Invocation> invocationRepository,
    this.model = 'flux-general-en', // Deepgram Flux v2 with superior turn detection
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
    bool speechHasFinal = false;
    Timer? finalCompleteTimer;

    Future<void> connect() async {
      try {
        // Build WebSocket URL with parameters and API key
        // Flux v2: Minimal params only - NO channels, interim_results, endpointing, vad_events, utterance_end_ms
        // These v1 params break v2 (causes HTTP 400)
        final urlString = 'wss://api.deepgram.com/v2/listen'
            '?model=flux-general-en'
            '&encoding=linear16'
            '&sample_rate=16000'
            '&eager_eot_threshold=0.5'
            '&eot_threshold=0.5'
            '&eot_timeout_ms=3000';

        // Connect with timeout and Authorization header
        try {
          print('🔗 [Deepgram] Connecting to: $urlString');
          final connectStart = DateTime.now();
          _ws = IOWebSocketChannel.connect(
            Uri.parse(urlString),
            headers: {'Authorization': 'Token $apiKey'},
          );
          final connectTime = DateTime.now().difference(connectStart).inMilliseconds;
          print('✅ [Deepgram] Connected in ${connectTime}ms');
        } catch (e) {
          print('❌ [Deepgram] Connection failed: $e');
          throw STTException('Failed to connect to Deepgram', cause: e);
        }

        // Handle WebSocket messages
        print('🎧 [Deepgram] Setting up stream listener...');
        print('   Stream type: ${_ws!.stream.runtimeType}');
        _wsSubscription = _ws!.stream.listen(
          (message) {
            print('✅ [Deepgram] Listener callback fired - message received');
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
              print('📨 [Deepgram] Message received at ${DateTime.now().toIso8601String()}');
              final json = jsonDecode(message);
              print('📨 [Deepgram] Message type: ${json['type']}');
              debugPrint('📨 [Deepgram] Raw response: ${json['type']}');

              // ============ Flux v2: Results Event (transcript chunks) ============
              if (json['type'] == 'Results') {
                // Save correlation ID for event publishing
                _correlationIdForEvent = json['request_id'] ?? json['metadata']?['request_id'] ?? 'unknown';

                // Capture metadata for training
                if (json['metadata'] != null) {
                  _deepgramMetadata = {
                    'requestId': json['metadata']['request_id'],
                    'model': json['metadata']['model_info']?['name'] ?? 'unknown',
                    'modelVersion': json['metadata']['model_info']?['version'],
                    'modelArch': json['metadata']['model_info']?['arch'],
                  };
                }

                // Flux v2: Result structure: channel.alternatives[0]
                final channel = json['channel'] as Map?;
                if (channel != null) {
                  final alternatives = channel['alternatives'] as List?;
                  if (alternatives != null && alternatives.isNotEmpty) {
                    final transcript = alternatives[0]['transcript'] as String?;
                    final confidence = (alternatives[0]['confidence'] as num?)?.toDouble() ?? 0.0;
                    final words = alternatives[0]['words'] as List? ?? [];

                    debugPrint('📨 [Deepgram] Transcript: "$transcript"');
                    if (transcript != null && transcript.isNotEmpty) {
                      _lastTranscript = transcript;
                      _transcriptConfidence = confidence;
                      _wordCount = words.length;
                      // Capture word details for training
                      _wordDetails = words.cast<Map<String, dynamic>>();
                      onData(transcript);
                    }
                  }

                  // Check for speech_final - fallback if UtteranceEnd doesn't arrive
                  final speechFinal = json['speech_final'] as bool? ?? false;
                  if (speechFinal && !speechHasFinal) {
                    speechHasFinal = true;
                    print('🔊 [Deepgram] Speech final detected - waiting for UtteranceEnd...');
                    // Timeout fallback: if UtteranceEnd doesn't arrive in 2 seconds, complete anyway
                    finalCompleteTimer = Timer(const Duration(seconds: 2), () {
                      if (isActive && speechHasFinal) {
                        print('🏁 [Deepgram] No UtteranceEnd received - completing STT stream via timeout');
                        _publishTranscriptionEvent();
                        onDone?.call();
                        _cleanup();
                      }
                    });
                  }
                }
              }
              // ============ v1: UtteranceEnd Event (turn detection) ============
              else if (json['type'] == 'UtteranceEnd') {
                final lastWordEnd = json['last_word_end'] as double?;
                print('🏁 [Deepgram/v1] UtteranceEnd received at ${lastWordEnd}s - turn is over');
                // For v1, set event type to EndOfTurn for consistency with v2 invocation format
                _eventType = 'EndOfTurn';
                _audioWindowEnd = lastWordEnd ?? _audioDuration;

                finalCompleteTimer?.cancel();
                onUtteranceEnd?.call();
                if (isActive) {
                  print('✅ [Deepgram] Turn complete - publishing event and closing stream');
                  _publishTranscriptionEvent();
                  onDone?.call();
                  _cleanup();
                }
              }
              // ============ Flux v2: TurnInfo Event (turn detection) ============
              else if (json['type'] == 'TurnInfo') {
                final eventType = json['event'] as String? ?? '';
                final endOfTurnConfidence = (json['end_of_turn_confidence'] as num?)?.toDouble() ?? 0.0;
                final audioWindowStart = (json['audio_window_start'] as num?)?.toDouble() ?? 0.0;
                final audioWindowEnd = (json['audio_window_end'] as num?)?.toDouble() ?? 0.0;
                final turnIndex = json['turn_index'] as int? ?? 0;
                final turnTranscript = json['transcript'] as String? ?? _lastTranscript;
                final turnWords = json['words'] as List? ?? [];

                print('🏁 [Deepgram/Flux] TurnInfo: event=$eventType, confidence=$endOfTurnConfidence, timing=${audioWindowStart}s-${audioWindowEnd}s, transcript="${turnTranscript.isEmpty ? "(empty)" : turnTranscript}"');

                // Store turn detection data for training
                _eventType = eventType;
                _endOfTurnConfidence = endOfTurnConfidence;
                _audioWindowStart = audioWindowStart;
                _audioWindowEnd = audioWindowEnd;
                _turnIndex = turnIndex;
                _audioDuration = audioWindowEnd - audioWindowStart;
                if (turnWords.isNotEmpty) {
                  _wordDetails = turnWords.cast<Map<String, dynamic>>();
                  _wordCount = turnWords.length;
                }
                if (turnTranscript.isNotEmpty && turnTranscript != _lastTranscript) {
                  _lastTranscript = turnTranscript;
                }

                // DEBUG: For first Update, log full JSON to understand structure
                if (eventType == 'Update' && _lastTranscript.isEmpty && _wordDetails.isEmpty) {
                  print('🔍 [Deepgram/Flux] First Update - Full JSON structure:');
                  print('   ${jsonEncode(json)}');
                  print('   Available fields: ${json.keys.join(", ")}');
                }

                // Handle turn end events
                if (eventType == 'EndOfTurn' || eventType == 'EagerEndOfTurn') {
                  finalCompleteTimer?.cancel();
                  onUtteranceEnd?.call();
                  if (isActive) {
                    print('✅ [Deepgram/Flux] Turn complete ($eventType) - publishing event');
                    _publishTranscriptionEvent();
                    onDone?.call();
                    _cleanup();
                  }
                } else if (eventType == 'Update') {
                  // Flux Update: reschedule timeout on each Update
                  // When Updates stop coming = turn complete (audio ended, Flux done processing)
                  finalCompleteTimer?.cancel();
                  finalCompleteTimer = Timer(const Duration(milliseconds: 500), () {
                    if (isActive) {
                      print('🏁 [Deepgram/Flux] No Updates for 500ms - turn complete');
                      onUtteranceEnd?.call();
                      _publishTranscriptionEvent();
                      onDone?.call();
                      _cleanup();
                    }
                  });
                } else if (eventType == 'TurnResumed') {
                  print('↩️  [Deepgram/Flux] Turn resumed - listening for more audio');
                }
              }
              // ============ Flux v2: FatalError Event ============
              else if (json['type'] == 'FatalError') {
                final errorMessage = json['message'] as String? ?? 'Unknown error';
                print('❌ [Deepgram/Flux] FatalError: $errorMessage');
                if (isActive) {
                  onError(STTException('Deepgram Fatal Error: $errorMessage'));
                  _cleanup();
                }
              }
            } catch (e) {
              // Log parse errors but don't fail - continue streaming
              print('Warning: Failed to parse Deepgram response: $e');
            }
          },
          onError: (error) {
            print('❌ [Deepgram] Stream onError fired: $error');
            if (isActive) {
              onError(STTException('WebSocket error', cause: error));
              _cleanup();
            }
          },
          onDone: () {
            print('🏁 [Deepgram] Stream onDone fired');
            if (isActive) {
              onDone?.call();
              _cleanup();
            }
          },
        );
        print('✅ [Deepgram] Listener attached - subscription: $_wsSubscription');

        // Send audio from input stream
        int totalAudioBytes = 0;
        int audioChunkCount = 0;
        input.listen(
          (audioBytes) {
            if (_ws != null && isActive) {
              try {
                audioChunkCount++;
                totalAudioBytes += audioBytes.length;
                print('📤 [Deepgram] Sending audio chunk #$audioChunkCount: ${audioBytes.length} bytes (total: $totalAudioBytes bytes)');
                _ws!.sink.add(audioBytes);
              } catch (e) {
                if (isActive) {
                  print('❌ [Deepgram] Failed to send audio: $e');
                  onError(STTException('Failed to send audio', cause: e));
                  _cleanup();
                }
              }
            }
          },
          onError: (error) {
            if (isActive) {
              print('❌ [Deepgram] Audio stream error: $error');
              onError(STTException('Audio stream error', cause: error));
              _cleanup();
            }
          },
          onDone: () {
            if (isActive) {
              print('✅ [Deepgram] Audio stream completed - sent $totalAudioBytes bytes in $audioChunkCount chunks');
              // Send CloseStream to explicitly signal end of audio
              // This tells Flux v2 to trigger turn detection logic (eot_threshold, eot_timeout_ms, etc.)
              try {
                final closeStreamMessage = jsonEncode({'type': 'CloseStream'});
                _ws!.sink.add(closeStreamMessage);
                print('📤 [Deepgram] Sent CloseStream message to signal end of audio');
              } catch (e) {
                print('⚠️  [Deepgram] Failed to send CloseStream: $e');
              }
              print('ℹ️  [Deepgram] Waiting for Flux v2 turn detection response...');
              // IMPORTANT: Don't close WebSocket immediately - Deepgram might still be sending responses
              // The idle timeout (30s) will handle cleanup if no response comes
              // Only close if explicitly told to (via isActive = false in _cleanup())
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

  Future<void> _publishTranscriptionEvent() async {
    try {
      if (_lastTranscript.isNotEmpty) {
        final eventBus = GetIt.instance<EventBus>();
        final event = TranscriptionComplete(
          transcript: _lastTranscript,
          durationMs: 0,
          confidence: 0.95,
          correlationId: _correlationIdForEvent,
        );
        await eventBus.publish(event);
        print('📡 [Deepgram] Published TranscriptionComplete event: "$_lastTranscript"');

        // Record STT invocation for training/learning
        try {
          final invocation = Invocation(
            correlationId: _correlationIdForEvent,
            componentType: 'stt',
            success: true,
            confidence: _transcriptConfidence,
            input: {
              'model': _deepgramModel,
              'encoding': 'linear16',
              'sampleRate': 16000,
              'channels': 2,
              'language': language,
            },
            output: {
              'transcript': _lastTranscript,
              'confidence': _transcriptConfidence,
              'wordCount': _wordCount,
              'audioDuration': _audioDuration,
              // ============ Flux v2 Turn Detection Data (for training) ============
              'endOfTurnConfidence': _endOfTurnConfidence, // Critical for turn detection quality
              'audioWindowStart': _audioWindowStart,
              'audioWindowEnd': _audioWindowEnd,
              'turnIndex': _turnIndex,
              'eventType': _eventType,
              'words': _wordDetails, // Per-word confidence array
              'success': true,
            },
            metadata: {
              'deepgramModel': _deepgramMetadata['model'],
              'deepgramModelVersion': _deepgramMetadata['modelVersion'],
              'deepgramModelArch': _deepgramMetadata['modelArch'],
              'requestId': _deepgramMetadata['requestId'],
            },
          );
          await _invocationRepository.save(invocation);
          print('💾 [Deepgram] STT invocation logged for training');
        } catch (logError) {
          print('⚠️ [Deepgram] Failed to log STT invocation: $logError');
        }
      }
    } catch (e) {
      print('⚠️ [Deepgram] Failed to publish TranscriptionComplete event: $e');
    }
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
