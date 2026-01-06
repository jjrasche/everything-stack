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
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/chunking_service.dart';
import 'package:everything_stack_template/services/semantic_search/semantic_search_service.dart';
import 'package:everything_stack_template/main.dart';
import 'package:get_it/get_it.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Invocation Semantic Search - Smoke Test (Real Embeddings)', () {
    setUpAll(() async {
      // No setup needed - app will initialize on pumpWidget()
    });

    testWidgets('Full smoke test: Index and search invocations',
        (WidgetTester tester) async {
      // Build app - this runs bootstrap and initializes GetIt
      debugPrint('🏗️ Building MyApp...');
      await tester.pumpWidget(const MyApp());

      debugPrint('⏳ Waiting for bootstrap and initialization...');
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // NOW GetIt services are available
      final chunkingService = GetIt.instance<ChunkingService>();
      final searchService = GetIt.instance<SemanticSearchService>();
      final embeddingService = EmbeddingService.instance;

      debugPrint('✅ Services initialized');

      final capturedEmbeddings = <String, List<double>>{};

      // Helper to create invocation with text content
      Invocation _createInvocation({
        required String componentType,
        required String text,
      }) {
        return Invocation(
          eventId: 'test-event-${DateTime.now().millisecondsSinceEpoch}',
          turnId: 'test-turn',
          componentType: componentType,
          success: true,
          confidence: 0.95,
          output: {
            if (componentType == 'stt') 'transcription': text
            else 'response': text,
          },
          metadata: {},
        );
      }

      /// Capture embedding from semantic search
      Future<void> _captureEmbedding(String text) async {
        try {
          final embedding = await embeddingService.generate(text);
          capturedEmbeddings[text] = embedding;
        } catch (e) {
          // Silently skip if capture fails
        }
      }

      // Test 1: Index short STT invocation
      debugPrint('\n📝 Test 1: Index short STT invocation');
      final invocation1 = _createInvocation(
        componentType: 'stt',
        text: 'What time is the meeting tomorrow',
      );

      final chunks1 = await chunkingService.indexEntity(invocation1);

      expect(chunks1, isNotEmpty);
      expect(chunks1.length, greaterThan(0));

      for (final chunk in chunks1) {
        await _captureEmbedding(chunk.text);
      }
      debugPrint('✅ Test 1 passed: ${chunks1.length} chunks created');

      // Test 2: Index medium LLM invocation
      debugPrint('\n📝 Test 2: Index medium LLM invocation');
      final invocation2 = _createInvocation(
        componentType: 'llm',
        text:
            'The meeting is scheduled for 2 PM tomorrow in the main conference room. '
            'Please prepare the presentation slides and bring the Q3 reports. '
            'We will discuss budget allocation and timeline for the new project.',
      );

      final chunks2 = await chunkingService.indexEntity(invocation2);

      expect(chunks2, isNotEmpty);
      expect(chunks2.length, greaterThanOrEqualTo(2));

      for (final chunk in chunks2) {
        await _captureEmbedding(chunk.text);
      }
      debugPrint('✅ Test 2 passed: ${chunks2.length} chunks created');

      // Test 3: Index long conversation invocation
      debugPrint('\n📝 Test 3: Index long conversation invocation');
      final invocation3 = _createInvocation(
        componentType: 'llm',
        text:
            'Based on the quarterly review, we need to reallocate resources. '
            'The marketing team is performing well but engineering is understaffed. '
            'I recommend moving two people from operations to the backend team. '
            'The DevOps infrastructure needs improvement for scalability. '
            'We should also invest in monitoring tools and automated testing. '
            'Timeline: target completion by end of Q1. Budget estimate: \$150K. '
            'This will improve deployment frequency and reduce incident response time.',
      );

      final chunks3 = await chunkingService.indexEntity(invocation3);

      expect(chunks3, isNotEmpty);
      expect(chunks3.length, greaterThanOrEqualTo(3));

      for (final chunk in chunks3) {
        await _captureEmbedding(chunk.text);
      }
      debugPrint('✅ Test 3 passed: ${chunks3.length} chunks created');

      // Test 4: Search returns semantic results
      debugPrint('\n📝 Test 4: Search returns semantic results');
      final results = await searchService.search(
        'meeting schedule conference room',
        limit: 5,
      );

      expect(results, isNotEmpty);
      expect(results.length, greaterThan(0));

      if (results.length > 1) {
        expect(
          results.first.similarity,
          greaterThanOrEqualTo(results.last.similarity),
        );
      }

      await _captureEmbedding('meeting schedule conference room');
      debugPrint('✅ Test 4 passed: ${results.length} results found');

      // Test 5: Search with entity type filter
      debugPrint('\n📝 Test 5: Search with entity type filter');
      final results2 = await searchService.search(
        'deployment DevOps infrastructure',
        entityTypes: ['Invocation'],
        limit: 5,
      );

      expect(results2, isNotEmpty);
      for (final result in results2) {
        expect(result.chunk, isNotNull);
      }

      await _captureEmbedding('deployment DevOps infrastructure');
      debugPrint('✅ Test 5 passed: ${results2.length} results found');

      // Test 6: Index multiple invocations and search across them
      debugPrint('\n📝 Test 6: Index multiple and search across');
      final inv1 = _createInvocation(
        componentType: 'stt',
        text: 'Schedule a meeting with the design team',
      );
      final inv2 = _createInvocation(
        componentType: 'llm',
        text:
            'The design team will present mockups for the new dashboard. '
            'We need feedback on color scheme and layout.',
      );

      await chunkingService.indexEntity(inv1);
      await chunkingService.indexEntity(inv2);

      final results3 = await searchService.search(
        'design team dashboard mockups',
        limit: 10,
      );

      expect(results3, isNotEmpty);

      await _captureEmbedding('design team dashboard mockups');
      debugPrint('✅ Test 6 passed: ${results3.length} results found');

      // Save captured embeddings for CI tests
      if (capturedEmbeddings.isNotEmpty) {
        final json = jsonEncode(capturedEmbeddings);
        debugPrint('💾 Captured ${capturedEmbeddings.length} embeddings');

        // Write fixture file to disk for CI tests
        try {
          final fixtureDir = Directory('test/fixtures');
          if (!fixtureDir.existsSync()) {
            fixtureDir.createSync(recursive: true);
            debugPrint('📁 Created test/fixtures directory');
          }

          final fixtureFile = File('test/fixtures/invocation_embeddings.json');
          fixtureFile.writeAsStringSync(json);

          debugPrint('✅ Fixture saved to: test/fixtures/invocation_embeddings.json');
          debugPrint('📊 Embedding vectors: ${capturedEmbeddings.length}');
          debugPrint('📐 Vector dimensions: 384 (Jina default)');
        } catch (e) {
          debugPrint('❌ Failed to save fixture: $e');
        }
      }

      debugPrint('\n✅ All smoke tests passed!');
    });
  });
}
