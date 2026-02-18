/// Run the encoder pipeline on golden conversation data.
///
/// Executed as a Flutter test to provide dart:ui for domain entity imports.
///
/// Usage:
///   flutter test test/scripts/run_encoder_test.dart
///   flutter test test/scripts/run_encoder_test.dart --name="conv_3475558a"
@TestOn('windows')
library;

import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/types/chat_client.dart';
import 'package:everything_stack_template/services/types/message.dart';
import 'package:everything_stack_template/services/memory/encoder.dart';
import 'package:everything_stack_template/services/memory/encoder_trace.dart';
import 'package:everything_stack_template/services/memory/working_memory_service.dart';
import 'package:everything_stack_template/services/memory/working_memory_diff.dart';
import 'package:everything_stack_template/services/memory/stages/normalize_stage.dart';
import 'package:everything_stack_template/services/memory/stages/segment_stage.dart';
import 'package:everything_stack_template/services/memory/stages/cohere_stage.dart';
import 'package:everything_stack_template/services/memory/stages/classify_stage.dart';
import 'package:everything_stack_template/services/memory/stages/decontextualize_stage.dart';
import 'package:everything_stack_template/services/memory/stages/dedup_stage.dart';

// ============ Groq HTTP Client ============

class GroqChatClient implements ChatClient {
  final String _apiKey;
  final String _model;
  final HttpClient _httpClient = HttpClient();

  GroqChatClient({required String apiKey, String model = 'llama-3.1-8b-instant'})
      : _apiKey = apiKey,
        _model = model;

  @override
  Future<String> chat({
    required String eventId,
    required List<Message> messages,
  }) async {
    final body = jsonEncode({
      'model': _model,
      'messages': messages.map((m) => {'role': m.role, 'content': m.content}).toList(),
      'temperature': 0.3,
      'max_tokens': 4096,
    });

    final uri = Uri.parse('https://api.groq.com/openai/v1/chat/completions');
    final request = await _httpClient.postUrl(uri);
    request.headers.set('Authorization', 'Bearer $_apiKey');
    request.headers.set('Content-Type', 'application/json; charset=utf-8');
    request.add(utf8.encode(body));

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode == 429 || response.statusCode >= 500) {
      final delay = response.statusCode == 429 ? 2 : 5;
      // ignore: avoid_print
      print('    [Groq ${response.statusCode}] retrying in ${delay}s...');
      await Future.delayed(Duration(seconds: delay));
      return chat(eventId: eventId, messages: messages);
    }

    if (response.statusCode != 200) {
      throw Exception('Groq API error ${response.statusCode}: $responseBody');
    }

    final data = jsonDecode(responseBody) as Map<String, dynamic>;
    final choices = data['choices'] as List;
    return (choices.first as Map<String, dynamic>)['message']['content'] as String;
  }

  void close() => _httpClient.close();
}

// ============ Conversation Data ============

class _Conversation {
  final String uuid;
  final String name;
  final List<Map<String, dynamic>> turns;

  _Conversation({required this.uuid, required this.name, required this.turns});
}

// ============ Test Entry Points ============

void main() {
  final turnsDir = 'lib/training/extraction/golden/turns';
  final outputDir = 'lib/training/extraction/golden/encoder_output';

  late GroqChatClient chatClient;
  late Encoder encoder;

  setUpAll(() {
    final apiKey = _loadGroqApiKey();
    chatClient = GroqChatClient(apiKey: apiKey);
    encoder = _createEncoder(chatClient);
  });

  tearDownAll(() => chatClient.close());

  test('encode all golden conversations', () async {
    await Directory(outputDir).create(recursive: true);
    final conversations = await _loadConversations(turnsDir);

    for (final conv in conversations) {
      final outputFile = File('$outputDir/${conv.uuid}.json');
      if (outputFile.existsSync()) {
        // ignore: avoid_print
        print('Skipping ${conv.name} (output exists)');
        continue;
      }
      await _processConversation(conv, encoder, outputDir);
    }
  }, timeout: const Timeout(Duration(minutes: 120)));

  test('conv_01d28f67', () async {
    await Directory(outputDir).create(recursive: true);
    final conversations = await _loadConversations(turnsDir);
    final conv = conversations.firstWhere((c) => c.uuid.startsWith('01d28f67'));
    await _processConversation(conv, encoder, outputDir);
  }, timeout: const Timeout(Duration(minutes: 30)));
}

// ============ Encoder Construction ============

Encoder _createEncoder(ChatClient chatClient) {
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
  // ignore: avoid_print
  print('${conv.name} (${conv.turns.length} turns)');

  final workingMemory = WorkingMemoryService(maxCapacity: 100);
  final turnTraces = <Map<String, dynamic>>[];

  for (var i = 0; i < conv.turns.length; i++) {
    final turn = conv.turns[i];
    final turnId = '${conv.uuid}_turn_$i';

    final promptText = turn['prompt'] as String? ?? '';
    if (promptText.isNotEmpty) {
      final result = await encoder.encode(
        source: EpisodicSource(text: promptText, speaker: 'user', episodeId: conv.uuid),
        turnId: '${turnId}_user',
        workingMemory: workingMemory,
        skipDedup: false,
      );
      workingMemory.applyDiff(result.diff);
      turnTraces.add(result.trace.toJson());
      _printDiff(i, 'user', result.diff);
    }

    final responseText = turn['response'] as String? ?? '';
    if (responseText.isNotEmpty) {
      final result = await encoder.encode(
        source: EpisodicSource(text: responseText, speaker: 'assistant', episodeId: conv.uuid),
        turnId: '${turnId}_assistant',
        workingMemory: workingMemory,
        skipDedup: false,
      );
      workingMemory.applyDiff(result.diff);
      turnTraces.add(result.trace.toJson());
      _printDiff(i, 'asst', result.diff);
    }
  }

  final output = {
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

  final outputFile = File('$outputDir/${conv.uuid}.json');
  await outputFile.writeAsString(const JsonEncoder.withIndent('  ').convert(output));

  // ignore: avoid_print
  print('  -> ${workingMemory.state.length} propositions in working memory\n');
}

void _printDiff(int turnIndex, String speaker, WorkingMemoryDiff diff) {
  final added = diff.added.length;
  final superseded = diff.superseded.length;
  if (added > 0 || superseded > 0) {
    // ignore: avoid_print
    print('  Turn $turnIndex ($speaker): +$added props, -$superseded superseded');
  }
}

// ============ Data Loading ============

String _loadGroqApiKey() {
  final file = File('.env');
  if (!file.existsSync()) throw Exception('Missing .env with GROQ_API_KEY');
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.startsWith('GROQ_API_KEY=')) {
      return trimmed.substring('GROQ_API_KEY='.length).trim();
    }
  }
  throw Exception('GROQ_API_KEY not found in .env');
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
