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
import 'package:everything_stack_template/services/semantic_search/semantic_search_service.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/core/entity_repository.dart';
import 'package:everything_stack_template/core/adaptation_state_repository.dart';
import 'package:everything_stack_template/core/feedback_repository.dart';
import 'package:everything_stack_template/services/trainables/model_selector.dart';
import 'package:everything_stack_template/services/voice_traits.dart';
import 'package:everything_stack_template/services/context_capacity.dart';
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
  final Map<String, dynamic>? mockImplementers; // Optional (mocked external implementers)
  final Future<void> Function(TestContext) testLogic;

  const IntegrationTestConfig({
    required this.name,
    this.repos = const [],
    this.utterances,
    this.mockImplementers,
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

          if (mockImplementers != null) {
            await _swapExternalImplementers(tester, mockImplementers!);

            // Register Coordinator now that services exist
            await _registerCoordinator();
          }
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
    Map<String, dynamic> mockImplementers,
  ) async {
    final getIt = GetIt.instance;

    for (final entry in mockImplementers.entries) {
      final serviceName = entry.key;
      final implementer = entry.value;

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
                'groq': implementer,
              },
              defaultImplementer: 'groq',
              invocationRepo: invocationRepo,
              adaptationStateRepo: adaptationRepo,
              feedbackRepo: feedbackRepo,
            ),
          );
          print('✅ Swapped InferenceService: ${implementer.runtimeType} + real repos');
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
                'flutter_tts': implementer,
              },
              defaultImplementer: 'flutter_tts',
              invocationRepo: invocationRepo,
              adaptationStateRepo: adaptationRepo,
              feedbackRepo: feedbackRepo,
            ),
          );
          print('✅ Swapped TTSService: ${implementer.runtimeType} + real repos');
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
                'deepgram': implementer,
              },
              defaultImplementer: 'deepgram',
              invocationRepo: invocationRepo,
              adaptationStateRepo: adaptationRepo,
              feedbackRepo: feedbackRepo,
            ),
          );
          print('✅ Swapped STTService: ${implementer.runtimeType} + real repos');
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

    // Unregister ContextSelector if exists (has cached EmbeddingService reference)
    if (getIt.isRegistered<ContextSelector>()) {
      print('ℹ️ ContextSelector already registered, unregistering to re-register with swapped EmbeddingService');
      getIt.unregister<ContextSelector>();
    }

    // Re-register ContextSelector with swapped EmbeddingService
    final contextSelector = ContextSelector(
      invocationRepo: getIt<EntityRepository<Invocation>>(),
      embeddingService: EmbeddingService.instance, // Uses swapped mock
      semanticSearchService: getIt<SemanticSearchService>(),
    );
    getIt.registerSingleton<ContextSelector>(contextSelector);
    print('✅ ContextSelector re-registered with swapped EmbeddingService');

    // Unregister Coordinator if exists (has cached service references)
    if (getIt.isRegistered<Coordinator>()) {
      print('ℹ️ Coordinator already registered, disposing and unregistering...');
      final oldCoordinator = getIt<Coordinator>();
      oldCoordinator.dispose(); // Cancel event listener to prevent double-handling
      getIt.unregister<Coordinator>();
    }

    print('🔍 Registering Coordinator...');

    // Get or create ModelSelector
    ModelSelector modelSelector;
    if (getIt.isRegistered<ModelSelector>()) {
      modelSelector = getIt<ModelSelector>();
    } else {
      // Create ModelSelector with available models from InferenceService
      final availableModels = getIt<InferenceService>().getAvailableModels();
      modelSelector = ModelSelector(availableModels: availableModels);
      getIt.registerSingleton<ModelSelector>(modelSelector);
    }

    final coordinator = Coordinator(
      embeddingService: EmbeddingService.instance,
      llmService: getIt<InferenceService>(),
      ttsService: getIt<TTSService>(),
      toolExecutor: getIt<ToolExecutor>(),
      contextSelector: getIt<ContextSelector>(), // Now gets the re-registered one
      modelSelector: modelSelector,
      voiceTraits: getIt.isRegistered<VoiceTraits>() ? getIt<VoiceTraits>() : null,
      contextCapacity: getIt.isRegistered<ContextCapacity>() ? getIt<ContextCapacity>() : null,
      invocationRepo: getIt<InvocationRepository<Invocation>>(),
      eventBus: getIt<EventBus>(),
    );
    getIt.registerSingleton<Coordinator>(coordinator);
    coordinator.initialize();
    print('✅ Coordinator registered and initialized');
  }
}
