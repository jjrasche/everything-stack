/// # Invocation Semantic Search - CI Test (Replayed Embeddings)
///
/// Uses mocked embeddings from fixture for deterministic CI runs.
/// No external API dependencies - fast and reliable.
///
/// Test pattern: register mocks → call shared test logic
/// This ensures smoke test (real) and CI test (mocked) are IDENTICAL
/// except for service configuration (which happens in setUpAll).

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/main.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import '../test/support/replay_embedding_service.dart';
import '../test/support/invocation_semantic_test_shared.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Invocation Semantic Search - CI Test (Replayed Embeddings)', () {
    setUpAll(() async {
      // Register mock embedding service BEFORE app builds
      // This ensures bootstrap uses mocks instead of real Jina API
      print('📝 Using MOCKED embeddings (replayed from fixture)');

      // Load captured embeddings from fixture
      final fixtureFile = File('test/fixtures/invocation_embeddings.json');
      final capturedEmbeddings = <String, List<double>>{};

      if (fixtureFile.existsSync()) {
        try {
          final json = jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
          for (final entry in json.entries) {
            final embedding = (entry.value as List<dynamic>).cast<double>();
            capturedEmbeddings[entry.key] = embedding;
          }
          print('✅ Loaded ${capturedEmbeddings.length} embeddings from fixture');
        } catch (e) {
          print('⚠️ Failed to load fixture: $e');
        }
      } else {
        print('⚠️ Fixture not found at: test/fixtures/invocation_embeddings.json');
        print('   Run smoke test first to generate fixture');
      }

      GetIt.instance.registerSingleton<EmbeddingService>(
        ReplayEmbeddingService(capturedEmbeddings: capturedEmbeddings),
      );
      print('✅ Mock embedding service registered');
    });

    testWidgets('E2E: Chunking, indexing, and search with mocked embeddings',
        (WidgetTester tester) async {
      // Build app - this runs bootstrap and initializes GetIt with mocked embedding service
      print('🏗️ Building MyApp with mocked embeddings...');
      await tester.pumpWidget(const MyApp());

      print('⏳ Waiting for bootstrap and initialization...');
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Shared test logic - identical to smoke test, only service config differs
      await runInvocationSemanticTest();
    });
  });
}
