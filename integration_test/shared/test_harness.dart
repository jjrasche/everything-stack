/// # Test Harness
///
/// DI magic for integration tests. Write once, reuse forever.
/// Handles service swapping (real repos, mock external APIs).

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/main.dart';
import 'package:everything_stack_template/services/inference_service.dart';
import 'package:everything_stack_template/services/tts_service.dart';
import 'package:everything_stack_template/services/stt_service.dart';
import 'package:everything_stack_template/services/types/llm_types.dart';
import 'package:everything_stack_template/services/coordinator.dart';
import 'package:everything_stack_template/services/context_selector.dart';
import 'package:everything_stack_template/services/tool_executor.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/event_bus.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/core/adaptation_state_repository.dart';
import 'package:everything_stack_template/core/feedback_repository.dart';
import 'test_context.dart';
import 'response_map_implementer.dart';
import '../mocks/mock_flutter_tts_implementer.dart';
import '../mocks/mock_deepgram_implementer.dart';

/// Configuration for a single integration test.
///
/// Runs in two modes (controlled by SMOKE_TEST environment variable):
/// - **Smoke mode** (SMOKE_TEST=true): Uses real external APIs
/// - **CI mode** (default): Uses mocked external APIs with real repos
class IntegrationTestConfig {
  final String name;
  final List<Type> repos;
  final Map<String, String>? utterances; // Optional (only for STT tests)
  final Map<String, Map<String, LLMResponse>>? mockResponses; // Optional
  final Future<void> Function(TestContext) testLogic;

  const IntegrationTestConfig({
    required this.name,
    this.repos = const [],
    this.utterances,
    this.mockResponses,
    required this.testLogic,
  });

  /// Runs the test with automatic service setup/teardown.
  void run() {
    final isSmoke = const bool.fromEnvironment('SMOKE_TEST', defaultValue: false);
    final modeName = isSmoke ? 'Smoke (Real APIs)' : 'CI (Mocked APIs)';

    group('$name - $modeName', () {
      testWidgets('full test', (WidgetTester tester) async {
        // 1. Build app FIRST (bootstrap creates real repos)
        await tester.pumpWidget(const MyApp());
        await tester.pumpAndSettle(const Duration(seconds: 5));

        // 2. Swap external implementers (only in CI mode)
        if (!isSmoke) {
          // Always swap embedding service in CI mode to avoid real API calls
          _swapEmbeddingService();

          if (mockResponses != null) {
            await _swapExternalImplementers(tester, mockResponses!);
          }

          // Register Coordinator now that services exist
          await _registerCoordinator();
        }

        // 3. Create TestContext
        final testContext = TestContext(tester, repos, utterances);

        // 4. Run test logic
        await testLogic(testContext);
      });

      tearDownAll(() {
        GetIt.instance.reset();
      });
    });
  }

  /// Swap embedding service to mock (avoid real API calls in tests)
  void _swapEmbeddingService() {
    EmbeddingService.instance = MockEmbeddingService();
    print('✅ Swapped EmbeddingService: MockEmbeddingService (no API calls)');
  }

  /// Swap external implementers with mocks (keep real repos)
  Future<void> _swapExternalImplementers(
    WidgetTester tester,
    Map<String, Map<String, LLMResponse>> mockResponses,
  ) async {
    final getIt = GetIt.instance;

    for (final entry in mockResponses.entries) {
      final serviceName = entry.key;
      final responses = entry.value;

      switch (serviceName) {
        case 'groq':
          // Get REAL repos (already exist from bootstrap)
          final invocationRepo = getIt<InvocationRepository<Invocation>>();
          final adaptationRepo = getIt<AdaptationStateRepository>();
          final feedbackRepo = getIt<FeedbackRepository>();

          // Unregister service if it exists (bootstrap may skip registration)
          if (getIt.isRegistered<InferenceService>()) {
            getIt.unregister<InferenceService>();
          }

          // Register with MOCK implementer + REAL repos
          getIt.registerSingleton<InferenceService>(
            InferenceService(
              implementers: {
                'groq': ResponseMapLLMImplementer(responses),
              },
              defaultImplementer: 'groq',
              invocationRepo: invocationRepo,
              adaptationStateRepo: adaptationRepo,
              feedbackRepo: feedbackRepo,
            ),
          );
          print('✅ Swapped InferenceService: ResponseMapLLMImplementer + real repos');
          break;

        case 'tts':
          final invocationRepo = getIt<InvocationRepository<Invocation>>();
          final adaptationRepo = getIt<AdaptationStateRepository>();
          final feedbackRepo = getIt<FeedbackRepository>();

          if (getIt.isRegistered<TTSService>()) {
            getIt.unregister<TTSService>();
          }
          getIt.registerSingleton<TTSService>(
            TTSService(
              implementers: {
                'flutter_tts': MockFlutterTTSImplementer(),
              },
              defaultImplementer: 'flutter_tts',
              invocationRepo: invocationRepo,
              adaptationStateRepo: adaptationRepo,
              feedbackRepo: feedbackRepo,
            ),
          );
          print('✅ Swapped TTSService: MockFlutterTTSImplementer + real repos');
          break;

        case 'deepgram':
          final invocationRepo = getIt<InvocationRepository<Invocation>>();
          final adaptationRepo = getIt<AdaptationStateRepository>();
          final feedbackRepo = getIt<FeedbackRepository>();

          if (getIt.isRegistered<STTService>()) {
            getIt.unregister<STTService>();
          }
          getIt.registerSingleton<STTService>(
            STTService(
              implementers: {
                'deepgram': MockDeepgramImplementer(),
              },
              defaultImplementer: 'deepgram',
              invocationRepo: invocationRepo,
              adaptationStateRepo: adaptationRepo,
              feedbackRepo: feedbackRepo,
            ),
          );
          print('✅ Swapped STTService: MockDeepgramImplementer + real repos');
          break;

        default:
          print('⚠️ Unknown service: $serviceName');
      }
    }

    await tester.pump();
  }

  /// Register Coordinator after services are available
  Future<void> _registerCoordinator() async {
    final getIt = GetIt.instance;

    // Only register if not already registered
    if (getIt.isRegistered<Coordinator>()) {
      print('ℹ️ Coordinator already registered, skipping');
      return;
    }

    print('🔍 Registering Coordinator...');
    final coordinator = Coordinator(
      embeddingService: EmbeddingService.instance,
      llmService: getIt<InferenceService>(),
      ttsService: getIt<TTSService>(),
      toolExecutor: getIt<ToolExecutor>(),
      contextSelector: getIt<ContextSelector>(),
      invocationRepo: getIt<InvocationRepository<Invocation>>(),
      eventBus: getIt<EventBus>(),
    );
    getIt.registerSingleton<Coordinator>(coordinator);
    coordinator.initialize();
    print('✅ Coordinator registered and initialized');
  }
}
