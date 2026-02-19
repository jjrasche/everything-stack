import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final apiKey = Platform.environment['GROQ_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    fail('GROQ_API_KEY not set');
  }

  final spansFile = File('temp_test_spans.json');
  if (!spansFile.existsSync()) {
    fail('temp_test_spans.json not found');
  }

  final spans = (jsonDecode(spansFile.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  for (final span in spans) {
    final name = span['name'] as String;
    final sentenceCount = span['sentences'] as int;
    final text = span['text'] as String;

    test('decontextualize: $name ($sentenceCount sentences)', () async {
      final systemPrompt =
          '''You decompose a text span into atomic, self-contained propositions.

Rules:
- Each proposition must be understandable WITHOUT the source text
- Replace all pronouns with specific referents
- One fact per proposition. If a sentence contains multiple facts, split them.
- Skip filler, greetings, hedging, and meta-commentary ("I guess", "let me think")
- Output 0 propositions if the span contains no durable knowledge
- Scope: session (this conversation only), project (named project), life (identity-level)
- Type: learning (discovered fact), project (decision/requirement), exploration (investigated option)
- Output ONLY a JSON array, no other text.''';

      final userPrompt = '''Text span ($sentenceCount sentences):
$text

Output JSON array: [{"content": "...", "scope": "...", "type": "..."}]''';

      final body = jsonEncode({
        'model': 'llama-3.1-8b-instant',
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': 0.0,
        'max_tokens': 2000,
      });

      final request = await HttpClient()
          .postUrl(Uri.parse('https://api.groq.com/openai/v1/chat/completions'));
      request.headers.set('Authorization', 'Bearer $apiKey');
      request.headers.set('Content-Type', 'application/json');
      request.add(utf8.encode(body));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      final json = jsonDecode(responseBody) as Map<String, dynamic>;

      final content =
          json['choices'][0]['message']['content'] as String;

      // Parse propositions
      final arrStart = content.indexOf('[');
      final arrEnd = content.lastIndexOf(']');
      if (arrStart < 0 || arrEnd <= arrStart) {
        fail('No JSON array in response:\n$content');
      }
      final parsed = jsonDecode(content.substring(arrStart, arrEnd + 1)) as List;

      print('\n=== $name ($sentenceCount sentences, ${text.length} chars) ===');
      print('Propositions: ${parsed.length}');
      for (var i = 0; i < parsed.length; i++) {
        final p = parsed[i] as Map<String, dynamic>;
        print('  ${i + 1}. [${p['scope']}/${p['type']}] ${p['content']}');
      }

      // Basic sanity: should produce at least 2 propositions from 12+ sentences
      expect(parsed.length, greaterThan(1),
          reason: 'Expected multiple propositions from $sentenceCount sentences');
      // Should not over-produce (summarization symptom is too few, not too many)
      expect(parsed.length, lessThan(sentenceCount),
          reason: 'Should not produce more propositions than sentences');
    });
  }
}
