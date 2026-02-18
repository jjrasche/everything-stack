/// Query imported Claude conversations from ObjectBox (read-only access)
///
/// Usage:
///   dart run scripts/query_imported_conversations.dart [--limit=10] [--export=uuid1,uuid2]
///
/// Outputs:
///   - List of conversations with metadata and scores
///   - If --export specified: creates golden test data files

import 'dart:io';
import 'dart:convert';
import 'package:objectbox/objectbox.dart';
import '../lib/objectbox.g.dart';
import '../lib/persistence/objectbox/wrappers/invocation_ob.dart';

void main(List<String> args) async {
  print('📥 Querying imported Claude conversations from ObjectBox...\n');

  // Parse args
  final limit = _parseArg(args, 'limit', '10');
  final exportUuids = _parseArg(args, 'export', '').split(',').where((s) => s.isNotEmpty).toList();

  // Open ObjectBox store (read-only)
  final store = await openStore(directory: 'objectbox');
  final box = store.box<InvocationOB>();

  try {
    // Query all claude_import invocations
    final query = box.query(InvocationOB_.implementer.equals('claude_import')).build();
    final allInvocations = query.find();
    query.close();

    print('📊 Found ${allInvocations.length} imported turns');

    // Group by conversation UUID
    final Map<String, List<InvocationOB>> byConversation = {};
    for (final inv in allInvocations) {
      final metadata = inv.metadataJson != null ? jsonDecode(inv.metadataJson!) : {};
      final convUuid = metadata['sourceConversationUuid'] as String?;
      if (convUuid != null) {
        byConversation.putIfAbsent(convUuid, () => []).add(inv);
      }
    }

    print('📂 Grouped into ${byConversation.length} conversations\n');

    // Score and rank conversations
    final scored = byConversation.entries.map((entry) {
      final turns = entry.value..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      final turnCount = turns.length;
      int totalChars = 0;
      int technicalWords = 0;

      for (final turn in turns) {
        final input = turn.inputJson != null ? jsonDecode(turn.inputJson!) : {};
        final output = turn.outputJson != null ? jsonDecode(turn.outputJson!) : {};

        final prompt = input['prompt']?.toString() ?? '';
        final response = output['response']?.toString() ?? '';
        totalChars += prompt.length + response.length;

        // Count technical indicators
        final text = '$prompt $response'.toLowerCase();
        if (text.contains(RegExp(r'\b(function|class|api|database|service|component|implement|algorithm|pattern|architecture|repository|entity|query|index|semantic|embedding)\b'))) {
          technicalWords++;
        }
      }

      final avgCharsPerTurn = totalChars / turnCount;
      final estimatedTokens = (totalChars / 4).round();

      // Scoring:
      // - Multi-turn: 3+ turns (30pts), 5+ turns (+20pts)
      // - Length: 200-1000 chars/turn (30pts)
      // - Technical density: up to 20pts
      double score = 0;
      if (turnCount >= 3) score += 30;
      if (turnCount >= 5) score += 20;
      if (avgCharsPerTurn >= 200 && avgCharsPerTurn <= 1000) score += 30;
      score += (technicalWords / turnCount) * 20;

      final firstInput = turns.first.inputJson != null ? jsonDecode(turns.first.inputJson!) : {};
      final firstPrompt = firstInput['prompt']?.toString() ?? '';
      final metadata = turns.first.metadataJson != null ? jsonDecode(turns.first.metadataJson!) : {};

      return {
        'uuid': entry.key,
        'name': metadata['sourceConversationName'] ?? 'Unnamed',
        'turnCount': turnCount,
        'estimatedTokens': estimatedTokens,
        'avgCharsPerTurn': avgCharsPerTurn.round(),
        'technicalDensity': ((technicalWords / turnCount) * 100).round(),
        'score': score.round(),
        'firstPrompt': _truncate(firstPrompt, 100),
        'firstTurnDate': turns.first.createdAt.toIso8601String(),
      };
    }).toList()
      ..sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    // Display top candidates
    final displayLimit = int.tryParse(limit) ?? 10;
    print('🏆 Top $displayLimit conversation candidates for testing:\n');
    print('${'#'.padRight(3)} ${'Score'.padRight(5)} ${'Turns'.padRight(5)} ${'Tokens'.padRight(7)} ${'Tech%'.padRight(5)} ${'Name'.padRight(40)} ${'First Prompt'}');
    print('─' * 120);

    for (var i = 0; i < scored.length && i < displayLimit; i++) {
      final conv = scored[i];
      final rank = (i + 1).toString().padRight(3);
      final score = (conv['score'] as int).toString().padRight(5);
      final turns = (conv['turnCount'] as int).toString().padRight(5);
      final tokens = (conv['estimatedTokens'] as int).toString().padRight(7);
      final tech = '${conv['technicalDensity']}%'.padRight(5);
      final name = _truncate(conv['name'] as String, 38).padRight(40);
      final prompt = conv['firstPrompt'] as String;

      print('$rank $score $turns $tokens $tech $name $prompt');
    }

    // Export if requested
    if (exportUuids.isNotEmpty) {
      print('\n📤 Exporting conversations to lib/training/extraction/golden/...');
      final exportDir = Directory('lib/training/extraction/golden');
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }

      for (final uuid in exportUuids) {
        final turns = byConversation[uuid];
        if (turns == null) {
          print('   ⚠️ Conversation not found: $uuid');
          continue;
        }

        final sorted = turns..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final metadata = sorted.first.metadataJson != null ? jsonDecode(sorted.first.metadataJson!) : {};

        final testData = {
          'id': 'conv_${uuid.substring(0, 8)}',
          'description': 'TODO: Add description of what makes this conversation interesting for extraction testing',
          'conversation': {
            'uuid': uuid,
            'name': metadata['sourceConversationName'] ?? 'Unnamed',
            'turn_count': sorted.length,
            'first_turn_date': sorted.first.createdAt.toIso8601String(),
            'last_turn_date': sorted.last.createdAt.toIso8601String(),
            'turns': sorted.asMap().entries.map((entry) {
              final idx = entry.key;
              final inv = entry.value;
              final input = inv.inputJson != null ? jsonDecode(inv.inputJson!) : {};
              final output = inv.outputJson != null ? jsonDecode(inv.outputJson!) : {};

              return {
                'turn_index': idx,
                'uuid': inv.uuid,
                'created_at': inv.createdAt.toIso8601String(),
                'prompt': input['prompt'],
                'response': output['response'],
              };
            }).toList(),
          },
          'expected_insights': [
            {
              'content': 'TODO: [Fact]. Because [reason].',
              'source_turns': [0],
              'notes': 'Add expected insights to extract from this conversation',
            }
          ],
        };

        final filename = 'conv_${uuid.substring(0, 8)}.json';
        final file = File('lib/training/extraction/golden/$filename');
        await file.writeAsString(JsonEncoder.withIndent('  ').convert(testData));
        print('   ✅ Exported: $filename');
      }
    }

    print('\n✅ Query complete');
  } finally {
    store.close();
  }
}

String _parseArg(List<String> args, String key, String defaultValue) {
  for (final arg in args) {
    if (arg.startsWith('--$key=')) {
      return arg.substring('--$key='.length);
    }
  }
  return defaultValue;
}

String _truncate(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength)}...';
}
