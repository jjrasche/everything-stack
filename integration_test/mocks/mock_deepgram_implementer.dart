/// Mock Deepgram Implementer - returns canned STT response for testing
///
/// Implements STTImplementer interface but returns hardcoded responses
/// instead of hitting the real Deepgram API. Used in CI mode integration tests.
///
/// Supports failure mode for error handling tests via shouldFail parameter.

import 'dart:convert';
import 'dart:typed_data';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/services/event_bus.dart';
import 'package:everything_stack_template/core/event.dart';
import 'package:everything_stack_template/services/implementations/stt_implementer.dart';
import 'package:everything_stack_template/services/types/stt_types.dart';
import 'package:everything_stack_template/services/types/word.dart';

class MockDeepgramImplementer implements STTImplementer {
  final bool shouldFail;

  MockDeepgramImplementer({this.shouldFail = false});

  @override
  String get implementerName => 'deepgram';

  @override
  Set<String> get supportedPlatforms => {
        'android',
        'ios',
        'macos',
        'windows',
        'linux',
        'web',
        // Mock supports all platforms (no real API dependencies)
      };

  @override
  Future<STTInvocationOutput> recognize({
    required String audioId,
    required double durationSeconds,
    String? eventId,
    double? eotThreshold,
    double? eagerEotThreshold,
    int? eotTimeoutMs,
    bool? enablePartialTranscripts,
    bool? enableEagerProcessing,
  }) async {
    if (shouldFail) {
      print('💥 MockDeepgramImplementer.recognize(): Simulating failure');
      throw Exception('Mock STT failure: Simulated transcription error');
    }

    print('🎤 MockDeepgramImplementer.recognize(): Returning canned transcription (no API call)');
    const transcription = 'mock transcription from audio';
    final words = transcription.split(' ').asMap().entries.map((e) {
      return Word(
        text: e.value,
        confidence: 0.95,
        startTime: e.key * 0.5,
        endTime: (e.key + 1) * 0.5,
      );
    }).toList();

    return STTInvocationOutput(
      transcription: transcription,
      confidence: 0.95,
      words: words,
      latencyMs: 50,
    );
  }

  @override
  Future<STTInvocationOutput> startLiveRecognition({
    required Stream<Uint8List> audioStream,
    required String eventId,
    double? eotThreshold,
    double? eagerEotThreshold,
    int? eotTimeoutMs,
    bool? enablePartialTranscripts,
    bool? enableEagerProcessing,
  }) {
    throw UnsupportedError('MockDeepgramImplementer does not support live streaming');
  }
}

/// Enhanced Mock Deepgram Implementer - configurable transcription response
///
/// Allows tests to specify what transcript should be returned.
/// Useful for testing different scenarios (e.g., "one plus one", error cases).
///
/// Supports failure mode for error handling tests via shouldFail parameter.
class EnhancedMockDeepgramImplementer implements STTImplementer {
  final String transcriptToEmit;
  final Duration processingDelay;
  final bool shouldFail;

  EnhancedMockDeepgramImplementer({
    this.transcriptToEmit = 'mock transcription',
    this.processingDelay = const Duration(milliseconds: 100),
    this.shouldFail = false,
  });

  @override
  String get implementerName => 'deepgram';

  @override
  Set<String> get supportedPlatforms => {
        'android',
        'ios',
        'macos',
        'windows',
        'linux',
        'web',
        // Mock supports all platforms (no real API dependencies)
      };

  @override
  Future<STTInvocationOutput> recognize({
    required String audioId,
    required double durationSeconds,
    String? eventId,
    double? eotThreshold,
    double? eagerEotThreshold,
    int? eotTimeoutMs,
    bool? enablePartialTranscripts,
    bool? enableEagerProcessing,
  }) async {
    if (shouldFail) {
      print('💥 EnhancedMockDeepgramImplementer.recognize(): Simulating failure');
      throw Exception('Mock STT failure: Simulated transcription error');
    }

    print('🎤 EnhancedMockDeepgramImplementer.recognize(): Processing audio (configurable)');
    print('   📝 Duration: ${durationSeconds}s');

    // Simulate processing delay
    await Future.delayed(processingDelay);

    print('   📤 Emitting transcript: "$transcriptToEmit"');

    // Split transcript into words with timing
    final words = transcriptToEmit.split(' ').asMap().entries.map((e) {
      return Word(
        text: e.value,
        confidence: 0.95,
        startTime: e.key * 0.5,
        endTime: (e.key + 1) * 0.5,
      );
    }).toList();

    return STTInvocationOutput(
      transcription: transcriptToEmit,
      confidence: 0.95,
      words: words,
      latencyMs: processingDelay.inMilliseconds.toDouble(),
    );
  }

  @override
  Future<STTInvocationOutput> startLiveRecognition({
    required Stream<Uint8List> audioStream,
    required String eventId,
    double? eotThreshold,
    double? eagerEotThreshold,
    int? eotTimeoutMs,
    bool? enablePartialTranscripts,
    bool? enableEagerProcessing,
  }) {
    throw UnsupportedError('EnhancedMockDeepgramImplementer does not support live streaming');
  }
}

/// Custom exception for Deepgram errors (matches real DeepgramException behavior)
class DeepgramException implements Exception {
  final String message;
  DeepgramException(this.message);

  @override
  String toString() => 'DeepgramException: $message';
}

/// Live Streaming Mock Deepgram Implementer
///
/// Supports startLiveRecognition for testing live audio streaming scenarios.
/// Can simulate:
/// - Successful transcription
/// - Timeout errors (simulates 30s recognition timeout)
/// - Connection errors
///
/// IMPORTANT: This mock publishes the same EventBus events as the real
/// DeepgramFluxImplementer to ensure tests catch event-related regressions:
/// - start_of_turn: When user starts speaking (barge-in detection)
/// - end_of_turn: When user finishes speaking (auto-stop recording)
///
/// Use this for testing UI error handling of live streaming failures.
class LiveStreamingMockDeepgramImplementer implements STTImplementer {
  final String transcriptToEmit;
  final bool shouldTimeout;
  final bool shouldFail;
  final Duration? processingDelay;
  final bool publishEvents; // Whether to publish EventBus events like real implementer

  LiveStreamingMockDeepgramImplementer({
    this.transcriptToEmit = 'live mock transcription',
    this.shouldTimeout = false,
    this.shouldFail = false,
    this.processingDelay,
    this.publishEvents = true, // Default: mirror real implementer behavior
  });

  @override
  String get implementerName => 'deepgram_flux';

  @override
  Set<String> get supportedPlatforms => {
        'android',
        'ios',
        'macos',
        'windows',
        'linux',
        'web',
      };

  @override
  Future<STTInvocationOutput> recognize({
    required String audioId,
    required double durationSeconds,
    String? eventId,
    double? eotThreshold,
    double? eagerEotThreshold,
    int? eotTimeoutMs,
    bool? enablePartialTranscripts,
    bool? enableEagerProcessing,
  }) async {
    if (shouldFail) {
      throw Exception('Mock STT failure: Simulated transcription error');
    }

    final words = transcriptToEmit.split(' ').asMap().entries.map((e) {
      return Word(
        text: e.value,
        confidence: 0.95,
        startTime: e.key * 0.5,
        endTime: (e.key + 1) * 0.5,
      );
    }).toList();

    return STTInvocationOutput(
      transcription: transcriptToEmit,
      confidence: 0.95,
      words: words,
      latencyMs: 50,
    );
  }

  @override
  Future<STTInvocationOutput> startLiveRecognition({
    required Stream<Uint8List> audioStream,
    required String eventId,
    double? eotThreshold,
    double? eagerEotThreshold,
    int? eotTimeoutMs,
    bool? enablePartialTranscripts,
    bool? enableEagerProcessing,
  }) async {
    print('🎤 LiveStreamingMockDeepgramImplementer.startLiveRecognition()');
    print('   eventId: $eventId');
    print('   shouldTimeout: $shouldTimeout, shouldFail: $shouldFail');
    print('   publishEvents: $publishEvents');

    // Simulate processing delay if specified
    if (processingDelay != null) {
      await Future.delayed(processingDelay!);
    }

    // Simulate timeout (matches real Deepgram behavior)
    if (shouldTimeout) {
      print('💥 Simulating recognition timeout');
      throw DeepgramException('Recognition timeout after 30s');
    }

    // Simulate generic failure
    if (shouldFail) {
      print('💥 Simulating connection failure');
      throw DeepgramException('WebSocket connection failed');
    }

    // Publish start_of_turn event (mirrors real DeepgramFluxImplementer)
    // This is critical for barge-in detection
    if (publishEvents) {
      final eventBus = GetIt.instance<EventBus>();
      await eventBus.publish(Event(
        eventType: 'start_of_turn',
        correlationId: eventId,
        source: 'stt',
        payloadJson: jsonEncode({
          'transcript': '',
          'confidence': 0.0,
        }),
      ));
      print('📡 [Mock] Published start_of_turn event');
    }

    // Consume the audio stream (required for proper cleanup)
    await for (final _ in audioStream) {
      // Discard chunks
    }

    // Publish end_of_turn event (mirrors real DeepgramFluxImplementer)
    // This is critical for continuous conversation mode
    if (publishEvents) {
      final eventBus = GetIt.instance<EventBus>();
      await eventBus.publish(Event(
        eventType: 'end_of_turn',
        correlationId: eventId,
        source: 'stt',
        payloadJson: jsonEncode({
          'transcript': transcriptToEmit,
          'confidence': 0.95,
          'latency_ms': 100.0,
        }),
      ));
      print('📡 [Mock] Published end_of_turn event');
    }

    print('✅ Returning mock transcription: "$transcriptToEmit"');

    final words = transcriptToEmit.split(' ').asMap().entries.map((e) {
      return Word(
        text: e.value,
        confidence: 0.95,
        startTime: e.key * 0.5,
        endTime: (e.key + 1) * 0.5,
      );
    }).toList();

    return STTInvocationOutput(
      transcription: transcriptToEmit,
      confidence: 0.95,
      words: words,
      latencyMs: 100,
    );
  }
}
