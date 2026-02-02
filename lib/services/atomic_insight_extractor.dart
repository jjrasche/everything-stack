/// # AtomicInsightExtractor
///
/// ## What it does
/// Continuously extracts atomic insights from conversation using Groq LLM.
/// Maintains self-model through Session/Day insights (auto-updated).
/// Handles deduplication to avoid repetitive entries.
///
/// ## Format
/// All extracted insights follow the format: "[Atomic idea]. Because [reason]."
///
/// ## Flow
/// 1. User speaks → ChatService processes
/// 2. Intent Engine classifies intent (returns intent object)
/// 3. Extractor receives: utterance + intent + chat history + previous insights
/// 4. Single Groq call: "Extract new atomic insights. Skip if redundant. Return empty if nothing new."
/// 5. Session/Day insights auto-update (live, not provisional)
/// 6. Projects/Life remain untouched until training checkpoint
///
/// ## Usage
/// ```dart
/// // Initialize with repositories
/// final extractor = AtomicInsightExtractor(
///   insightRepo: insightRepo,
///   groqService: GroqService.instance,
/// );
///
/// // On each turn: utterance + intent from Intent Engine + chat history
/// await extractor.updateFromTurn(
///   utterance: 'I want to build distributed systems',
///   intentOutput: intentObject,
///   chatHistory: [...],
///   previousInsights: previousInsights,
/// );
/// ```

import 'dart:async';
import 'dart:convert';
import '../core/logging/logger.dart';
import '../domain/atomic_insight.dart';
import '../domain/atomic_insight_repository.dart';
import 'groq_service.dart';

class AtomicInsightExtractor {
  final AtomicInsightRepository _insightRepo;
  final GroqService _groqService;
  final Logger _logger = Logger.instance;

  AtomicInsightExtractor({
    required AtomicInsightRepository insightRepo,
    required GroqService groqService,
  })  : _insightRepo = insightRepo,
        _groqService = groqService;

  /// Process a conversation turn and extract/update atomic insights.
  ///
  /// Parameters:
  /// - utterance: The user's current input (text or STT result)
  /// - intentOutput: Full intent object from Intent Engine with reasoning
  /// - chatHistory: Recent chat messages for context
  /// - previousInsights: Active insights from all scopes (for dedup)
  ///
  /// Returns: List of new AtomicInsight objects created
  /// Side effect: Saves insights to database for Session/Day scopes
  Future<List<AtomicInsight>> updateFromTurn({
    required String utterance,
    required Map<String, dynamic> intentOutput,
    required List<Map<String, dynamic>> chatHistory,
    required List<AtomicInsight> previousInsights,
  }) async {
    try {
      // Build context for Groq prompt
      final context = _buildContext(
        utterance: utterance,
        intentOutput: intentOutput,
        chatHistory: chatHistory,
        previousInsights: previousInsights,
      );

      // Single Groq call to extract new atomic insights
      final extracted = await _extractWithGroq(context);

      // Save extracted insights to database (Session and Day only)
      final saved = <AtomicInsight>[];
      for (final insight in extracted) {
        // Only auto-save Session/Day; Projects/Life require training
        if (insight.scope == 'session' || insight.scope == 'day') {
          await _insightRepo.save(insight);
          saved.add(insight);
          _logger.debug(
            'AtomicInsightExtractor: Saved ${insight.scope} insight: "${insight.content.substring(0, 50)}..."',
          );
        }
      }

      return saved;
    } catch (e, st) {
      _logger.error('AtomicInsightExtractor.updateFromTurn failed: $e', stackTrace: st);
      return [];
    }
  }

  /// Build comprehensive context for Groq extraction prompt
  String _buildContext({
    required String utterance,
    required Map<String, dynamic> intentOutput,
    required List<Map<String, dynamic>> chatHistory,
    required List<AtomicInsight> previousInsights,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('=== CURRENT UTTERANCE ===');
    buffer.writeln(utterance);
    buffer.writeln();

    buffer.writeln('=== INTENT ANALYSIS ===');
    buffer.writeln('Classification: ${intentOutput['classification'] ?? 'unknown'}');
    buffer.writeln('Confidence: ${intentOutput['confidence'] ?? 'N/A'}');
    if (intentOutput['reasoning'] != null) {
      buffer.writeln('Reasoning: ${intentOutput['reasoning']}');
    }
    buffer.writeln();

    buffer.writeln('=== RECENT CHAT HISTORY ===');
    for (final msg in chatHistory.take(10)) {
      final role = msg['role'] ?? 'unknown';
      final content = (msg['content'] ?? '').toString();
      buffer.writeln('$role: ${content.substring(0, 100)}');
    }
    buffer.writeln();

    buffer.writeln('=== EXISTING INSIGHTS (for deduplication) ===');
    if (previousInsights.isEmpty) {
      buffer.writeln('(None)');
    } else {
      for (final insight in previousInsights.take(20)) {
        buffer.writeln('- [${insight.scope}] ${insight.content.substring(0, 80)}');
      }
    }
    buffer.writeln();

    return buffer.toString();
  }

  /// Call Groq to extract new atomic insights.
  /// Handles deduplication and returns structured results.
  Future<List<AtomicInsight>> _extractWithGroq(String context) async {
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': _systemPrompt(),
      },
      {
        'role': 'user',
        'content': context,
      },
    ];

    try {
      // Stream completion from Groq
      final stream = _groqService.stream(
        messages: messages,
        model: 'llama-3.3-70b-versatile', // Llama 3.3 70B for extraction
        maxTokens: 1000,
      );

      final tokens = <String>[];
      await for (final token in stream) {
        tokens.add(token.text);
      }

      final response = tokens.join();
      return _parseResponse(response);
    } catch (e, st) {
      _logger.error('AtomicInsightExtractor Groq call failed: $e', stackTrace: st);
      return [];
    }
  }

  /// System prompt for atomic insight extraction
  String _systemPrompt() => '''You are the system's atomic insight extractor. Your job is to identify new insights about the user's identity, goals, and reasoning from conversation.

Rules:
1. Extract NEW atomic insights ONLY. Skip if redundant with existing insights.
2. Format: "[Atomic idea]. Because [reasoning]."
3. Be concise. One sentence per insight.
4. Identify insight type: 'learning', 'project', or 'exploration'.
5. Assign scope:
   - 'session': Current conversation (always Session if new)
   - 'day': Multi-conversation pattern within a day
   - 'week': Weekly themes
   - 'project': User-defined project context (ONLY if explicitly stated)
   - 'life': Identity-level patterns (ONLY if profound/core)
6. Return JSON array:
   [
     {
       "content": "[idea]. Because [reason].",
       "scope": "session|day|week|project|life",
       "type": "learning|project|exploration"
     }
   ]
7. Return empty array [] if nothing new.
8. Never invent projects or life insights. Only surface what's evident.

Example response:
[
  {
    "content": "Distributed systems enable resilience. Because single points of failure risk everything.",
    "scope": "session",
    "type": "learning"
  }
]''';

  /// Parse Groq response JSON into AtomicInsight objects
  List<AtomicInsight> _parseResponse(String response) {
    try {
      // Find JSON array in response
      final jsonMatch = RegExp(r'\[\s*\{.*\}\s*\]', dotAll: true).firstMatch(response);
      if (jsonMatch == null) {
        _logger.debug('AtomicInsightExtractor: No JSON found in response');
        return [];
      }

      final jsonStr = jsonMatch.group(0)!;
      final parsed = jsonDecode(jsonStr) as List<dynamic>;

      return parsed
          .whereType<Map<String, dynamic>>()
          .map((json) => AtomicInsight(
                content: json['content'] ?? '',
                scope: json['scope'] ?? 'session',
                type: json['type'],
              ))
          .where((insight) => insight.content.isNotEmpty)
          .toList();
    } catch (e) {
      _logger.error('AtomicInsightExtractor: Failed to parse Groq response: $e');
      return [];
    }
  }
}
