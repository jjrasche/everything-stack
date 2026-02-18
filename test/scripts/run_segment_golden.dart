/// Run normalize + segment on all 33 golden conversations.
///
/// Rules-based stages only — no LLM calls, runs in seconds.
/// Writes per-conversation JSON to golden/segment_output/.
/// Prints corpus-wide summary stats.
///
/// Usage:
///   flutter test test/scripts/run_segment_golden.dart
@TestOn('windows')
library;

import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/memory/stages/normalize_stage.dart';
import 'package:everything_stack_template/services/memory/stages/segment_stage.dart';
import 'package:everything_stack_template/services/memory/encoder_trace.dart';

// ============ Conversation Data ============

class _Conversation {
  final String uuid;
  final String name;
  final List<Map<String, dynamic>> turns;

  _Conversation({required this.uuid, required this.name, required this.turns});
}

// ============ Per-Turn Result ============

class _TurnResult {
  final int turnIndex;
  final String speaker;
  final int inputCharCount;
  final List<Map<String, dynamic>> sentences;
  final int droppedFragments;
  final bool punctuationNeeded;

  _TurnResult({
    required this.turnIndex,
    required this.speaker,
    required this.inputCharCount,
    required this.sentences,
    required this.droppedFragments,
    required this.punctuationNeeded,
  });

  Map<String, dynamic> toJson() => {
        'turnIndex': turnIndex,
        'speaker': speaker,
        'inputCharCount': inputCharCount,
        'sentenceCount': sentences.length,
        'droppedFragments': droppedFragments,
        'punctuationNeeded': punctuationNeeded,
        'sentences': sentences,
      };
}

// ============ Test Entry Point ============

void main() {
  final turnsDir = 'lib/training/extraction/golden/turns';
  final outputDir = 'lib/training/extraction/golden/segment_output';

  test('segment all golden conversations', () async {
    await Directory(outputDir).create(recursive: true);
    final conversations = await _loadConversations(turnsDir);

    final normalizeStage = NormalizeStage();
    final segmentStage = SegmentStage();

    var totalSentences = 0;
    var totalTurns = 0;
    var totalChars = 0;
    var totalDroppedFragments = 0;
    final allSentenceLengths = <int>[];
    final sentencesPerTurn = <int>[];

    for (final conv in conversations) {
      final turnResults = <_TurnResult>[];

      for (var i = 0; i < conv.turns.length; i++) {
        final turn = conv.turns[i];

        for (final speaker in ['user', 'assistant']) {
          final key = speaker == 'user' ? 'prompt' : 'response';
          final text = turn[key] as String? ?? '';
          if (text.isEmpty) continue;

          final result = await _processTurn(
            normalizeStage: normalizeStage,
            segmentStage: segmentStage,
            text: text,
            turnIndex: i,
            speaker: speaker,
          );

          turnResults.add(result);
          totalSentences += result.sentences.length;
          totalTurns++;
          totalChars += result.inputCharCount;
          totalDroppedFragments += result.droppedFragments;
          sentencesPerTurn.add(result.sentences.length);

          for (final s in result.sentences) {
            allSentenceLengths.add((s['text'] as String).length);
          }
        }
      }

      final output = {
        'conversationUuid': conv.uuid,
        'conversationName': conv.name,
        'turnCount': turnResults.length,
        'totalSentences':
            turnResults.fold<int>(0, (sum, t) => sum + t.sentences.length),
        'turns': turnResults.map((t) => t.toJson()).toList(),
      };

      final outputFile = File('$outputDir/${conv.uuid}.json');
      await outputFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(output));
    }

    // ============ Summary Stats ============

    allSentenceLengths.sort();
    sentencesPerTurn.sort();

    final avgSentencesPerTurn =
        totalTurns > 0 ? totalSentences / totalTurns : 0.0;
    final sentencesPer1000Chars =
        totalChars > 0 ? (totalSentences / totalChars) * 1000 : 0.0;
    final minSentenceLen =
        allSentenceLengths.isNotEmpty ? allSentenceLengths.first : 0;
    final maxSentenceLen =
        allSentenceLengths.isNotEmpty ? allSentenceLengths.last : 0;
    final medianSentenceLen = allSentenceLengths.isNotEmpty
        ? allSentenceLengths[allSentenceLengths.length ~/ 2]
        : 0;
    final p5SentencesPerTurn = sentencesPerTurn.isNotEmpty
        ? sentencesPerTurn[(sentencesPerTurn.length * 0.05).floor()]
        : 0;
    final p95SentencesPerTurn = sentencesPerTurn.isNotEmpty
        ? sentencesPerTurn[
            min(sentencesPerTurn.length - 1, (sentencesPerTurn.length * 0.95).floor())]
        : 0;

    // ignore: avoid_print
    print('\n========== SEGMENT GOLDEN STATS ==========');
    // ignore: avoid_print
    print('Conversations:        ${conversations.length}');
    // ignore: avoid_print
    print('Total turns:          $totalTurns');
    // ignore: avoid_print
    print('Total sentences:      $totalSentences');
    // ignore: avoid_print
    print('Avg sentences/turn:   ${avgSentencesPerTurn.toStringAsFixed(1)}');
    // ignore: avoid_print
    print(
        'Sentences/1000 chars: ${sentencesPer1000Chars.toStringAsFixed(2)}');
    // ignore: avoid_print
    print('Min sentence length:  $minSentenceLen chars');
    // ignore: avoid_print
    print('Max sentence length:  $maxSentenceLen chars');
    // ignore: avoid_print
    print('Median sentence len:  $medianSentenceLen chars');
    // ignore: avoid_print
    print(
        'Sentences/turn p5-p95: $p5SentencesPerTurn - $p95SentencesPerTurn');
    // ignore: avoid_print
    print('Dropped fragments:    $totalDroppedFragments');
    // ignore: avoid_print
    print('===========================================\n');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

// ============ Turn Processing ============

Future<_TurnResult> _processTurn({
  required NormalizeStage normalizeStage,
  required SegmentStage segmentStage,
  required String text,
  required int turnIndex,
  required String speaker,
}) async {
  final normalizeResult = await normalizeStage.process(text);
  final segmentResult = await segmentStage.process(normalizeResult.output);

  // Count dropped fragments by running segment without filter and comparing
  final allSentenceCount =
      _countPreFilterSentences(normalizeResult.output);
  final droppedFragments = allSentenceCount - segmentResult.sentences.length;

  return _TurnResult(
    turnIndex: turnIndex,
    speaker: speaker,
    inputCharCount: text.length,
    sentences: segmentResult.sentences
        .map((s) => {'id': s.id, 'text': s.text})
        .toList(),
    droppedFragments: max(0, droppedFragments),
    punctuationNeeded: normalizeResult.trace.punctuationNeeded,
  );
}

/// Count sentences before fragment filtering to measure drop count.
/// Mimics SegmentStage._splitSentences + _stripCodeBlocks + _stripMarkdown
/// without the _filterFragments step.
int _countPreFilterSentences(String text) {
  if (text.trim().isEmpty) return 0;

  // Strip code blocks (same regexes as SegmentStage)
  final withoutCode = text
      .replaceAll(RegExp(r'```[^\n]*\n[\s\S]*?```', multiLine: true), '')
      .replaceAll(RegExp(r'(^(    |\t).+\n?)+', multiLine: true), '');

  // Strip markdown
  final prose = withoutCode
      .replaceAll(RegExp(r'^#{1,6}\s+.*$', multiLine: true), '')
      .replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m.group(1)!)
      .replaceAll(RegExp(r'^[\s]*[-*+]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^[\s]*\d+\.\s+', multiLine: true), '');

  // Split on sentence boundaries
  final parts = prose
      .split(RegExp(r'(?<=[.?!])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  // Account for remainder (text not ending with sentence-end punctuation)
  if (prose.trim().isNotEmpty && parts.isEmpty) return 1;
  return parts.length;
}

// ============ Data Loading ============

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
