/// Shared IO for golden data SLM accuracy test scripts.
///
/// Load conversations, read/write stage output JSON, check existence.
/// NOT for golden data generation (Claude Code does that).
library;

import 'dart:io';
import 'dart:convert';

// ============ Data Types ============

/// Source conversation from golden/turns/.
class GoldenConversation {
  final String uuid;
  final String name;
  final int turnCount;
  final List<GoldenTurn> turns;

  GoldenConversation({
    required this.uuid,
    required this.name,
    required this.turnCount,
    required this.turns,
  });
}

/// Single turn with user prompt and assistant response.
class GoldenTurn {
  final String prompt;
  final String response;

  GoldenTurn({required this.prompt, required this.response});
}

// ============ Directory Constants ============

const goldenRoot = 'lib/training/extraction/golden';
const turnsDir = '$goldenRoot/turns';
const normalizeOutputDir = '$goldenRoot/normalize_output';
const segmentOutputDir = '$goldenRoot/segment_output';
const cohereOutputDir = '$goldenRoot/cohere_output';
const recoherOutputDir = '$goldenRoot/recohere_output';
const filterLabelsPath = '$goldenRoot/labels/filter/labeled_all.json';
const decontextOutputDir = '$goldenRoot/decontext_output';
const dedupOutputDir = '$goldenRoot/dedup_output';

// ============ Load Conversations ============

/// Load all golden conversations sorted by UUID.
Future<List<GoldenConversation>> loadConversations([
  String dir = turnsDir,
]) async {
  final directory = Directory(dir);
  if (!await directory.exists()) {
    throw StateError('Directory not found: $dir');
  }

  final jsonFiles = await directory
      .list()
      .where((entity) => entity.path.endsWith('.json'))
      .toList();

  final conversations = <GoldenConversation>[];

  for (final file in jsonFiles) {
    final data = await readJson(file.path);
    final rawTurns = data['turns'] as List<dynamic>;

    final turns = rawTurns.map((t) {
      final turn = t as Map<String, dynamic>;
      return GoldenTurn(
        prompt: turn['prompt'] as String? ?? '',
        response: turn['response'] as String? ?? '',
      );
    }).toList();

    conversations.add(GoldenConversation(
      uuid: data['convUuid'] as String,
      name: data['convName'] as String? ?? 'Unnamed',
      turnCount: turns.length,
      turns: turns,
    ));
  }

  conversations.sort((a, b) => a.uuid.compareTo(b.uuid));
  return conversations;
}

// ============ JSON IO ============

/// Read a JSON file and return parsed map.
Future<Map<String, dynamic>> readJson(String path) async {
  final content = await File(path).readAsString();
  return jsonDecode(content) as Map<String, dynamic>;
}

/// Read a JSON file and return parsed list.
Future<List<dynamic>> readJsonList(String path) async {
  final content = await File(path).readAsString();
  return jsonDecode(content) as List<dynamic>;
}

/// Write a map as pretty-printed JSON.
Future<void> writeJson(String path, Map<String, dynamic> data) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(data),
  );
}

/// Check whether a JSON file exists for [uuid] in [outputDir].
bool outputExists(String outputDir, String uuid) {
  return File('$outputDir/$uuid.json').existsSync();
}

// ============ Standard Envelope ============

/// Wrap turn payloads in the standard golden data envelope.
Map<String, dynamic> buildEnvelope({
  required String uuid,
  required String conversationName,
  required int turnCount,
  required String stage,
  required String generator,
  required List<Map<String, dynamic>> turns,
}) {
  return {
    'conversationUuid': uuid,
    'conversationName': conversationName,
    'turnCount': turnCount,
    'stage': stage,
    'generator': generator,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'turns': turns,
  };
}

// ============ Summary ============

/// Print a formatted summary line.
void printSummary(String stageName, Map<String, int> counts) {
  final pairs = counts.entries.map((e) => '${e.key}: ${e.value}').join(', ');
  // ignore: avoid_print
  print('[$stageName] $pairs');
}
