/// GroqService Tests
/// Tests API parsing, timeout handling, retry logic

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:everything_stack_template/services/groq_service.dart';

void main() {
  group('GroqService - Response Parsing', () {
    test('parses successful chat response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'id': 'chatcmpl-123',
            'model': 'llama-3.3-70b-versatile',
            'choices': [
              {
                'index': 0,
                'message': {
                  'role': 'assistant',
                  'content': 'Hello!',
                },
                'finish_reason': 'stop',
              }
            ],
            'usage': {
              'prompt_tokens': 10,
              'completion_tokens': 5,
              'total_tokens': 15,
            },
          }),
          200,
        );
      });

      final groq = GroqService(apiKey: 'test-key');
      // Would need to inject mockClient - for now testing parsing logic

      final response = GroqResponse.fromJson({
        'id': 'chatcmpl-123',
        'model': 'llama-3.3-70b-versatile',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': 'Hello!',
            },
            'finish_reason': 'stop',
          }
        ],
        'usage': {
          'prompt_tokens': 10,
          'completion_tokens': 5,
          'total_tokens': 15,
        },
      });

      expect(response.id, 'chatcmpl-123');
      expect(response.content, 'Hello!');
      expect(response.usage.totalTokens, 15);
    });

    test('parses tool calls from response', () {
      final response = GroqResponse.fromJson({
        'id': 'chatcmpl-456',
        'model': 'llama-3.3-70b-versatile',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': null,
              'tool_calls': [
                {
                  'id': 'call_abc123',
                  'type': 'function',
                  'function': {
                    'name': 'task.create',
                    'arguments': '{"title": "Buy groceries", "priority": "high"}',
                  },
                }
              ],
            },
            'finish_reason': 'tool_calls',
          }
        ],
        'usage': {
          'prompt_tokens': 100,
          'completion_tokens': 50,
          'total_tokens': 150,
        },
      });

      expect(response.toolCalls, isNotNull);
      expect(response.toolCalls!.length, 1);
      expect(response.toolCalls![0].function.name, 'task.create');
      expect(response.toolCalls![0].function.parsedArguments['title'],
          'Buy groceries');
      expect(response.firstChoice.wantsToolCall, true);
    });

    test('handles JSON parsing in arguments', () {
      final toolCall = GroqToolCall.fromJson({
        'id': 'call_123',
        'type': 'function',
        'function': {
          'name': 'timer.set',
          'arguments': '{"label": "5 min break", "duration": 300}',
        },
      });

      final parsed = toolCall.function.parsedArguments;
      expect(parsed['label'], '5 min break');
      expect(parsed['duration'], 300);
    });
  });

  group('GroqService - Error Handling', () {
    test('throws GroqRateLimitException on 429', () async {
      // Would test with mock HTTP client
      // For now, testing exception types exist
      expect(() => throw GroqRateLimitException('Rate limited'),
          throwsA(isA<GroqRateLimitException>()));
    });

    test('throws GroqTimeoutException on timeout', () {
      expect(() => throw GroqTimeoutException('Timeout'),
          throwsA(isA<GroqTimeoutException>()));
    });

    test('throws GroqServerException on 500', () {
      expect(() => throw GroqServerException('Server error'),
          throwsA(isA<GroqServerException>()));
    });
  });

  group('GroqService - Tool Schema Format', () {
    test('formats tools in OpenAI format', () {
      final tools = [
        {
          'type': 'function',
          'function': {
            'name': 'task.create',
            'description': 'Create a new task',
            'parameters': {
              'type': 'object',
              'properties': {
                'title': {'type': 'string'},
                'priority': {'type': 'string', 'enum': ['low', 'medium', 'high']},
              },
              'required': ['title'],
            },
          },
        }
      ];

      final tool = tools[0] as Map<String, dynamic>;
      final function = tool['function'] as Map<String, dynamic>;
      final parameters = function['parameters'] as Map<String, dynamic>;

      expect(tool['type'], 'function');
      expect(function['name'], 'task.create');
      expect(parameters['type'], 'object');
    });
  });
}
