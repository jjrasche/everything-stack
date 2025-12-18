/// Intent Engine - Translates user utterances into structured tool invocations
///
/// Pure classification: utterance + context → Intent objects
/// Does NOT execute. ToolExecutor handles execution.
/// ConversationService orchestrates the flow.
///
/// Workflow:
/// 1. Receive utterance + conversation history + entities
/// 2. Build prompt with tool registry and instructions
/// 3. Single LLM call to Claude (streaming)
/// 4. Parse JSON response to Intent objects
/// 5. Validate all tools exist in registry
/// 6. Return {conversational_response, intents, turn_complete}
///
/// JSON Output Format:
/// {
///   "conversational_response": "string",
///   "intents": [
///     {
///       "tool": "string",
///       "slots": {"slotName": value, ...},
///       "reasoning": "string",
///       "slot_confidence": {"slotName": 0.0-1.0, ...},
///       "execution_order": int
///     }
///   ],
///   "turn_complete": true
/// }

import 'dart:convert';
import 'package:everything_stack/services/llm_service.dart';
import 'tool_registry.dart';

export 'tool_registry.dart';

class IntentClassificationException implements Exception {
  final String message;
  final Object? cause;

  IntentClassificationException(this.message, {this.cause});

  @override
  String toString() {
    if (cause != null) {
      return 'IntentClassificationException: $message (cause: $cause)';
    }
    return 'IntentClassificationException: $message';
  }
}

class IntentEngine {
  final ToolRegistry toolRegistry;

  IntentEngine({
    required this.toolRegistry,
  });

  /// Classify user utterance into structured intents
  /// Single LLM call returns both conversational response and intent list
  Future<Map<String, dynamic>> classify({
    required String utterance,
    required List<Map<String, String>> history,
    required Map<String, dynamic> entities,
  }) async {
    try {
      // 1. Build system prompt with tool registry
      final systemPrompt = _buildSystemPrompt();

      // 2. Convert history to LLMService Message format
      final messages = history
          .map((h) => Message(
                role: h['role'] ?? 'user',
                content: h['text'] ?? '',
              ))
          .toList();

      // 3. Build user message with utterance + entity context
      final userMessage = _buildUserMessage(utterance, entities);

      // 4. Call Claude with streaming response
      final response = await _callLLMStreaming(
        systemPrompt: systemPrompt,
        history: messages,
        userMessage: userMessage,
      );

      // 5. Parse JSON response
      final json = _parseJsonResponse(response);

      // 6. Extract and validate intents
      final intents = _validateAndExtractIntents(json['intents'] as List? ?? []);

      // 7. Return structured response
      return {
        'conversational_response': json['conversational_response'] ?? '',
        'intents': intents.map((i) => i.toJson()).toList(),
        'turn_complete': json['turn_complete'] ?? true,
      };
    } catch (e) {
      throw IntentClassificationException('Failed to classify utterance', cause: e);
    }
  }

  /// Build system prompt with tool registry and classification instructions
  String _buildSystemPrompt() {
    final buffer = StringBuffer();

    buffer.writeln('You are an Intent Engine that translates user utterances into structured tool invocations.');
    buffer.writeln('');
    buffer.writeln('IMPORTANT: Respond ONLY with valid JSON. No explanation, no markdown, just JSON.');
    buffer.writeln('');
    buffer.writeln(toolRegistry.formatForPrompt());
    buffer.writeln('');
    buffer.writeln('For each utterance, respond with exactly this JSON structure:');
    buffer.writeln('{');
    buffer.writeln('  "conversational_response": "Natural language response to user",');
    buffer.writeln('  "intents": [');
    buffer.writeln('    {');
    buffer.writeln('      "tool": "TOOL_NAME",');
    buffer.writeln('      "slots": {"slot_name": value, ...},');
    buffer.writeln('      "reasoning": "Why this tool was selected",');
    buffer.writeln('      "slot_confidence": {"slot_name": 0.0-1.0, ...},');
    buffer.writeln('      "execution_order": 1');
    buffer.writeln('    }');
    buffer.writeln('  ],');
    buffer.writeln('  "turn_complete": true');
    buffer.writeln('}');
    buffer.writeln('');
    buffer.writeln('Rules:');
    buffer.writeln('- If utterance maps to no tool, intents is empty array');
    buffer.writeln('- slot_confidence reflects confidence in slot fill (0.0 for null, up to 1.0)');
    buffer.writeln('- Only use tools from the registry above');
    buffer.writeln('- Multiple tools can be returned (order them by execution_order)');
    buffer.writeln('- If slot is required and missing, set it to null and confidence to 0.0');

    return buffer.toString();
  }

  /// Build user message with utterance and entity context
  String _buildUserMessage(String utterance, Map<String, dynamic> entities) {
    final buffer = StringBuffer();

    buffer.writeln('User says: "$utterance"');

    if (entities.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('Available entities:');
      entities.forEach((key, values) {
        buffer.writeln('- $key: ${_formatEntityList(values)}');
      });
    }

    return buffer.toString();
  }

  /// Format entity list for prompt
  String _formatEntityList(dynamic values) {
    if (values is List) {
      return values.join(', ');
    }
    return values.toString();
  }

  /// Call LLM with streaming response and accumulate tokens
  Future<String> _callLLMStreaming({
    required String systemPrompt,
    required List<Message> history,
    required String userMessage,
  }) async {
    final buffer = StringBuffer();

    try {
      await for (final token in LLMService.instance.chat(
        systemPrompt: systemPrompt,
        history: history,
        userMessage: userMessage,
        maxTokens: 2048, // Enough for intent JSON
      )) {
        buffer.write(token);
      }
    } catch (e) {
      throw IntentClassificationException('LLM call failed', cause: e);
    }

    return buffer.toString();
  }

  /// Parse JSON response from Claude
  Map<String, dynamic> _parseJsonResponse(String response) {
    try {
      // Try to find JSON in response (in case of extra text)
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(response);
      if (jsonMatch == null) {
        throw IntentClassificationException('No JSON found in Claude response');
      }

      final jsonStr = jsonMatch.group(0)!;
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      return json;
    } catch (e) {
      throw IntentClassificationException('Failed to parse JSON from Claude response', cause: e);
    }
  }

  /// Extract and validate intents from JSON
  List<Intent> _validateAndExtractIntents(List<dynamic> intentsJson) {
    final intents = <Intent>[];

    for (final intentData in intentsJson) {
      if (intentData is! Map) {
        throw IntentClassificationException('Intent must be a map, got: $intentData');
      }

      final intent = Intent.fromJson(intentData as Map<String, dynamic>);

      // Validate tool exists in registry
      if (!toolRegistry.hasToolNamed(intent.tool)) {
        throw UnknownToolException(
          intent.tool,
          'Claude returned tool not in registry: ${intent.tool}',
        );
      }

      intents.add(intent);
    }

    return intents;
  }
}

/// Intent class - Represents a classified intent
class Intent {
  final String tool;
  final Map<String, dynamic> slots;
  final String reasoning;
  final Map<String, num> slotConfidence;
  final int executionOrder;

  Intent({
    required this.tool,
    required this.slots,
    required this.reasoning,
    required this.slotConfidence,
    required this.executionOrder,
  });

  /// Deserialize from Claude's JSON response
  factory Intent.fromJson(Map<String, dynamic> json) {
    return Intent(
      tool: json['tool'] as String,
      slots: Map<String, dynamic>.from(json['slots'] as Map),
      reasoning: json['reasoning'] as String,
      slotConfidence: Map<String, num>.from(json['slot_confidence'] as Map),
      executionOrder: json['execution_order'] as int,
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() {
    return {
      'tool': tool,
      'slots': slots,
      'reasoning': reasoning,
      'slot_confidence': slotConfidence,
      'execution_order': executionOrder,
    };
  }
}
