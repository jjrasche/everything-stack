/// Run the encoder pipeline on golden conversation data.
///
/// No Flutter dependency — uses direct Groq HTTP via CliChatClient.
///
/// Usage:
///   dart run scripts/run_encoder.dart
///   dart run scripts/run_encoder.dart --conv=conv_3475558a
///   dart run scripts/run_encoder.dart --dir=lib/training/extraction/golden/turns

import 'dart:io';
import 'dart:convert';

import 'cli_chat_client.dart';
import '../lib/services/memory/encoder.dart';
import '../lib/services/memory/encoder_trace.dart';
import '../lib/services/memory/working_memory_service.dart';
import '../lib/services/memory/stages/normalize_stage.dart';
import '../lib/services/memory/stages/segment_stage.dart';
import '../lib/services/memory/stages/cohere_stage.dart';
import '../lib/services/memory/stages/classify_stage.dart';
import '../lib/services/memory/stages/decontextualize_stage.dart';
import '../lib/services/memory/stages/dedup_stage.dart';

Future<void> main(List<String> args) async {
  final apiKey = loadGroqApiKey();
  final chatClient = CliChatClient(apiKey: apiKey);

  try {
    final turnsDir = _parseArg(args, 'dir', 'lib/training/extraction/golden/turns');
    final convFilter = _parseArg(args, 'conv', '');
    final outputDir = 'lib/training/extraction/golden/encoder_output';

    await Directory(outputDir).create(recursive: true);

    final conversations = await _loadConversations(turnsDir);
    final filtered = convFilter.isEmpty
        ? conversations
        : conversations.where((c) => c.uuid.startsWith(convFilter)).toList();

    if (filtered.isEmpty) {
      print('No conversations found${convFilter.isNotEmpty ? ' matching $convFilter' : ''}');
      exit(1);
    }

    print('Processing ${filtered.length} conversation(s)...\n');

    final encoder = _createEncoder(chatClient);

    for (final conv in filtered) {
      await _processConversation(conv, encoder, outputDir);
    }

    print('\nDone. Output written to $outputDir/');
  } finally {
    chatClient.close();
  }
}

// ============ Encoder Construction ============

Encoder _createEncoder(CliChatClient chatClient) {
  final decontextStage = DecontextualizeStage(chatClient: chatClient);

  return Encoder(
    normalizeStage: NormalizeStage(),
    segmentStage: SegmentStage(),
    cohereStage: CohereStage(chatClient: chatClient),
    classifyStage: ClassifyStage(chatClient: chatClient),
    decontextualizeStage: decontextStage,
    dedupStage: DedupStage(
      chatClient: chatClient,
      decontextualizeStage: decontextStage,
    ),
  );
}

// ============ Conversation Processing ============

Future<void> _processConversation(
  _Conversation conv,
  Encoder encoder,
  String outputDir,
) async {
  print('${conv.name} (${conv.turns.length} turns)');

  final workingMemory = WorkingMemoryService(maxCapacity: 100);
  final turnTraces = <Map<String, dynamic>>[];

  for (var i = 0; i < conv.turns.length; i++) {
    final turn = conv.turns[i];
    final turnId = '${conv.uuid}_turn_$i';

    final promptText = turn['prompt'] as String? ?? '';
    if (promptText.isNotEmpty) {
      final result = await encoder.encode(
        source: EpisodicSource(
          text: promptText,
          speaker: 'user',
          episodeId: conv.uuid,
        ),
        turnId: '${turnId}_user',
        workingMemory: workingMemory,
      );
      workingMemory.applyDiff(result.diff);
      turnTraces.add(result.trace.toJson());
      _printDiffSummary(i, 'user', result.diff);
    }

    final responseText = turn['response'] as String? ?? '';
    if (responseText.isNotEmpty) {
      final result = await encoder.encode(
        source: EpisodicSource(
          text: responseText,
          speaker: 'assistant',
          episodeId: conv.uuid,
        ),
        turnId: '${turnId}_assistant',
        workingMemory: workingMemory,
      );
      workingMemory.applyDiff(result.diff);
      turnTraces.add(result.trace.toJson());
      _printDiffSummary(i, 'asst', result.diff);
    }
  }

  final output = _buildOutput(conv, workingMemory, turnTraces);
  final outputFile = File('$outputDir/${conv.uuid}.json');
  await outputFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
  );

  print('  -> ${workingMemory.state.length} propositions in working memory\n');
}

void _printDiffSummary(int turnIndex, String speaker, dynamic diff) {
  final added = diff.added.length;
  final superseded = diff.superseded.length;
  if (added > 0 || superseded > 0) {
    print('  Turn $turnIndex ($speaker): +$added props, -$superseded superseded');
  }
}

Map<String, dynamic> _buildOutput(
  _Conversation conv,
  WorkingMemoryService workingMemory,
  List<Map<String, dynamic>> turnTraces,
) {
  return {
    'conversationUuid': conv.uuid,
    'conversationName': conv.name,
    'turnCount': conv.turns.length,
    'finalWorkingMemory': workingMemory.state
        .map((p) => {
              'uuid': p.uuid,
              'content': p.content,
              'scope': p.scope,
              'type': p.type,
              'sourceIds': p.sourceIds,
              'sourceTurnId': p.sourceTurnId,
              'status': p.status,
            })
        .toList(),
    'traces': turnTraces,
  };
}

// ============ Golden Data Loading ============

class _Conversation {
  final String uuid;
  final String name;
  final List<Map<String, dynamic>> turns;

  _Conversation({required this.uuid, required this.name, required this.turns});
}

Future<List<_Conversation>> _loadConversations(String dir) async {
  final directory = Directory(dir);
  if (!await directory.exists()) {
    print('Golden data directory not found: $dir');
    exit(1);
  }

  final jsonFiles = await directory
      .list()
      .where((entity) => entity.path.endsWith('.json'))
      .toList();

  if (jsonFiles.isEmpty) {
    print('No .json files found in $dir');
    exit(1);
  }

  final conversations = <_Conversation>[];

  for (final file in jsonFiles) {
    final content = await File(file.path).readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;
    final conversation = data['conversation'] as Map<String, dynamic>;
    final rawTurns = conversation['turns'] as List<dynamic>;

    final turns = rawTurns.map((t) {
      final turn = t as Map<String, dynamic>;
      return <String, dynamic>{
        'prompt': turn['prompt'] ?? '',
        'response': turn['response'] ?? '',
      };
    }).toList();

    conversations.add(_Conversation(
      uuid: conversation['uuid'] as String,
      name: conversation['name'] as String? ?? 'Unnamed',
      turns: turns,
    ));
  }

  conversations.sort((a, b) => a.uuid.compareTo(b.uuid));
  return conversations;
}

// ============ Argument Parsing ============

String _parseArg(List<String> args, String key, String defaultValue) {
  for (final arg in args) {
    if (arg.startsWith('--$key=')) {
      return arg.substring('--$key='.length);
    }
  }
  return defaultValue;
}
