/// Run normalize stage on all 33 golden conversations.
/// No LLM calls — normalize is rules-based (punctuation detection + sentence splitting).
///
/// Usage:
///   flutter test test/scripts/run_normalize_segment_test.dart
@TestOn('windows')
library;

import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/memory/stages/normalize_stage.dart';

void main() {
  final turnsDir = 'lib/training/extraction/golden/turns';
  final outputDir = 'lib/training/extraction/golden/normalize_output';

  late NormalizeStage normalizeStage;

  setUpAll(() {
    normalizeStage = NormalizeStage();
  });

  test('normalize all golden conversations', () async {
    await Directory(outputDir).create(recursive: true);
    final conversations = await _loadConversations(turnsDir);

    // ignore: avoid_print
    print('Processing ${conversations.length} conversations...\n');

    var totalTextBlocks = 0;
    var punctuationNeededCount = 0;
    var splitCount = 0;

    for (final conv in conversations) {
      final turnOutputs = <Map<String, dynamic>>[];

      for (var i = 0; i < conv.turns.length; i++) {
        final turn = conv.turns[i];

        for (final entry in [
          {'speaker': 'user', 'text': turn['prompt'] as String? ?? ''},
          {'speaker': 'assistant', 'text': turn['response'] as String? ?? ''},
        ]) {
          final text = entry['text']!;
          if (text.isEmpty) continue;

          totalTextBlocks++;
          final result = await normalizeStage.process(text);

          if (result.trace.punctuationNeeded) punctuationNeededCount++;
          splitCount += result.trace.splitCount;

          turnOutputs.add({
            'turnIndex': i,
            'speaker': entry['speaker'],
            'normalize': result.trace.toJson(),
          });
        }
      }

      final output = {
        'conversationUuid': conv.uuid,
        'conversationName': conv.name,
        'turnCount': conv.turns.length,
        'stage': 'normalize',
        'turns': turnOutputs,
      };

      final outputFile = File('$outputDir/${conv.uuid}.json');
      await outputFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(output),
      );

      final neededCount = turnOutputs
          .where((t) => (t['normalize'] as Map<String, dynamic>)['punctuationNeeded'] == true)
          .length;

      // ignore: avoid_print
      print('  ${conv.name}: ${turnOutputs.length} blocks, $neededCount need punctuation');
    }

    // ignore: avoid_print
    print('\n--- Summary ---');
    // ignore: avoid_print
    print('Conversations: ${conversations.length}');
    // ignore: avoid_print
    print('Total text blocks: $totalTextBlocks');
    // ignore: avoid_print
    print('Punctuation needed: $punctuationNeededCount / $totalTextBlocks');
    // ignore: avoid_print
    print('Overlong splits: $splitCount');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

class _Conversation {
  final String uuid;
  final String name;
  final List<Map<String, dynamic>> turns;

  _Conversation({required this.uuid, required this.name, required this.turns});
}

Future<List<_Conversation>> _loadConversations(String dir) async {
  final directory = Directory(dir);
  if (!await directory.exists()) throw Exception('Directory not found: $dir');

  final jsonFiles = await directory
      .list()
      .where((entity) => entity.path.endsWith('.json'))
      .toList();

  final conversations = <_Conversation>[];

  for (final file in jsonFiles) {
    final content = await File(file.path).readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;
    final rawTurns = data['turns'] as List<dynamic>;

    final turns = rawTurns.map((t) {
      final turn = t as Map<String, dynamic>;
      return <String, dynamic>{
        'prompt': turn['prompt'] ?? '',
        'response': turn['response'] ?? '',
      };
    }).toList();

    conversations.add(_Conversation(
      uuid: data['convUuid'] as String,
      name: data['convName'] as String? ?? 'Unnamed',
      turns: turns,
    ));
  }

  conversations.sort((a, b) => a.uuid.compareTo(b.uuid));
  return conversations;
}
