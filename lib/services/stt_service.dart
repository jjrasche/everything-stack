import 'dart:async';
import 'dart:typed_data';

import 'streaming_service.dart';
import 'timeout_config.dart';

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
abstract class STTService extends StreamingService<Uint8List, String> {
  /// Global instance (default: NullSTTService)
  ///
  /// Replace with DeepgramSTTService in bootstrap:
  /// ```dart
  /// STTService.instance = DeepgramSTTService(apiKey: '...');
  /// await STTService.instance.initialize();
  /// ```
  static STTService instance = NullSTTService();

  /// Stream audio bytes, receive transcript chunks.
  ///
  /// Convenience wrapper around [stream] with STT-specific types.
  ///
  /// ## Parameters
  /// - [audio]: Stream of audio bytes (e.g., from microphone)
  /// - [onTranscript]: Called for each transcript chunk
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
  ///   onError: (e) => _showError(e),
  /// );
  /// ```
  StreamSubscription<String> transcribe({
    required Stream<Uint8List> audio,
    required void Function(String) onTranscript,
    required void Function(Object) onError,
    void Function()? onDone,
  }) {
    return stream(
      input: audio,
      onData: onTranscript,
      onError: onError,
      onDone: onDone,
    );
  }
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

  bool _isReady = false;

  DeepgramSTTService({
    required this.apiKey,
    this.model = 'nova-2',
    this.language = 'en-US',
  });

  @override
  Future<void> initialize() async {
    // TODO: Implement WebSocket connection setup
    // - Validate API key
    // - Test connection with timeout
    // - Set _isReady = true on success

    print('DeepgramSTTService.initialize() - STUB: Not implemented');
    _isReady = true; // Fake success for now
  }

  @override
  StreamSubscription<String> stream({
    required Stream<Uint8List> input,
    required void Function(String) onData,
    required void Function(Object) onError,
    void Function()? onDone,
  }) {
    // TODO: Implement WebSocket streaming
    // 1. Connect to Deepgram with connection timeout
    // 2. Send audio bytes from input stream
    // 3. Receive transcript chunks from WebSocket
    // 4. Apply idle timeout (30s no data → close)
    // 5. Handle errors gracefully

    print('DeepgramSTTService.stream() - STUB: Not implemented');

    // Return empty stream for now
    onError(STTException('DeepgramSTTService not implemented'));
    return Stream<String>.empty().listen(null);
  }

  @override
  void dispose() {
    // TODO: Close WebSocket connection
    _isReady = false;
    print('DeepgramSTTService.dispose() - STUB: Not implemented');
  }

  @override
  bool get isReady => _isReady;
}

// ============================================================================
// Null STT Service (Safe Fallback)
// ============================================================================

/// Null Object implementation for STT service.
///
/// Used when STT is not configured.
/// Fails gracefully without crashing the app.
class NullSTTService extends STTService {
  @override
  Future<void> initialize() async {
    print('Warning: STTService not configured (using NullSTTService)');
  }

  @override
  StreamSubscription<String> stream({
    required Stream<Uint8List> input,
    required void Function(String) onData,
    required void Function(Object) onError,
    void Function()? onDone,
  }) {
    onError(STTException('STT not configured'));
    return Stream<String>.empty().listen(null);
  }

  @override
  void dispose() {}

  @override
  bool get isReady => false;
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
