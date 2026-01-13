/// # Generic Integration Test Entry Point
///
/// Single entry point for all integration tests. Configuration is data-driven
/// and defined inline below.
///
/// Run all tests:
/// ```bash
/// flutter test integration_test/shared/generic_test.dart -d <platform>
/// ```
///
/// Run single test:
/// ```bash
/// flutter test integration_test/shared/generic_test.dart --dart-define=TEST=invocation_semantic -d <platform>
/// ```
///
/// Smoke mode (real APIs, capture fixtures):
/// ```bash
/// flutter test integration_test/shared/generic_test.dart --dart-define=SMOKE_TEST=true -d <platform>
/// ```

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:everything_stack_template/services/inference_service.dart';
import 'package:everything_stack_template/services/stt_service.dart';
import 'test_harness.dart';
import '../mocks/services_setup.dart';
import '../invocation_semantic_logic.dart';
import '../audio_pipeline_logic.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final testName = const String.fromEnvironment('TEST', defaultValue: '');

  // Define all test configurations inline
  final configs = {
    'invocation_semantic': IntegrationTestConfig(
      name: 'Invocation Semantic Search',
      services: [
        ServiceConfig.embedding(fixture: 'invocation_embeddings.json'),
      ],
      testLogic: (tester) async {
        await runInvocationSemanticTest();
      },
    ),
    'audio_pipeline': IntegrationTestConfig(
      name: 'Audio Pipeline',
      services: [
        ServiceConfig(
          setup: (bool isSmoke) async {
            if (isSmoke) {
              print('🔥 Smoke: Real services (loading .env)');
              await dotenv.load(fileName: '.env');
              print('✅ Real Deepgram/Groq services configured');
            } else {
              print('📝 CI: Mock services (real services + mock implementers)');
              GetIt.instance.registerSingleton<InferenceService>(createMockInferenceService());
              GetIt.instance.registerSingleton<STTService>(
                createEnhancedMockSTTService(
                  transcriptToEmit: 'one plus one',
                  processingDelay: const Duration(milliseconds: 100),
                ),
              );
              print('✅ Mock services registered');
            }
          },
        ),
      ],
      testLogic: runAudioPipelineTest,
    ),
  };

  if (testName.isEmpty) {
    // Run all tests
    for (final config in configs.values) {
      config.run();
    }
  } else {
    // Run single test
    final config = configs[testName];
    if (config == null) {
      throw Exception(
        'Unknown test: $testName\n'
        'Available tests: ${configs.keys.join(", ")}',
      );
    }
    config.run();
  }
}
