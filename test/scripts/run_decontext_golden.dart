/// Run DecontextualizeStage on all classify-extract spans from golden data.
/// Reads classify_output/ + segment_output/, writes decontext_output/.
///
/// Usage:
///   flutter test test/scripts/run_decontext_golden.dart
///   flutter test test/scripts/run_decontext_golden.dart --name="conv_01d28f67"
@TestOn('windows')
library;

import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/types/chat_client.dart';
import 'package:everything_stack_template/services/types/message.dart';
import 'package:everything_stack_template/services/memory/encoder_trace.dart';
import 'package:everything_stack_template/services/memory/working_memory_service.dart';
import 'package:everything_stack_template/services/memory/stages/decontextualize_stage.dart';

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
      'max_tokens': 2048,
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

void main() {
  final classifyDir = 'lib/training/extraction/golden/classify_output';
  final segmentDir = 'lib/training/extraction/golden/segment_output';
  final cohereDir = 'lib/training/extraction/golden/cohere_output';
  final outputDir = 'lib/training/extraction/golden/decontext_output';

  late GroqChatClient chatClient;
  late DecontextualizeStage decontextStage;

  setUpAll(() {
    chatClient = GroqChatClient(apiKey: _loadGroqApiKey());
    decontextStage = DecontextualizeStage(chatClient: chatClient);
  });

  tearDownAll(() => chatClient.close());

  test('decontextualize all golden conversations', () async {
    await Directory(outputDir).create(recursive: true);

    final classifyFiles = await Directory(classifyDir)
        .list()
        .where((e) => e.path.endsWith('.json'))
        .toList();
    classifyFiles.sort((a, b) => a.path.compareTo(b.path));

    var totalExtractSpans = 0;
    var totalPropositions = 0;

    for (final file in classifyFiles) {
      final classifyData = jsonDecode(await File(file.path).readAsString())
          as Map<String, dynamic>;
      final uuid = classifyData['conversationUuid'] as String;
      final name = classifyData['conversationName'] as String;

      final outputFile = File('$outputDir/$uuid.json');
      if (outputFile.existsSync()) {
        // ignore: avoid_print
        print('  SKIP $name (output exists)');
        continue;
      }

      final segmentData = jsonDecode(
        await File('$segmentDir/$uuid.json').readAsString(),
      ) as Map<String, dynamic>;

      final cohereData = jsonDecode(
        await File('$cohereDir/$uuid.json').readAsString(),
      ) as Map<String, dynamic>;

      final turnOutputs = <Map<String, dynamic>>[];
      final workingMemory = WorkingMemoryService(maxCapacity: 100);

      for (final turn in classifyData['turns'] as List<dynamic>) {
        final turnMap = turn as Map<String, dynamic>;
        final turnIndex = turnMap['turnIndex'] as int;

        final segTurn = (segmentData['turns'] as List<dynamic>)
            .firstWhere((t) => (t as Map<String, dynamic>)['turnIndex'] == turnIndex)
            as Map<String, dynamic>;

        final sentences = (segTurn['sentences'] as List<dynamic>)
            .map((s) => Sentence(
                  id: (s as Map<String, dynamic>)['id'] as String,
                  text: s['text'] as String,
                ))
            .toList();

        // Get span->sentenceIds from cohere output
        final cohereTurn = (cohereData['turns'] as List<dynamic>)
            .firstWhere((t) => (t as Map<String, dynamic>)['turnIndex'] == turnIndex)
            as Map<String, dynamic>;
        final cohereSpanMap = <String, List<String>>{};
        for (final span in cohereTurn['spans'] as List<dynamic>) {
          final spanMap = span as Map<String, dynamic>;
          cohereSpanMap[spanMap['spanId'] as String] =
              (spanMap['sentenceIds'] as List<dynamic>).cast<String>();
        }

        // Filter to extract-only spans
        final decisions = (turnMap['decisions'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final extractSpanIds = decisions
            .where((d) => d['label'] == 'extract')
            .map((d) => d['spanId'] as String)
            .toSet();

        final extractSpans = extractSpanIds
            .where((id) => cohereSpanMap.containsKey(id))
            .map((id) => ConceptSpan(
                  spanId: id,
                  sentenceIds: cohereSpanMap[id]!,
                ))
            .toList();

        if (extractSpans.isEmpty) {
          turnOutputs.add({
            'turnIndex': turnIndex,
            'speaker': turnMap['speaker'],
            'extractSpanCount': 0,
            'propositionCount': 0,
            'propositions': [],
            'latencyMs': 0,
          });
          continue;
        }

        totalExtractSpans += extractSpans.length;

        final result = await decontextStage.process(DecontextualizeInput(
          extractSpans: extractSpans,
          sentences: sentences,
          workingMemory: workingMemory,
          sourceTurnId: '${uuid}_turn_$turnIndex',
          sourceEpisodeId: uuid,
        ));

        totalPropositions += result.propositions.length;

        turnOutputs.add({
          'turnIndex': turnIndex,
          'speaker': turnMap['speaker'],
          'extractSpanCount': extractSpans.length,
          'propositionCount': result.propositions.length,
          'propositions': result.propositions.map((p) => {
            'content': p.content,
            'scope': p.scope,
            'type': p.type,
            'sourceIds': p.sourceIds,
          }).toList(),
          'latencyMs': result.trace.totalLatencyMs,
        });
      }

      final output = {
        'conversationUuid': uuid,
        'conversationName': name,
        'turnCount': (classifyData['turns'] as List).length,
        'stage': 'decontextualize',
        'model': 'groq/llama-3.1-8b-instant',
        'turns': turnOutputs,
      };

      await outputFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(output),
      );

      final propCount = turnOutputs.fold<int>(
          0, (sum, t) => sum + (t['propositionCount'] as int));
      final spanCount = turnOutputs.fold<int>(
          0, (sum, t) => sum + (t['extractSpanCount'] as int));

      // ignore: avoid_print
      print('  $name: $spanCount extract spans -> $propCount propositions');
    }

    // ignore: avoid_print
    print('\n--- Summary ---');
    // ignore: avoid_print
    print('Total extract spans: $totalExtractSpans');
    // ignore: avoid_print
    print('Total propositions: $totalPropositions');
    if (totalExtractSpans > 0) {
      // ignore: avoid_print
      print('Avg propositions/span: ${(totalPropositions / totalExtractSpans).toStringAsFixed(1)}');
    }
  }, timeout: const Timeout(Duration(minutes: 120)));
}

