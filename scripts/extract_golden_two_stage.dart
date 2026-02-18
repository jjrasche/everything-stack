/// Two-stage golden data extraction: Stage 1 (select) then Stage 2 (format).
///
/// Calls Anthropic Messages API directly. No Flutter dependency.
///
/// Usage:
///   dart run scripts/extract_golden_two_stage.dart --conv=3475558a
///   dart run scripts/extract_golden_two_stage.dart  # all conversations

import 'dart:io';
import 'dart:convert';

const _goldenDir = 'lib/training/extraction/golden';
const _turnsDir = '$_goldenDir/turns';
const _extractionsDir = '$_goldenDir/extractions';
const _selectionDir = '$_goldenDir/selection';
const _stage1PromptPath = '$_goldenDir/stage1_prompt.txt';
const _stage2PromptPath = '$_goldenDir/stage2_prompt.txt';
const _anthropicModel = 'claude-sonnet-4-5-20250929';
const _anthropicUrl = 'https://api.anthropic.com/v1/messages';
const _anthropicVersion = '2023-06-01';

// ============ Orchestrator ============

Future<void> main(List<String> args) async {
  final convFilter = _parseArg(args, 'conv', '');
  final apiKey = await _loadApiKey();
  final stage1Prompt = await _loadFile(_stage1PromptPath);
  final stage2Prompt = await _loadFile(_stage2PromptPath);
  final conversations = await _loadTurnFiles(_turnsDir, convFilter);

  print('Loaded ${conversations.length} conversations\n');

  for (final conv in conversations) {
    await _extractConversation(conv, stage1Prompt, stage2Prompt, apiKey);
  }
}

// ============ Concept Functions ============

Future<String> _loadApiKey() async {
  final envFile = File('.env');
  if (!await envFile.exists()) {
    print('.env not found');
    exit(1);
  }
  final lines = await envFile.readAsLines();
  for (final line in lines) {
    if (line.startsWith('ANTHROPIC_API_KEY=')) {
      return line.substring('ANTHROPIC_API_KEY='.length).trim();
    }
  }
  print('ANTHROPIC_API_KEY not found in .env');
  exit(1);
}

Future<String> _loadFile(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    print('File not found: $path');
    exit(1);
  }
  return file.readAsString();
}

Future<List<_TurnFile>> _loadTurnFiles(String dir, String filter) async {
  final directory = Directory(dir);
  if (!await directory.exists()) {
    print('Turns directory not found: $dir');
    exit(1);
  }

  final files = await directory
      .list()
      .where((e) => e.path.endsWith('.json'))
      .where((e) => filter.isEmpty || e.path.contains(filter))
      .toList();

  if (files.isEmpty) {
    print('No matching turn files in $dir');
    exit(1);
  }

  final results = <_TurnFile>[];
  for (final file in files) {
    final content = await File(file.path).readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;
    results.add(_TurnFile(
      convUuid: data['convUuid'] as String,
      convName: data['convName'] as String,
      turnCount: data['turnCount'] as int,
      turns: (data['turns'] as List<dynamic>).cast<Map<String, dynamic>>(),
    ));
  }

  results.sort((a, b) => a.convUuid.compareTo(b.convUuid));
  return results;
}

Future<void> _extractConversation(
  _TurnFile conv,
  String stage1Prompt,
  String stage2Prompt,
  String apiKey,
) async {
  print('${conv.convName} (${conv.turnCount} turns)');

  final whiteboard = <String>[];
  final extraction = <Map<String, dynamic>>[];
  var insightCount = 0;

  for (var i = 0; i < conv.turns.length; i++) {
    final turn = conv.turns[i];
    final turnResult = await _extractTurn(
      turn, whiteboard, stage1Prompt, stage2Prompt, apiKey,
    );

    extraction.add({
      'turnIndex': i,
      'whiteboardBefore': List<String>.from(whiteboard),
      'extracted': turnResult.insights,
      'skipped': turnResult.skipped,
      'stage1Raw': turnResult.stage1Raw,
    });

    for (final insight in turnResult.insights) {
      whiteboard.add(insight['content'] as String);
      insightCount++;
    }

    final selected = turnResult.insights.length;
    final skipped = turnResult.skipped.length;
    print('  Turn $i: $selected extracted, $skipped skipped');
  }

  await _writeExtraction(conv, extraction, insightCount);
  await _writeSelectionLog(conv, extraction);
  print('  Total: $insightCount insights\n');
}

Future<_TurnResult> _extractTurn(
  Map<String, dynamic> turn,
  List<String> whiteboard,
  String stage1Prompt,
  String stage2Prompt,
  String apiKey,
) async {
  final turnContext = _formatTurnContext(turn);
  final whiteboardContext = _formatWhiteboard(whiteboard);

  final stage1Input = '$turnContext\n$whiteboardContext\nSelected:';
  final stage1Response = await _callAnthropic(apiKey, stage1Prompt, stage1Input);
  final stage1Parsed = _parseStage1(stage1Response);


  if (stage1Parsed.selected.isEmpty) {
    return _TurnResult(
      insights: [],
      skipped: stage1Parsed.skipped,
      stage1Raw: stage1Parsed.selected,
    );
  }

  final candidatesJson = const JsonEncoder.withIndent('  ')
      .convert(stage1Parsed.selected);
  final stage2Input = 'Candidates:\n$candidatesJson\nInsights:';
  final stage2Response = await _callAnthropic(apiKey, stage2Prompt, stage2Input);
  final insights = _parseStage2(stage2Response);

  return _TurnResult(
    insights: insights,
    skipped: stage1Parsed.skipped,
    stage1Raw: stage1Parsed.selected,
  );
}

String _formatTurnContext(Map<String, dynamic> turn) {
  final prompt = turn['prompt'] as String? ?? '';
  final response = turn['response'] as String? ?? '';
  return 'Source Turn:\nUser: "$prompt"\nAssistant: "$response"';
}

String _formatWhiteboard(List<String> whiteboard) {
  if (whiteboard.isEmpty) {
    return 'Existing Whiteboard:\n(empty)';
  }
  final items = whiteboard.map((i) => '- $i').join('\n');
  return 'Existing Whiteboard:\n$items';
}

Future<String> _callAnthropic(
  String apiKey,
  String systemPrompt,
  String userContent,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(_anthropicUrl));
    request.headers.set('x-api-key', apiKey);
    request.headers.set('anthropic-version', _anthropicVersion);
    request.headers.set('Content-Type', 'application/json');

    final body = jsonEncode({
      'model': _anthropicModel,
      'max_tokens': 4096,
      'system': systemPrompt,
      'messages': [
        {'role': 'user', 'content': userContent},
      ],
      'temperature': 0.3,
    });
    request.add(utf8.encode(body));

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      print('    Anthropic API error ${response.statusCode}: $responseBody');
      return '';
    }

    final parsed = jsonDecode(responseBody) as Map<String, dynamic>;
    final content = parsed['content'] as List<dynamic>;
    if (content.isEmpty) return '';
    final textBlock = content[0] as Map<String, dynamic>;
    return textBlock['text'] as String? ?? '';
  } finally {
    client.close();
  }
}

_Stage1Result _parseStage1(String response) {
  try {
    if (response.isEmpty) {
      return _Stage1Result(selected: [], skipped: []);
    }
    final cleaned = _stripMarkdownFencing(response);

    // Model completes after "Selected:" with an array, then "Skipped:" with another
    final skippedSplit = cleaned.split(RegExp(r'Skipped:\s*'));
    final selectedPart = skippedSplit[0];
    final skippedPart = skippedSplit.length > 1 ? skippedSplit[1] : '';

    final selected = _parseJsonArray(selectedPart);
    final skipped = _parseJsonArray(skippedPart);
    return _Stage1Result(selected: selected, skipped: skipped);
  } catch (e) {
    print('    Stage 1 parse error: $e');
    return _Stage1Result(selected: [], skipped: []);
  }
}

List<Map<String, dynamic>> _parseStage2(String response) {
  try {
    final cleaned = _stripMarkdownFencing(response);
    final jsonStr = _extractJsonArray(cleaned);
    if (jsonStr == null) return [];
    final parsed = jsonDecode(jsonStr) as List<dynamic>;
    return parsed.cast<Map<String, dynamic>>();
  } catch (e) {
    print('    Stage 2 parse error: $e');
    return [];
  }
}

Future<void> _writeExtraction(
  _TurnFile conv,
  List<Map<String, dynamic>> extraction,
  int insightCount,
) async {
  final dir = Directory(_extractionsDir);
  if (!await dir.exists()) await dir.create(recursive: true);

  final output = {
    'convUuid': conv.convUuid,
    'convName': conv.convName,
    'turnCount': conv.turnCount,
    'insightCount': insightCount,
    'extractionModel': _anthropicModel,
    'extractedAt': DateTime.now().toIso8601String(),
    'schema': 'per-turn-whiteboard-v1',
    'promptVersion': 'two-stage-v1',
    'extraction': extraction.map((e) => {
      'turnIndex': e['turnIndex'],
      'whiteboardBefore': e['whiteboardBefore'],
      'extracted': e['extracted'],
      'skipped': e['skipped'],
    }).toList(),
  };

  final shortUuid = conv.convUuid.length >= 8
      ? conv.convUuid.substring(0, 8)
      : conv.convUuid;
  final file = File('$_extractionsDir/conv_$shortUuid.json');
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
  );
}

Future<void> _writeSelectionLog(
  _TurnFile conv,
  List<Map<String, dynamic>> extraction,
) async {
  final dir = Directory(_selectionDir);
  if (!await dir.exists()) await dir.create(recursive: true);

  final shortUuid = conv.convUuid.length >= 8
      ? conv.convUuid.substring(0, 8)
      : conv.convUuid;
  final output = {
    'convUuid': conv.convUuid,
    'convName': conv.convName,
    'turnCount': conv.turnCount,
    'extractedAt': DateTime.now().toIso8601String(),
    'turns': extraction.map((e) => {
      'turnIndex': e['turnIndex'],
      'stage1Selected': e['stage1Raw'],
      'stage1Skipped': e['skipped'],
    }).toList(),
  };

  final file = File('$_selectionDir/conv_$shortUuid.json');
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
  );
}

// ============ Leaf Functions ============

String _stripMarkdownFencing(String text) {
  return text
      .replaceAll(RegExp(r'```json\s*'), '')
      .replaceAll(RegExp(r'```\s*'), '');
}

String? _extractJsonArray(String text) {
  final arrayMatch = RegExp(r'\[\s*\{.*\}\s*\]', dotAll: true)
      .firstMatch(text);
  if (arrayMatch != null) return arrayMatch.group(0);
  if (RegExp(r'\[\s*\]').hasMatch(text)) return '[]';
  return null;
}

List<Map<String, dynamic>> _parseJsonArray(String text) {
  final jsonStr = _extractJsonArray(text);
  if (jsonStr == null) return [];
  try {
    final parsed = jsonDecode(jsonStr) as List<dynamic>;
    return parsed.cast<Map<String, dynamic>>();
  } catch (e) {
    return [];
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

// ============ Data Types ============

class _TurnFile {
  final String convUuid;
  final String convName;
  final int turnCount;
  final List<Map<String, dynamic>> turns;

  _TurnFile({
    required this.convUuid,
    required this.convName,
    required this.turnCount,
    required this.turns,
  });
}

class _Stage1Result {
  final List<Map<String, dynamic>> selected;
  final List<Map<String, dynamic>> skipped;

  _Stage1Result({required this.selected, required this.skipped});
}

class _TurnResult {
  final List<Map<String, dynamic>> insights;
  final List<Map<String, dynamic>> skipped;
  final List<Map<String, dynamic>> stage1Raw;

  _TurnResult({
    required this.insights,
    required this.skipped,
    required this.stage1Raw,
  });
}
