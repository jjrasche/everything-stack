/// Mock Deepgram Implementer - returns canned STT response for testing
///
/// Implements STTImplementer interface but returns hardcoded responses
/// instead of hitting the real Deepgram API. Used in CI mode integration tests.
///
/// Supports failure mode for error handling tests via shouldFail parameter.

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
}
