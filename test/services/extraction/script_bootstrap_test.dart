/// Tests for scripts/script_bootstrap.dart service wiring.
///
/// Requires .env with valid GROQ_API_KEY. Skips gracefully if missing.
/// Run: flutter test test/services/extraction/script_bootstrap_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:everything_stack_template/services/extraction/atomic_insight_extractor.dart';
import 'package:everything_stack_template/services/prompt/prompt_registry.dart';

// Cannot import scripts/ via package:, so we test the wiring
// by constructing the same pipeline inline. The script_bootstrap.dart
// uses identical construction patterns.
import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/objectbox.g.dart';

import 'package:everything_stack_template/persistence/objectbox/invocation_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/adaptation_state_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/feedback_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/atomic_insight_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/prompt_version_objectbox_adapter.dart';

import 'package:everything_stack_template/services/inference_service.dart';
import 'package:everything_stack_template/services/implementations/groq_implementer.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/training/extraction/extraction_evaluator.dart';
import 'package:everything_stack_template/training/extraction/extraction_improvement_loop.dart';
import 'package:everything_stack_template/services/prompt/prompt_mutator.dart';
import 'package:everything_stack_template/services/prompt/prompt_validator.dart';

import 'package:everything_stack_template/domain/atomic_insight_repository.dart';
import 'package:everything_stack_template/domain/prompt_version_repository.dart';

bool _hasGroqKey() {
  try {
    final key = dotenv.env['GROQ_API_KEY'];
    return key != null && key.isNotEmpty;
  } catch (_) {
    return false;
  }
}

void main() {
  late Store store;
  late Directory tempDir;

  setUpAll(() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // .env not found; tests will skip
    }
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('bootstrap_test_');
    store = await openStore(directory: tempDir.path);
  });

  tearDown(() {
    store.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ExtractionPipeline wiring', () {
    test('all services construct without error', () {
      if (!_hasGroqKey()) {
        markTestSkipped('GROQ_API_KEY not found in .env');
        return;
      }

      final groqKey = dotenv.env['GROQ_API_KEY']!;

      final inferenceService = InferenceService(
        implementers: {'groq': GroqImplementer(apiKey: groqKey)},
        defaultImplementer: 'groq',
        invocationRepo: InvocationObjectBoxAdapter(store),
        adaptationStateRepo: AdaptationStateObjectBoxAdapter(store),
        feedbackRepo: FeedbackObjectBoxAdapter(store),
      );

      final insightRepo = AtomicInsightRepository(
        adapter: AtomicInsightObjectBoxAdapter(store),
        embeddingService: NullEmbeddingService(),
      );

      final promptVersionRepo = PromptVersionRepository(
        adapter: PromptVersionObjectBoxAdapter(store),
        embeddingService: NullEmbeddingService(),
      );

      final promptRegistry = PromptRegistry(
        repo: promptVersionRepo,
        componentType: 'extraction_prompt',
        hardcodedDefault: AtomicInsightExtractor.defaultSystemPrompt,
      );

      final extractor = AtomicInsightExtractor(
        insightRepo: insightRepo,
        inferenceService: inferenceService,
        promptRegistry: promptRegistry,
      );

      final evaluator = ExtractionEvaluator(
        inferenceService: inferenceService,
      );

      final mutator = PromptMutator(inferenceService: inferenceService);
      final validator = PromptValidator();

      final loop = ExtractionImprovementLoop(
        extractor: extractor,
        evaluator: evaluator,
        promptRegistry: promptRegistry,
        mutator: mutator,
        validator: validator,
      );

      expect(inferenceService, isNotNull);
      expect(insightRepo, isNotNull);
      expect(promptVersionRepo, isNotNull);
      expect(promptRegistry, isNotNull);
      expect(extractor, isNotNull);
      expect(evaluator, isNotNull);
      expect(loop, isNotNull);
    });

    test('PromptRegistry returns hardcoded default when no versions exist',
        () async {
      if (!_hasGroqKey()) {
        markTestSkipped('GROQ_API_KEY not found in .env');
        return;
      }

      final promptVersionRepo = PromptVersionRepository(
        adapter: PromptVersionObjectBoxAdapter(store),
        embeddingService: NullEmbeddingService(),
      );

      final registry = PromptRegistry(
        repo: promptVersionRepo,
        componentType: 'extraction_prompt',
        hardcodedDefault: AtomicInsightExtractor.defaultSystemPrompt,
      );

      final prompt = await registry.getActivePrompt();

      expect(prompt, equals(AtomicInsightExtractor.defaultSystemPrompt));
      expect(registry.activeVersion, equals(0));
    });
  });
}
