/// # Generic Integration Test Entry Point
///
/// Single entry point for all integration tests.
///
/// Run all tests:
/// ```bash
/// flutter test integration_test/shared/generic_test.dart -d <platform>
/// ```
///
/// Run single test:
/// ```bash
/// flutter test integration_test/shared/generic_test.dart --dart-define=TEST=timer -d <platform>
/// ```
///
/// Smoke mode (real APIs):
/// ```bash
/// flutter test integration_test/shared/generic_test.dart --dart-define=SMOKE_TEST=true -d <platform>
/// ```

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'test_harness.dart';
import '../timer_multiturn_logic.dart';
import '../audio_pipeline_logic.dart';
import '../invocation_semantic_logic.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final testName = const String.fromEnvironment('TEST', defaultValue: '');

  // Aggregate all test configs
  final configs = {
    'timer': timerMultiturnTest,
    'audio': audioPipelineTest,
    'semantic': invocationSemanticTest,
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
