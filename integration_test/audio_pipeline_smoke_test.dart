import 'package:flutter_test/flutter_test.dart';
import '../test/support/audio_pipeline_test_shared.dart';

void main() {
  group('Audio Pipeline Smoke Test', () {
    setUpAll(() async {
      print('🔥 Using REAL services (Groq, Deepgram)');

      // Don't load .env here - let bootstrap handle it
      // If keys are missing, bootstrap will fail during app initialization with clear error
      // .env path resolution is handled by bootstrap's working directory context

      print('✅ Ready to test with real services (bootstrap will validate keys)');

      // Don't register any services - bootstrap will load real ones from .env
    });

    testWidgets('Smoke: Event-driven flow with real services',
        (WidgetTester tester) async {
      await runAudioPipelineTest(tester);
    });
  });
}
