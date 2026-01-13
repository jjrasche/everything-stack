/// Mock FlutterTTS Implementer - returns canned TTS response for testing
///
/// Implements TTSImplementer interface but returns hardcoded responses
/// instead of hitting the real Flutter TTS API. Used in CI mode integration tests.

import 'package:everything_stack_template/services/implementations/tts_implementer.dart';
import 'package:everything_stack_template/services/types/tts_types.dart';

class MockFlutterTTSImplementer implements TTSImplementer {
  @override
  String get implementerName => 'flutter_tts';

  @override
  Future<TTSInvocationOutput> synthesize({
    required String text,
    required String voiceId,
    required double speechRate,
    required double pitch,
  }) async {
    print('🔊 MockFlutterTTSImplementer.synthesize(): Returning canned audio (no API call)');
    print('   📝 Text: "$text"');
    print('   🎙️ Voice: $voiceId');
    // In real scenario, this would return actual audio bytes
    // For testing, just return metadata
    return TTSInvocationOutput(
      audioId: 'mock_audio_${DateTime.now().millisecondsSinceEpoch}',
      durationSeconds: 2.5,
      latencyMs: 75,
    );
  }
}
