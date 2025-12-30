/// # Audio Pipeline E2E Test (Layer 4 - Platform Integration)
///
/// Real end-to-end test of the complete event-driven audio pipeline:
/// 1. App boots → Coordinator.initialize() wires listener to EventBus
/// 2. STTService publishes TranscriptionComplete event (simulated by test)
/// 3. EventBus routes event to Coordinator listener
/// 4. Coordinator listener automatically calls orchestrate()
/// 5. ALL 6 REAL components execute:
///    - NamespaceSelector (REAL)
///    - ToolSelector (REAL)
///    - ContextInjector (REAL)
///    - LLMConfigSelector (REAL)
///    - LLMOrchestrator (REAL)
///    - ResponseRenderer (REAL)
/// 6. Each component records invocation to InvocationRepository
/// 7. EventBus persists TranscriptionComplete event
///
/// This tests the REAL event-driven flow:
/// STT → EventBus → Coordinator listener → orchestrate() → 6 components
///
/// ASSERTIONS:
/// - Coordinator listener is active and receives events
/// - InvocationRepository has 5+ invocations (one per component)
/// - All invocations share same correlationId
/// - EventBus has TranscriptionComplete event persisted
/// - Orchestration triggered by event, not direct code call

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import '../test/support/mock_services.dart';
import '../test/support/audio_pipeline_test_shared.dart';

void main() {
  group('Audio Pipeline E2E Test - Real UI to Real Persistence', () {
    setUpAll(() async {
      // Register mock services BEFORE app builds
      // This ensures bootstrap uses mocks instead of real services
      print('📝 Using MOCK services (CI mode)');
      GetIt.instance.registerSingleton<LLMService>(MockLLMService());
      GetIt.instance.registerSingleton<STTService>(MockSTTService());
      print('✅ Mock services registered');
    });

    testWidgets('E2E: Event-driven flow with mocked services',
        (WidgetTester tester) async {
      // Shared test logic - works with mocked services
      await runAudioPipelineTest(tester);
    });
  });
}
