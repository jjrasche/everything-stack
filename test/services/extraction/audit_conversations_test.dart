/// Audit imported conversations in ObjectBox.
///
/// Run: flutter test test/services/extraction/audit_conversations_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/objectbox.g.dart';
import 'package:everything_stack_template/persistence/objectbox/wrappers/invocation_ob.dart';

void main() {
  test('audit conversation data', () async {
    final storePath = await _findStore();
    print('Opening store at: $storePath');
    final store = await openStore(directory: storePath);

    final grouped = _groupByConversation(store);
    final turnCounts = <int>[];
    final tokenCounts = <int>[];
    final summaries = <(String name, int turns, int tokens)>[];

    for (final entry in grouped.entries) {
      final turns = entry.value;
      int totalChars = 0;
      for (final turn in turns) {
        totalChars += _extractCharCount(turn);
      }
      final estimatedTokens = (totalChars / 4).ceil();
      turnCounts.add(turns.length);
      tokenCounts.add(estimatedTokens);
      summaries.add((_extractName(turns.first), turns.length, estimatedTokens));
    }

    turnCounts.sort();
    tokenCounts.sort();
    summaries.sort((a, b) => b.$3.compareTo(a.$3));

    print('\n=== TURN DISTRIBUTION ===');
    _printPercentiles(turnCounts);

    print('\n=== ESTIMATED TOKENS (chars/4) ===');
    _printPercentiles(tokenCounts);

    const jinaLimit = 8192;
    final fitsWhole = tokenCounts.where((t) => t <= jinaLimit).length;
    final totalTokens = tokenCounts.fold<int>(0, (a, b) => a + b);
    print('\n=== JINA EMBEDDING FIT (8192 token limit) ===');
    print('  Whole conversations that fit: $fitsWhole / ${tokenCounts.length}');
    print('  Total tokens: $totalTokens');
    print('  Free tier (10M): ${totalTokens <= 10000000 ? "FITS" : "EXCEEDS by ${totalTokens - 10000000}"}');

    print('\n=== 10 LARGEST ===');
    for (var i = 0; i < 10 && i < summaries.length; i++) {
      final s = summaries[i];
      final name = s.$1.length > 55 ? '${s.$1.substring(0, 55)}...' : s.$1;
      print('  ${s.$2.toString().padLeft(4)} turns  ${s.$3.toString().padLeft(7)} tok  $name');
    }

    final singleTurn = turnCounts.where((t) => t == 1).length;
    print('\n=== NOISE ===');
    print('  1-turn: $singleTurn');
    print('  2-turn: ${turnCounts.where((t) => t == 2).length}');

    store.close();
    expect(grouped.length, greaterThan(0));
  });
}

Map<String, List<InvocationOB>> _groupByConversation(Store store) {
  final box = store.box<InvocationOB>();
  final query = box.query(
    InvocationOB_.implementer.equals('claude_import'),
  ).build();
  final allInvocations = query.find();
  query.close();
  print('Total imported turns: ${allInvocations.length}');

  final grouped = <String, List<InvocationOB>>{};
  for (final inv in allInvocations) {
    final metadata = inv.metadataJson != null
        ? jsonDecode(inv.metadataJson!) as Map<String, dynamic>
        : <String, dynamic>{};
    final convUuid = metadata['sourceConversationUuid'] as String?;
    if (convUuid != null) {
      grouped.putIfAbsent(convUuid, () => []).add(inv);
    }
  }
  print('Total conversations: ${grouped.length}');
  return grouped;
}

int _extractCharCount(InvocationOB turn) {
  final input = turn.inputJson != null
      ? jsonDecode(turn.inputJson!) as Map<String, dynamic>
      : <String, dynamic>{};
  final output = turn.outputJson != null
      ? jsonDecode(turn.outputJson!) as Map<String, dynamic>
      : <String, dynamic>{};
  return (input['prompt']?.toString() ?? '').length +
      (output['response']?.toString() ?? '').length;
}

String _extractName(InvocationOB firstTurn) {
  final metadata = firstTurn.metadataJson != null
      ? jsonDecode(firstTurn.metadataJson!) as Map<String, dynamic>
      : <String, dynamic>{};
  return metadata['sourceConversationName'] as String? ?? 'Unnamed';
}

void _printPercentiles(List<int> sorted) {
  int p(int pct) => sorted[((pct / 100) * (sorted.length - 1)).round()];
  print('  Min: ${sorted.first}  p25: ${p(25)}  Median: ${p(50)}  p75: ${p(75)}  p90: ${p(90)}  Max: ${sorted.last}');
}

Future<String> _findStore() async {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ?? '';
  for (final path in ['$home/Documents/objectbox', 'objectbox']) {
    final dataFile = File('$path/data.mdb');
    if (await dataFile.exists() && await dataFile.length() > 100 * 1024) {
      return path;
    }
  }
  return 'objectbox';
}
