/// # Real Groq Prompt Test
///
/// Actually calls Groq API to test NarrativeThinker extraction prompt
/// Verifies: format, dedup, scope correctness
///
/// Run with:
/// ```bash
/// GROQ_API_KEY=your-key dart test/groq_prompt_test.dart
/// ```

import 'dart:io';
import 'dart:async';
import 'dart:convert';

// ============================================================================
// GROQ API CLIENT
// ============================================================================

class GroqClient {
  final String apiKey;
  static const String baseUrl = 'https://api.groq.com/openai/v1/chat/completions';

  GroqClient(this.apiKey);

  Future<String> callChat({
    required List<Map<String, String>> messages,
    String model = 'mixtral-8x7b-32768',
    double temperature = 0.7,
  }) async {
    final client = HttpClient();
    try {
      final url = Uri.parse(baseUrl);
      final request = client.postUrl(url);

      request.headers.set('Authorization', 'Bearer $apiKey');
      request.headers.set('Content-Type', 'application/json');

      final body = jsonEncode({
        'model': model,
        'messages': messages,
        'temperature': temperature,
        'max_tokens': 500,
      });

      request.add(utf8.encode(body));
      final response = await request.close();

      if (response.statusCode != 200) {
        final error = await response.transform(utf8.decoder).join();
        throw Exception('Groq API error (${response.statusCode}): $error');
      }

      final responseBody = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(responseBody);

      if (decoded['choices'] == null || decoded['choices'].isEmpty) {
        throw Exception('No choices in Groq response');
      }

      return decoded['choices'][0]['message']['content'] ?? '';
    } finally {
      client.close();
    }
  }
}

// ============================================================================
// RUBRIC VALIDATOR
// ============================================================================

class NarrativeThinkerRubric {
  bool isValidJsonArray(String text) {
    try {
      final trimmed = text.trim();
      if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) {
        return false;
      }
      jsonDecode(trimmed);
      return true;
    } catch (e) {
      return false;
    }
  }

  Map<String, dynamic> validateExtraction(String response, String testCase) {
    final result = {
      'valid_json': false,
      'format_correct': false,
      'dedup_working': false,
      'scope_correct': false,
      'entries_count': 0,
      'failures': <String>[],
    };

    // Check 1: Valid JSON
    if (!isValidJsonArray(response)) {
      result['failures'].add('FAIL: Response is not valid JSON array');
      return result;
    }
    result['valid_json'] = true;

    try {
      final list = jsonDecode(response) as List;
      result['entries_count'] = list.length;

      // Check 2: Format
      if (list.isNotEmpty) {
        final entry = list.first as Map;
        if (entry.containsKey('content') &&
            entry.containsKey('scope') &&
            entry.containsKey('type')) {
          result['format_correct'] = true;
        } else {
          result['failures'].add('FAIL: Missing required fields (content, scope, type)');
        }

        // Check 3: Dedup (if applicable)
        if (testCase == 'dedup') {
          if (list.isEmpty) {
            result['dedup_working'] = true;
          } else {
            result['failures'].add('FAIL: Dedup test expected empty array, got ${list.length} entries');
          }
        } else {
          result['dedup_working'] = true; // Not applicable
        }

        // Check 4: Scope correctness
        if (testCase == 'project') {
          final scope = entry['scope'];
          if (scope == 'session') {
            result['scope_correct'] = true;
          } else {
            result['failures'].add('FAIL: Project should have scope=session (not $scope)');
          }
        } else if (testCase == 'learning') {
          final type = entry['type'];
          if (type == 'learning') {
            result['scope_correct'] = true;
          } else {
            result['failures'].add('FAIL: Learning should have type=learning (not $type)');
          }
        } else {
          result['scope_correct'] = true; // Not applicable
        }
      }
    } catch (e) {
      result['failures'].add('FAIL: JSON parsing error: $e');
    }

    return result;
  }
}

// ============================================================================
// TEST CASES
// ============================================================================

class GroqPromptTest {
  final GroqClient groq;
  final NarrativeThinkerRubric rubric = NarrativeThinkerRubric();

  int passed = 0;
  int failed = 0;

  GroqPromptTest(this.groq);

  Future<void> runTest(
    String name,
    String testCase,
    String systemPrompt,
    String userPrompt,
  ) async {
    print('\n${'─' * 70}');
    print('TEST: $name');
    print('${'─' * 70}');

    try {
      print('Calling Groq API...');
      final response = await groq.callChat(
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      );

      print('\nGroq Response:');
      print('```');
      print(response);
      print('```\n');

      // Validate
      final result = rubric.validateExtraction(response, testCase);

      print('Rubric Validation:');
      print('  ✓ Valid JSON: ${result['valid_json']}');
      print('  ✓ Format correct: ${result['format_correct']}');
      print('  ✓ Dedup working: ${result['dedup_working']}');
      print('  ✓ Scope correct: ${result['scope_correct']}');
      print('  Entries extracted: ${result['entries_count']}');

      if ((result['failures'] as List).isNotEmpty) {
        print('\nFailures:');
        for (final failure in result['failures']) {
          print('  ✗ $failure');
        }
        failed++;
        print('\n✗ FAIL');
      } else {
        passed++;
        print('\n✓ PASS');
      }
    } catch (e) {
      failed++;
      print('\n✗ EXCEPTION: $e\n');
    }
  }

  void summary() {
    print('\n${'═' * 70}');
    print('SUMMARY: $passed passed, $failed failed');
    print('${'═' * 70}\n');
  }
}

// ============================================================================
// MAIN
// ============================================================================

Future<void> main() async {
  final apiKey = Platform.environment['GROQ_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    print('Error: GROQ_API_KEY not set');
    print('Run with: GROQ_API_KEY=your-key dart test/groq_prompt_test.dart');
    exit(1);
  }

  print('\n${'═' * 70}');
  print('GROQ PROMPT TEST - Real API Calls');
  print('${'═' * 70}');

  final groq = GroqClient(apiKey);
  final tester = GroqPromptTest(groq);

  final systemPrompt = '''You are the system's self-model extractor. Your job is to identify new insights about the user's identity, goals, and reasoning from conversation.

CRITICAL RULES:
1. Extract NEW narrative entries ONLY. Skip if redundant with existing narratives.
2. Format EXACTLY: "[Atomic idea]. Because [reasoning]."
3. Identify entry type: 'learning', 'project', or 'exploration'
4. Assign scope: 'session' for current conversation, 'day'/'project'/'life' only when clear
5. Return VALID JSON array ONLY. No markdown, no explanations.
6. Return empty array [] if nothing new.

RESPONSE FORMAT:
[
  {
    "content": "[idea]. Because [reason].",
    "scope": "session|day|project|life",
    "type": "learning|project|exploration"
  }
]
''';

  // TEST 1: Extract learning
  await tester.runTest(
    'Extract Learning Insight',
    'learning',
    systemPrompt,
    'I want to learn Rust because it teaches memory safety and prevents entire classes of bugs.',
  );

  // TEST 2: Deduplication
  // Note: This test manually includes previous entries context
  final dupSystemPrompt = systemPrompt +
      '''

EXISTING NARRATIVES (for deduplication):
- "Rust teaches memory safety. Because explicit control prevents bugs."

Only extract NEW entries that are NOT already captured.''';

  await tester.runTest(
    'Deduplication - Skip Similar Entry',
    'dedup',
    dupSystemPrompt,
    'I think Rust is really good because it handles memory safety well. I want to learn it.',
  );

  // TEST 3: Project extraction
  await tester.runTest(
    'Extract Project (should use session scope, not project)',
    'project',
    systemPrompt,
    'I\'m building a chatbot that learns from user feedback. The system needs to handle corrections gracefully.',
  );

  tester.summary();
}
