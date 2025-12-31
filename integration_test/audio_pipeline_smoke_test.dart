import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/services/stt_service.dart';
import '../test/support/audio_pipeline_test_shared.dart';
import '../test/support/mock_services.dart';

void main() {
  group('Audio Pipeline Smoke Test', () {
    setUpAll(() async {
      print('🔥 Using REAL services (Deepgram, Groq)');
      print('ℹ️  Debugging WebSocket issue - HTTP works, WebSocket should too');

      // Load .env file BEFORE building app
      // This ensures API keys are available to bootstrap
      await dotenv.load(fileName: '.env');
      print('✅ Environment variables loaded from .env');

      // Don't register mock - let bootstrap load real Deepgram
      // We're debugging why WebSocket fails
      print('✅ Ready to test with real services');
    });

    testWidgets('Smoke: Event-driven flow with real services',
        (WidgetTester tester) async {
      await runAudioPipelineTest(tester);
    });
  });
}
