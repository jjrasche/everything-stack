/// Audit imported conversations in ObjectBox.
///
/// Run: dart run scripts/audit_conversations.dart

import 'dart:convert';
import 'dart:io';

import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/objectbox.g.dart';
import 'package:everything_stack_template/persistence/objectbox/wrappers/invocation_ob.dart';

void main() async {
  final storePath = await findStore();
  print('Opening store at: $storePath');
  final store = await openStore(directory: storePath);

  final conversations = groupByConversation(store);
  final stats = computeStats(conversations);

  printDistribution('TURN DISTRIBUTION', stats.turnCounts);
  printDistribution('ESTIMATED TOKENS (chars/4)', stats.tokenCounts);
  printEmbeddingFit(stats);
  printLargestConversations(stats.summaries, count: 10);
  printNoiseCount(stats.turnCounts);

  store.close();
}

// ============ Data Types ============

class ConversationStats {
  final List<int> turnCounts;
  final List<int> tokenCounts;
  final List<ConversationSummary> summaries;
  final int totalTurns;

  ConversationStats({
    required this.turnCounts,
    required this.tokenCounts,
    required this.summaries,
    required this.totalTurns,
  });
}

class ConversationSummary implements Comparable<ConversationSummary> {
  final String name;
  final int turnCount;
  final int estimatedTokens;

  ConversationSummary({
    required this.name,
    required this.turnCount,
    required this.estimatedTokens,
  });

  @override
  int compareTo(ConversationSummary other) =>
      other.estimatedTokens.compareTo(estimatedTokens);
}

// ============ Query ============

Map<String, List<InvocationOB>> groupByConversation(Store store) {
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

  print('Total conversations: ${grouped.length}\n');
  return grouped;
}

// ============ Compute ============

ConversationStats computeStats(Map<String, List<InvocationOB>> conversations) {
  final turnCounts = <int>[];
  final tokenCounts = <int>[];
  final summaries = <ConversationSummary>[];
  int totalTurns = 0;

  for (final entry in conversations.entries) {
    final turns = entry.value;
    totalTurns += turns.length;

    int totalChars = 0;
    for (final turn in turns) {
      totalChars += extractTurnCharCount(turn);
    }

    final estimatedTokens = (totalChars / 4).ceil();
    turnCounts.add(turns.length);
    tokenCounts.add(estimatedTokens);

    summaries.add(ConversationSummary(
      name: extractConversationName(turns.first),
      turnCount: turns.length,
      estimatedTokens: estimatedTokens,
    ));
  }

  turnCounts.sort();
  tokenCounts.sort();
  summaries.sort();

  return ConversationStats(
    turnCounts: turnCounts,
    tokenCounts: tokenCounts,
    summaries: summaries,
    totalTurns: totalTurns,
  );
}

int extractTurnCharCount(InvocationOB turn) {
  final input = turn.inputJson != null
      ? jsonDecode(turn.inputJson!) as Map<String, dynamic>
      : <String, dynamic>{};
  final output = turn.outputJson != null
      ? jsonDecode(turn.outputJson!) as Map<String, dynamic>
      : <String, dynamic>{};
  final prompt = input['prompt']?.toString() ?? '';
  final response = output['response']?.toString() ?? '';
  return prompt.length + response.length;
}

String extractConversationName(InvocationOB firstTurn) {
  final metadata = firstTurn.metadataJson != null
      ? jsonDecode(firstTurn.metadataJson!) as Map<String, dynamic>
      : <String, dynamic>{};
  return metadata['sourceConversationName'] as String? ?? 'Unnamed';
}

// ============ Print ============

void printDistribution(String label, List<int> sorted) {
  print('=== $label ===');
  print('  Min: ${sorted.first}');
  print('  p25: ${percentile(sorted, 25)}');
  print('  Median: ${percentile(sorted, 50)}');
  print('  p75: ${percentile(sorted, 75)}');
  print('  p90: ${percentile(sorted, 90)}');
  print('  Max: ${sorted.last}');
  print('');
}

void printEmbeddingFit(ConversationStats stats) {
  const jinaLimit = 8192;
  final fitsCount = stats.tokenCounts.where((t) => t <= jinaLimit).length;
  final totalConversations = stats.tokenCounts.length;
  final totalTokens = stats.tokenCounts.fold<int>(0, (a, b) => a + b);

  print('=== JINA EMBEDDING FIT (8192 token limit) ===');
  print('  Whole conversations that fit: $fitsCount / $totalConversations '
      '(${(fitsCount / totalConversations * 100).toStringAsFixed(1)}%)');
  print('  Total tokens all conversations: $totalTokens');
  print('  Jina free tier: 10,000,000 tokens');
  print('  ${totalTokens <= 10000000 ? "FITS in free tier" : "EXCEEDS free tier by ${totalTokens - 10000000}"}');
  print('');
}

void printLargestConversations(List<ConversationSummary> summaries, {int count = 10}) {
  print('=== ${count} LARGEST CONVERSATIONS ===');
  for (var i = 0; i < count && i < summaries.length; i++) {
    final c = summaries[i];
    final truncatedName = c.name.length > 60 ? c.name.substring(0, 60) : c.name;
    print('  ${c.turnCount.toString().padLeft(4)} turns, '
        '${c.estimatedTokens.toString().padLeft(7)} tokens: $truncatedName');
  }
  print('');
}

void printNoiseCount(List<int> turnCounts) {
  final singleTurn = turnCounts.where((t) => t == 1).length;
  final twoTurn = turnCounts.where((t) => t == 2).length;
  print('=== POTENTIAL NOISE ===');
  print('  1-turn conversations: $singleTurn');
  print('  2-turn conversations: $twoTurn');
}

int percentile(List<int> sorted, int p) {
  final index = ((p / 100) * (sorted.length - 1)).round();
  return sorted[index];
}

Future<String> findStore() async {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ?? '';
  final candidates = ['$home/Documents/objectbox', 'objectbox'];
  for (final path in candidates) {
    final dataFile = File('$path/data.mdb');
    if (await dataFile.exists() && await dataFile.length() > 100 * 1024) {
      return path;
    }
  }
  return 'objectbox';
}
