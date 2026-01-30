/// # Logic Test Runner
///
/// Entry point for test harness tests (*_logic.dart files).
///
/// Run all logic tests:
/// ```bash
/// flutter test integration_test/shared/logic_test_runner.dart -d <platform>
/// ```
///
/// Run single logic test:
/// ```bash
/// flutter test integration_test/shared/logic_test_runner.dart --dart-define=TEST=timer -d <platform>
/// ```
///
/// Smoke mode (real APIs):
/// ```bash
/// flutter test integration_test/shared/logic_test_runner.dart --dart-define=SMOKE_TEST=true -d <platform>
/// ```

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'test_harness.dart';
import '../timer_multiturn_logic.dart';
import '../regulation_logic.dart';
import '../audio_pipeline_logic.dart';
import '../microphone_stt_logic.dart';
import '../invocation_semantic_logic.dart';
import '../error_handling_logic.dart';
import '../enrichment_queue_logic.dart';
import '../enrichment_advanced_logic.dart';
import '../conversational_flow_logic.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final testName = const String.fromEnvironment('TEST', defaultValue: '');

  // Aggregate all test configs
  final configs = {
    'conversational_flow': conversationalFlowTest,
    'timer': timerMultiturnTest,
    'regulation': regulationTrackingTest,
    'audio': audioPipelineTest,
    'microphone_stt': microphoneSttTest,
    'semantic': invocationSemanticTest,
    'llm_failure': llmFailureTest,
    'stt_failure': sttFailureTest,
    'stt_live_timeout': sttLiveStreamingTimeoutTest,
    'tts_failure': ttsFailureTest,
    'enrichment_queue': enrichmentQueueTest,
    'startup_recovery': startupRecoveryTest,
    'entity_update_cancels': entityUpdateCancelsTest,
    'batch_failures': batchPartialFailuresTest,
    'concurrent_saves': concurrentSavesTest,
    'entity_deleted': entityDeletedDuringProcessingTest,
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
