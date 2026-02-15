/// # Semantic Search Test
///
/// Interactive search through the semantic index.
/// Run with: flutter test integration_test/search_test.dart -d windows

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:get_it/get_it.dart';

import 'package:everything_stack_template/bootstrap.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/services/semantic_search/semantic_search_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Semantic Search', () {
    late SemanticSearchService searchService;

    setUpAll(() async {
      await initializeEverythingStack();
      await setupServiceLocator();
      searchService = GetIt.instance<SemanticSearchService>();
    });

    testWidgets('search: coaching business name', (tester) async {
      await _runSearch(searchService, 'coaching business name');
    });

    testWidgets('search: air fryer energy efficiency', (tester) async {
      await _runSearch(searchService, 'air fryer energy efficiency');
    });

    testWidgets('search: flourish thrive synonyms', (tester) async {
      await _runSearch(searchService, 'flourish thrive synonyms');
    });

    testWidgets('search: muscle control conscious', (tester) async {
      await _runSearch(searchService, 'muscle control conscious');
    });
  });
}

Future<void> _runSearch(SemanticSearchService searchService, String query) async {
  print('\n' + '═' * 60);
  print('🔎 SEARCH: "$query"');
  print('═' * 60);

  final results = await searchService.search(
    query,
    limit: 5,
  );

  if (results.isEmpty) {
    print('❌ No results found\n');
    return;
  }

  print('✅ Found ${results.length} results:\n');

  for (int i = 0; i < results.length; i++) {
    final result = results[i];
    print('─' * 50);
    print('[$i] Similarity: ${(result.similarity * 100).toStringAsFixed(1)}%');

    if (result.sourceEntity is Invocation) {
      final inv = result.sourceEntity as Invocation;
      final prompt = inv.input?['prompt'] as String? ?? '';
      final response = inv.output?['response'] as String? ?? '';
      final convName = inv.metadata?['sourceConversationName'] as String?;

      if (convName != null) {
        print('    📂 Conversation: $convName');
      }
      print('    📅 Date: ${inv.createdAt}');
      print('    🔧 Source: ${inv.implementer}');
      print('');
      print('    👤 User: ${_truncate(prompt, 80)}');
      print('    🤖 Assistant: ${_truncate(response, 120)}');
    } else {
      print('    📄 Chunk: ${_truncate(result.chunk.text, 150)}');
    }
    print('');
  }

  print('═' * 60 + '\n');
}

String _truncate(String text, int maxLen) {
  final cleaned = text.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.length <= maxLen) return cleaned;
  return '${cleaned.substring(0, maxLen)}...';
}
