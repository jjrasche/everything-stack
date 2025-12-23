/// # NarrativeThinker
///
/// ## What it does
/// Continuously extracts narrative insights from conversation using Groq.
/// Maintains self-model through Session/Day narratives (auto-updated).
/// Handles deduplication to avoid repetitive entries.
///
/// ## Flow
/// 1. User speaks → LLMService processes
/// 2. Intent Engine classifies intent (returns intent object)
/// 3. Thinker receives: utterance + intent + chat history + previous narratives
/// 4. Single Groq call: "Extract new narrative entries. Skip if redundant. Return empty if nothing new."
/// 5. Session/Day narratives auto-update (live, not provisional)
/// 6. Projects/Life remain untouched until training checkpoint
///
/// ## Usage
/// ```dart
/// // Initialize with repositories
/// final thinker = NarrativeThinker(
///   narrativeRepo: narrativeRepo,
///   groqService: LLMService.instance,
/// );
///
/// // On each turn: utterance + intent from Intent Engine + chat history
/// await thinker.updateFromTurn(
///   utterance: 'I want to build distributed systems',
///   intentOutput: intentObject,
///   chatHistory: [...],
///   previousNarratives: previousEntries,
/// );
/// ```

import 'dart:async';
import 'dart:convert';

import '../domain/narrative_entry.dart';
import '../domain/narrative_repository.dart';
import 'llm_service.dart';

class NarrativeThinker {
  final NarrativeRepository _narrativeRepo;
  final LLMService _groqService;

  NarrativeThinker({
    required NarrativeRepository narrativeRepo,
    required LLMService groqService,
  })  : _narrativeRepo = narrativeRepo,
        _groqService = groqService;

  /// Process a conversation turn and extract/update narratives.
  ///
  /// Parameters:
  /// - utterance: The user's current input (text or STT result)
  /// - intentOutput: Full intent object from Intent Engine with reasoning
  /// - chatHistory: Recent chat messages for context
  /// - previousNarratives: Active narratives from all scopes (for dedup)
  ///
  /// Returns: List of new NarrativeEntry objects created
  /// Side effect: Saves entries to database for Session/Day scopes
  Future<List<NarrativeEntry>> updateFromTurn({
    required String utterance,
    required Map<String, dynamic> intentOutput,
    required List<Map<String, dynamic>> chatHistory,
    required List<NarrativeEntry> previousNarratives,
  }) async {
    try {
      // Build context for Groq prompt
      final context = _buildContext(
        utterance: utterance,
        intentOutput: intentOutput,
        chatHistory: chatHistory,
        previousNarratives: previousNarratives,
      );

      // Single Groq call to extract new narrative entries
      final extracted = await _extractWithGroq(context);

      // Save extracted entries to database (Session and Day only)
      final saved = <NarrativeEntry>[];
      for (final entry in extracted) {
        // Only auto-save Session/Day; Projects/Life require training
        if (entry.scope == 'session' || entry.scope == 'day') {
          await _narrativeRepo.save(entry);
          saved.add(entry);
        }
      }

      return saved;
    } catch (e) {
      return [];
    }
  }

  /// Build comprehensive context for Groq extraction prompt
  String _buildContext({
    required String utterance,
    required Map<String, dynamic> intentOutput,
    required List<Map<String, dynamic>> chatHistory,
    required List<NarrativeEntry> previousNarratives,
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

    buffer.writeln('=== EXISTING NARRATIVES (for deduplication) ===');
    if (previousNarratives.isEmpty) {
      buffer.writeln('(None)');
    } else {
      for (final entry in previousNarratives.take(20)) {
        buffer.writeln('- [${entry.scope}] ${entry.content.substring(0, 80)}');
      }
    }
    buffer.writeln();

    return buffer.toString();
  }

  /// Call LLM to extract new narrative entries.
  /// Handles deduplication and returns structured results.
  Future<List<NarrativeEntry>> _extractWithGroq(String context) async {
    try {
      // Stream completion from LLM
      final stream = _groqService.chat(
        history: [], // No previous messages in this flow
        userMessage: context,
        systemPrompt: _systemPrompt(),
      );

      final tokens = <String>[];
      await for (final token in stream) {
        tokens.add(token);
      }

      final response = tokens.join();
      return _parseResponse(response);
    } catch (e) {
      return [];
    }
  }

  /// System prompt for narrative extraction
  String _systemPrompt() => '''You are the system's self-model extractor. Your job is to identify new insights about the user's identity, goals, and reasoning from conversation.

Rules:
1. Extract NEW narrative entries ONLY. Skip if redundant with existing narratives.
2. Format: "[Atomic idea]. Because [reasoning]."
3. Be concise. One sentence per entry.
4. Identify entry type: 'learning', 'project', or 'exploration'.
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

  /// Parse Groq response JSON into NarrativeEntry objects
  List<NarrativeEntry> _parseResponse(String response) {
    try {
      // Find JSON array in response
      final jsonMatch = RegExp(r'\[\s*\{.*\}\s*\]', dotAll: true).firstMatch(response);
      if (jsonMatch == null) {
        return [];
      }

      final jsonStr = jsonMatch.group(0)!;
      final parsed = jsonDecode(jsonStr) as List<dynamic>;

      return parsed
          .whereType<Map<String, dynamic>>()
          .map((json) => NarrativeEntry(
                content: json['content'] ?? '',
                scope: json['scope'] ?? 'session',
                type: json['type'],
              ))
          .where((entry) => entry.content.isNotEmpty)
          .toList();
    } catch (e) {
      return [];
    }
  }
}
