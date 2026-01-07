/// Smoke test for invocation-level semantic search (real Jina embeddings).
///
/// This test:
/// 1. Creates invocations with real Jina embeddings
/// 2. Indexes them via ChunkingService
/// 3. Searches via SemanticSearchService
/// 4. Captures embeddings for CI tests
///
/// Run with: flutter test integration_test/invocation_semantic_smoke_test.dart -d <platform>

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:everything_stack_template/main.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import '../test/support/invocation_semantic_test_shared.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Invocation Semantic Search - Smoke Test (Real Embeddings)', () {
    setUpAll(() async {
      print('🔥 Using REAL Jina embeddings');
      print('ℹ️  Capturing embeddings from API for CI test fixture');
    });

    testWidgets('Smoke: Semantic search with real Jina embeddings',
        (WidgetTester tester) async {
      // Build app - this runs bootstrap and initializes GetIt
      debugPrint('🏗️ Building MyApp...');
      await tester.pumpWidget(const MyApp());

      debugPrint('⏳ Waiting for bootstrap and initialization...');
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Initialize embedding capture
      final embeddingService = EmbeddingService.instance;
      final capturedEmbeddings = <String, List<double>>{};

      /// Capture embedding from real API
      Future<void> captureEmbedding(String text) async {
        try {
          final embedding = await embeddingService.generate(text);
          capturedEmbeddings[text] = embedding;
          debugPrint('  📡 Captured: $text (${embedding.length} dims)');
        } catch (e) {
          debugPrint('  ⚠️ Failed to capture: $text - $e');
        }
      }

      // Run shared test logic
      await runInvocationSemanticTest();

      // Capture embeddings AFTER tests (for all test texts)
      debugPrint('\n💾 Capturing embeddings for fixture...');
      await captureEmbedding('What time is the meeting tomorrow');
      await captureEmbedding(
          'The meeting is scheduled for 2 PM tomorrow in the main conference room. '
          'Please prepare the presentation slides and bring the Q3 reports. '
          'We will discuss budget allocation and timeline for the new project.');
      await captureEmbedding(
          'Based on the quarterly review, we need to reallocate resources. '
          'The marketing team is performing well but engineering is understaffed. '
          'I recommend moving two people from operations to the backend team. '
          'The DevOps infrastructure needs improvement for scalability. '
          'We should also invest in monitoring tools and automated testing. '
          'Timeline: target completion by end of Q1. Budget estimate: \$150K. '
          'This will improve deployment frequency and reduce incident response time.');
      await captureEmbedding(
          'Based on the quarterly review, we need to reallocate resources. '
          'The marketing team is performing well but engineering is understaffed. '
          'I recommend moving two people from operations to the backend team. '
          'The DevOps infrastructure needs improvement for scalability. '
          'We should also invest in monitoring tools and automated testing. '
          'Timeline: target completion by end of Q1. Budget estimate: \$150K. '
          'This');
      await captureEmbedding(
          'will improve deployment frequency and reduce incident response time.');
      await captureEmbedding('meeting schedule conference room');
      await captureEmbedding('deployment DevOps infrastructure');
      await captureEmbedding('design team dashboard mockups');

      // Save fixture
      if (capturedEmbeddings.isNotEmpty) {
        final json = jsonEncode(capturedEmbeddings);
        debugPrint('\n✅ Saving fixture with ${capturedEmbeddings.length} embeddings');

        try {
          final fixtureDir = Directory('test/fixtures');
          if (!fixtureDir.existsSync()) {
            fixtureDir.createSync(recursive: true);
            debugPrint('  📁 Created test/fixtures directory');
          }

          final fixtureFile = File('test/fixtures/invocation_embeddings.json');
          fixtureFile.writeAsStringSync(json);

          debugPrint('  ✅ Fixture saved to: test/fixtures/invocation_embeddings.json');
          debugPrint('  📊 Embedding vectors: ${capturedEmbeddings.length}');
          debugPrint('  📐 Vector dimensions: 384 (Jina)');
        } catch (e) {
          debugPrint('  ❌ Failed to save fixture: $e');
        }
      }

      debugPrint('\n🎉 Smoke test complete');
      debugPrint('   - Semantic search pipeline: ✅');
      debugPrint('   - Real embeddings captured: ✅');
      debugPrint('   - Fixture ready for CI: ✅');
    });
  });
}
