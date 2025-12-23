/// # NarrativeCheckpoint
///
/// ## What it does
/// Manages training checkpoints where user reviews and refines narratives.
/// Triggers at time boundaries (midnight, end of week) or explicit action.
/// Shows card-based deltas, handles conversational editing for Projects/Life.
///
/// ## Training Flow
/// 1. Checkpoint triggered (time or manual)
/// 2. Display current Session/Day as cards (auto-updated, live)
/// 3. Ask user conversationally to refine Project/Life (AI-driven, not picking lists)
/// 4. Record deltas: what changed, promoted, removed
/// 5. Trainer observes deltas, learns from corrections
///
/// ## Usage
/// ```dart
/// final checkpoint = NarrativeCheckpoint(
///   narrativeRepo: narrativeRepo,
///   narrativeRetriever: retriever,
///   groqService: groqService,
/// );
///
/// // Trigger training at boundary
/// final deltas = await checkpoint.train();
/// // Returns: {added: [...], removed: [...], promoted: [...]}
/// ```

import 'dart:async';
import 'dart:convert';

import '../domain/narrative_entry.dart';
import '../domain/narrative_repository.dart';
import 'narrative_retriever.dart';
import 'llm_service.dart';

/// Represents changes made to narratives during training
class NarrativeDelta {
  final List<NarrativeEntry> added;
  final List<NarrativeEntry> removed;
  final List<(NarrativeEntry from, NarrativeEntry to)> promoted;

  NarrativeDelta({
    required this.added,
    required this.removed,
    required this.promoted,
  });

  bool get hasChanges => added.isNotEmpty || removed.isNotEmpty || promoted.isNotEmpty;
}

class NarrativeCheckpoint {
  final NarrativeRepository _narrativeRepo;
  final NarrativeRetriever _retriever;
  final LLMService _groqService;

  NarrativeCheckpoint({
    required NarrativeRepository narrativeRepo,
    required NarrativeRetriever retriever,
    required LLMService groqService,
  })  : _narrativeRepo = narrativeRepo,
        _retriever = retriever,
        _groqService = groqService;

  /// Run training checkpoint with user interaction.
  ///
  /// Returns: NarrativeDelta with changes made during training
  Future<NarrativeDelta> train({
    bool includeProjectsAndLife = true,
  }) async {
    try {
      final delta = NarrativeDelta(
        added: [],
        removed: [],
        promoted: [],
      );

      // Phase 1: Show Session/Day narratives (auto-updated, live)
      // User can remove entries that feel noisy
      final sessionEntries = await _retriever.findByScope('session');
      final dayEntries = await _retriever.findByScope('day');


      // Simulate user review of Session/Day (in real UI, this is interactive)
      final (sessionRemoved, sessionKept) =
          await _reviewAndFilter(sessionEntries, 'Session');
      delta.removed.addAll(sessionRemoved);

      final (dayRemoved, dayKept) = await _reviewAndFilter(dayEntries, 'Day');
      delta.removed.addAll(dayRemoved);

      // Phase 2: Conversational refinement for Projects/Life
      if (includeProjectsAndLife) {
        final refinements = await _refineProjectsAndLife(
          sessionKept,
          dayKept,
        );
        delta.added.addAll(refinements);
      }

      return delta;
    } catch (e) {
      return NarrativeDelta(added: [], removed: [], promoted: []);
    }
  }

  /// Present scope narrative as card and let user filter.
  /// Returns: (removed entries, kept entries)
  Future<(List<NarrativeEntry>, List<NarrativeEntry>)> _reviewAndFilter(
    List<NarrativeEntry> entries,
    String scopeName,
  ) async {
    if (entries.isEmpty) {
      return const (<NarrativeEntry>[], <NarrativeEntry>[]);
    }

    // In real implementation, this displays a UI card with entries
    // For now, simulate: remove entries marked as "noise"
    final removed = <NarrativeEntry>[];
    final kept = <NarrativeEntry>[];

    for (final entry in entries) {
      // Simulate some entries being marked for removal
      // In real UI, user explicitly removes via checkbox/swipe
      if (_shouldFilter(entry)) {
        removed.add(entry);
        await _narrativeRepo.archive(entry.uuid);
      } else {
        kept.add(entry);
      }
    }

    return (removed, kept);
  }

  /// Use Groq to drive conversational refinement for Projects/Life.
  /// AI suggests project/life themes from session, user confirms/edits via chat.
  Future<List<NarrativeEntry>> _refineProjectsAndLife(
    List<NarrativeEntry> sessionEntries,
    List<NarrativeEntry> dayEntries,
  ) async {
    final added = <NarrativeEntry>[];

    // Build context from session/day
    final context = StringBuffer();
    context.writeln('Session narratives:');
    for (final e in sessionEntries) {
      context.writeln('  • ${e.content}');
    }
    context.writeln();
    context.writeln('Day narratives:');
    for (final e in dayEntries) {
      context.writeln('  • ${e.content}');
    }

    // Groq generates suggestions for project/life themes
    final suggestions = await _generateProjectLifeSuggestions(context.toString());

    // In real implementation, suggestions appear as conversational prompt
    // User confirms/edits via chat (not picking from list)
    // For now, auto-save suggestions as-is (in real UI, requires user confirmation)
    for (final suggestion in suggestions) {
      await _narrativeRepo.save(suggestion);
      added.add(suggestion);
    }

    return added;
  }

  /// Ask Groq to suggest project/life narratives from session/day context
  Future<List<NarrativeEntry>> _generateProjectLifeSuggestions(
    String context,
  ) async {
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': '''You are helping the user identify deeper project and life narratives.
Based on their session and day narratives, suggest any emerging projects or life identity patterns.

Format: Return JSON array with suggested narratives.
Only suggest if evident from context.
Return empty [] if nothing new.

Rules:
- Projects: Multi-turn endeavors (e.g., "Building X", "Learning Y")
- Life: Core identity/values (e.g., "Decentralized systems matter")
- Be conservative. Only surface what's clear.

Response format:
[
  {
    "content": "[idea]. Because [reason].",
    "scope": "project|life",
    "type": "learning|project|exploration"
  }
]''',
      },
      {
        'role': 'user',
        'content': context,
      },
    ];

    try {
      // Stream completion from LLM
      final systemPrompt = messages.first['content'] as String;
      final userMessage = messages.last['content'] as String;

      final stream = _groqService.chat(
        history: [],
        userMessage: userMessage,
        systemPrompt: systemPrompt,
      );

      final tokens = <String>[];
      await for (final token in stream) {
        tokens.add(token);
      }

      final response = tokens.join();
      return _parseProjectLifeResponse(response);
    } catch (e) {
      return [];
    }
  }

  /// Parse Groq response into NarrativeEntry objects (Projects/Life only)
  List<NarrativeEntry> _parseProjectLifeResponse(String response) {
    try {
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
                scope: json['scope'] ?? 'project',
                type: json['type'],
              ))
          .where((entry) =>
              entry.content.isNotEmpty &&
              (entry.scope == 'project' || entry.scope == 'life'))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Simple filter: mark entries with generic/obvious statements as noise
  bool _shouldFilter(NarrativeEntry entry) {
    final content = entry.content.toLowerCase();
    final noisePatterns = [
      'talking about', 'discussed', 'mentioned', 'said',
      'in the conversation', 'during this chat',
    ];

    return noisePatterns.any((pattern) => content.contains(pattern));
  }
}
