/// Run ClassifyStage on all golden conversations' cohere output.
/// Reads cohere_output/ + segment_output/, writes classify_output/.
///
/// Usage:
///   flutter test test/scripts/run_classify_golden.dart
///   flutter test test/scripts/run_classify_golden.dart --name="conv_01d28f67"
@TestOn('windows')
library;

import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/types/chat_client.dart';
import 'package:everything_stack_template/services/types/message.dart';
import 'package:everything_stack_template/services/memory/encoder_trace.dart';
import 'package:everything_stack_template/services/memory/working_memory_service.dart';
import 'package:everything_stack_template/services/memory/stages/classify_stage.dart';

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
      'max_tokens': 512,
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
  final cohereDir = 'lib/training/extraction/golden/cohere_output';
  final segmentDir = 'lib/training/extraction/golden/segment_output';
  final outputDir = 'lib/training/extraction/golden/classify_output';

  late GroqChatClient chatClient;
  late ClassifyStage classifyStage;

  setUpAll(() {
    chatClient = GroqChatClient(apiKey: _loadGroqApiKey());
    classifyStage = ClassifyStage(chatClient: chatClient);
  });

  tearDownAll(() => chatClient.close());

  test('classify all golden conversations', () async {
    await Directory(outputDir).create(recursive: true);

    final cohereFiles = await Directory(cohereDir)
        .list()
        .where((e) => e.path.endsWith('.json'))
        .toList();
    cohereFiles.sort((a, b) => a.path.compareTo(b.path));

    var totalSpans = 0;
    var totalExtract = 0;
    var totalSkip = 0;

    for (final file in cohereFiles) {
      final cohereData = jsonDecode(await File(file.path).readAsString())
          as Map<String, dynamic>;
      final uuid = cohereData['conversationUuid'] as String;
      final name = cohereData['conversationName'] as String;

      final outputFile = File('$outputDir/$uuid.json');
      if (outputFile.existsSync()) {
        // ignore: avoid_print
        print('  SKIP $name (output exists)');
        continue;
      }

      // Load matching segment data for sentence text
      final segmentData = jsonDecode(
        await File('$segmentDir/$uuid.json').readAsString(),
      ) as Map<String, dynamic>;

      final turnOutputs = <Map<String, dynamic>>[];
      final workingMemory = WorkingMemoryService(maxCapacity: 100);

      for (final turn in cohereData['turns'] as List<dynamic>) {
        final turnMap = turn as Map<String, dynamic>;
        final turnIndex = turnMap['turnIndex'] as int;

        // Find matching segment turn for sentence text
        final segTurn = (segmentData['turns'] as List<dynamic>)
            .firstWhere((t) => (t as Map<String, dynamic>)['turnIndex'] == turnIndex)
            as Map<String, dynamic>;

        final sentences = (segTurn['sentences'] as List<dynamic>)
            .map((s) => Sentence(
                  id: (s as Map<String, dynamic>)['id'] as String,
                  text: s['text'] as String,
                ))
            .toList();

        final spans = (turnMap['spans'] as List<dynamic>)
            .map((s) => ConceptSpan(
                  spanId: (s as Map<String, dynamic>)['spanId'] as String,
                  sentenceIds: ((s)['sentenceIds'] as List<dynamic>).cast<String>(),
                ))
            .toList();

        if (spans.isEmpty) {
          turnOutputs.add({
            'turnIndex': turnIndex,
            'speaker': turnMap['speaker'],
            'spanCount': 0,
            'extractCount': 0,
            'skipCount': 0,
            'decisions': [],
            'latencyMs': 0,
          });
          continue;
        }

        final result = await classifyStage.process(ClassifyInput(
          spans: spans,
          sentences: sentences,
          workingMemory: workingMemory,
        ));

        final extractCount = result.decisions.where((d) => d.isExtract).length;
        final skipCount = result.decisions.where((d) => !d.isExtract).length;

        totalSpans += spans.length;
        totalExtract += extractCount;
        totalSkip += skipCount;

        turnOutputs.add({
          'turnIndex': turnIndex,
          'speaker': turnMap['speaker'],
          'spanCount': spans.length,
          'extractCount': extractCount,
          'skipCount': skipCount,
          'decisions': result.decisions.map((d) => {
            ...d.toJson(),
            'spanText': spans
                .firstWhere((s) => s.spanId == d.spanId)
                .resolveText(sentences),
          }).toList(),
          'latencyMs': result.trace.totalLatencyMs,
        });
      }

      final output = {
        'conversationUuid': uuid,
        'conversationName': name,
        'turnCount': (cohereData['turns'] as List).length,
        'stage': 'classify',
        'model': 'groq/llama-3.1-8b-instant',
        'turns': turnOutputs,
      };

      await outputFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(output),
      );

      final extractCount = turnOutputs.fold<int>(
          0, (sum, t) => sum + (t['extractCount'] as int));
      final skipCount = turnOutputs.fold<int>(
          0, (sum, t) => sum + (t['skipCount'] as int));
      final spanCount = turnOutputs.fold<int>(
          0, (sum, t) => sum + (t['spanCount'] as int));

      // ignore: avoid_print
      print('  $name: $spanCount spans -> $extractCount extract, $skipCount skip');
    }

    // ignore: avoid_print
    print('\n--- Summary ---');
    // ignore: avoid_print
    print('Total spans: $totalSpans');
    // ignore: avoid_print
    print('Extract: $totalExtract (${(totalExtract / totalSpans * 100).toStringAsFixed(1)}%)');
    // ignore: avoid_print
    print('Skip: $totalSkip (${(totalSkip / totalSpans * 100).toStringAsFixed(1)}%)');
  }, timeout: const Timeout(Duration(minutes: 120)));
}
