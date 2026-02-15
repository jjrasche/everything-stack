#!/usr/bin/env dart
/// # Semantic Search CLI
///
/// Search the semantic index from command line.
///
/// Usage:
///   dart run bin/search.dart "your query here"
///   dart run bin/search.dart "air fryer energy" --limit 10
///
/// Examples:
///   dart run bin/search.dart "coaching business name"
///   dart run bin/search.dart "microwave vs air fryer"
///   dart run bin/search.dart "flourish thrive synonyms"

import 'dart:io';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/bootstrap.dart';
import 'package:everything_stack_template/services/semantic_search/semantic_search_service.dart';
import 'package:everything_stack_template/core/invocation.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run bin/search.dart "your query"');
    print('');
    print('Options:');
    print('  --limit N    Max results (default: 5)');
    print('  --min S      Min similarity 0.0-1.0 (default: 0.3)');
    exit(1);
  }

  // Parse args
  String query = '';
  int limit = 5;
  double minSimilarity = 0.3;

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--limit' && i + 1 < args.length) {
      limit = int.parse(args[++i]);
    } else if (args[i] == '--min' && i + 1 < args.length) {
      minSimilarity = double.parse(args[++i]);
    } else if (!args[i].startsWith('--')) {
      query = args[i];
    }
  }

  if (query.isEmpty) {
    print('Error: No query provided');
    exit(1);
  }

  print('🔍 Initializing...');

  // Bootstrap (minimal - just what we need for search)
  await initializeEverythingStack();

  final searchService = GetIt.instance<SemanticSearchService>();

  print('🔎 Searching: "$query"');
  print('   Limit: $limit, Min similarity: $minSimilarity');
  print('');

  final results = await searchService.search(
    query,
    limit: limit,
    minSimilarity: minSimilarity,
  );

  if (results.isEmpty) {
    print('❌ No results found');
    exit(0);
  }

  print('✅ Found ${results.length} results:\n');

  for (int i = 0; i < results.length; i++) {
    final result = results[i];
    print('─' * 60);
    print('[$i] Similarity: ${(result.similarity * 100).toStringAsFixed(1)}%');

    if (result.entity is Invocation) {
      final inv = result.entity as Invocation;
      final prompt = inv.input?['prompt'] as String? ?? '';
      final response = inv.output?['response'] as String? ?? '';
      final convName = inv.metadata?['sourceConversationName'] as String?;

      if (convName != null) {
        print('    Conversation: $convName');
      }
      print('    Date: ${inv.createdAt}');
      print('    Implementer: ${inv.implementer}');
      print('');
      print('    User: ${_truncate(prompt, 100)}');
      print('');
      print('    Assistant: ${_truncate(response, 200)}');
    } else {
      print('    Chunk: ${_truncate(result.chunk.text, 200)}');
    }
    print('');
  }

  print('─' * 60);
  exit(0);
}

String _truncate(String text, int maxLen) {
  final cleaned = text.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.length <= maxLen) return cleaned;
  return '${cleaned.substring(0, maxLen)}...';
}
