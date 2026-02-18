import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../../domain/atomic_insight.dart';
import '../../domain/atomic_insight_repository.dart';
import '../../core/debug/debug_introspectable.dart';
import '../prompt/prompt_registry.dart';
import '../inference_service.dart';

class AtomicInsightExtractor with DebugIntrospectable {
  static const String _defaultModel = 'llama-3.1-8b-instant';

  /// Cosine similarity threshold for deduplication (empirically tuned)
  static const double _dedupThreshold = 0.7;

  /// Max existing insights shown in dedup context to keep prompt size bounded
  static const int _dedupContextLimit = 30;

  static const int _contentPreviewLength = 100;

  final AtomicInsightRepository _insightRepo;
  final InferenceService _inferenceService;
  PromptRegistry? _promptRegistry;
  final String _extractionModel;

  int _extractionCount = 0;
  int _insightsSaved = 0;
  int _duplicatesSkipped = 0;
  DateTime? _lastExtractionAt;

  AtomicInsightExtractor({
    required AtomicInsightRepository insightRepo,
    required InferenceService inferenceService,
    PromptRegistry? promptRegistry,
    String? model,
  })  : _insightRepo = insightRepo,
        _inferenceService = inferenceService,
        _promptRegistry = promptRegistry,
        _extractionModel = model ?? _defaultModel;

  set promptRegistry(PromptRegistry registry) =>
      _promptRegistry = registry;

  /// Process a live conversation turn and extract/update atomic insights.
  Future<List<AtomicInsight>> updateFromTurn({
    required String utterance,
    required Map<String, dynamic> intentOutput,
    required List<Map<String, dynamic>> chatHistory,
    required List<AtomicInsight> previousInsights,
  }) async {
    try {
      final context = _buildLiveContext(
        utterance: utterance,
        intentOutput: intentOutput,
        chatHistory: chatHistory,
        previousInsights: previousInsights,
      );

      final extracted = await _extract(context);
      return _deduplicateAndSave(extracted);
    } catch (e, st) {
      debugPrint('AtomicInsightExtractor.updateFromTurn failed: $e\n$st');
      return [];
    }
  }

  /// Extract insights from imported conversation history in batches.
  ///
  /// [overridePrompt] allows testing a candidate prompt without changing
  /// the registry — fixes the bug where both baseline and candidate
  /// extractions used the same registry prompt.
  Future<List<AtomicInsight>> extractFromConversation({
    required List<Map<String, dynamic>> turns,
    int batchSize = 5,
    String? overridePrompt,
  }) async {
    final allInsights = <AtomicInsight>[];

    for (var i = 0; i < turns.length; i += batchSize) {
      final batch = turns.sublist(
        i,
        (i + batchSize).clamp(0, turns.length),
      );

      final context = _buildBatchContext(
        batch: batch,
        batchIndex: i ~/ batchSize,
        totalTurns: turns.length,
        previousInsights: allInsights,
      );

      try {
        final extracted = await _extract(context, overridePrompt: overridePrompt);
        final saved = await _deduplicateAndSave(extracted);
        allInsights.addAll(saved);
      } catch (e, st) {
        debugPrint(
          'AtomicInsightExtractor: Batch ${i ~/ batchSize} failed: $e\n$st',
        );
      }
    }

    return allInsights;
  }

  String _buildLiveContext({
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
      final preview = content.length > 200 ? content.substring(0, 200) : content;
      buffer.writeln('$role: $preview');
    }
    buffer.writeln();

    _appendExistingInsights(buffer, previousInsights);

    return buffer.toString();
  }

  String _buildBatchContext({
    required List<Map<String, dynamic>> batch,
    required int batchIndex,
    required int totalTurns,
    required List<AtomicInsight> previousInsights,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('=== CONVERSATION BATCH ${batchIndex + 1} ===');
    buffer.writeln('(Turns ${batchIndex * batch.length + 1}-${batchIndex * batch.length + batch.length} of $totalTurns)');
    buffer.writeln();

    for (var i = 0; i < batch.length; i++) {
      final turn = batch[i];
      final prompt = turn['prompt'] as String? ?? '';
      final response = turn['response'] as String? ?? '';

      buffer.writeln('--- Turn ${batchIndex * batch.length + i + 1} ---');
      buffer.writeln('Human: $prompt');
      buffer.writeln();
      final responsePreview = response.length > 500
          ? '${response.substring(0, 500)}...'
          : response;
      buffer.writeln('Assistant: $responsePreview');
      buffer.writeln();
    }

    _appendExistingInsights(buffer, previousInsights);

    return buffer.toString();
  }

  void _appendExistingInsights(
    StringBuffer buffer,
    List<AtomicInsight> insights,
  ) {
    buffer.writeln('=== EXISTING INSIGHTS (for deduplication) ===');
    if (insights.isEmpty) {
      buffer.writeln('(None)');
    } else {
      for (final insight in insights.take(_dedupContextLimit)) {
        final preview = insight.content.length > _contentPreviewLength
            ? insight.content.substring(0, _contentPreviewLength)
            : insight.content;
        buffer.writeln('- [${insight.scope}] $preview');
      }
    }
    buffer.writeln();
  }

  /// Call LLM via streaming to extract new atomic insights.
  ///
  /// [overridePrompt] bypasses the registry when testing candidate prompts.
  Future<List<AtomicInsight>> _extract(
    String context, {
    String? overridePrompt,
  }) async {
    final prompt = overridePrompt ?? await _getSystemPrompt();
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': prompt},
      {'role': 'user', 'content': context},
    ];

    final tokens = <String>[];
    await for (final token in _inferenceService.chatStream(
      model: _extractionModel,
      messages: messages,
      temperature: 0.3,
      maxTokens: 1000,
    )) {
      tokens.add(token);
    }

    _extractionCount++;
    _lastExtractionAt = DateTime.now();

    final response = tokens.join();
    return _parseResponse(response);
  }

  Future<List<AtomicInsight>> _deduplicateAndSave(
    List<AtomicInsight> extracted,
  ) async {
    final saved = <AtomicInsight>[];

    for (final insight in extracted) {
      final similar = await _insightRepo.findRelevant(
        insight.content,
        topK: 3,
        threshold: _dedupThreshold,
      );

      if (similar.isNotEmpty) {
        _duplicatesSkipped++;
        debugPrint(
          'AtomicInsightExtractor: Skipped duplicate '
          '(${(similar.first).content.length > 50 ? similar.first.content.substring(0, 50) : similar.first.content}...)',
        );
        continue;
      }

      // Only persist session scopes — project/life require consolidation
      // logic that doesn't exist yet (see CLAUDE.md Future Considerations)
      if (insight.scope == 'session') {
        await _insightRepo.save(insight);
        saved.add(insight);
        _insightsSaved++;
        debugPrint(
          'AtomicInsightExtractor: Saved ${insight.scope} insight: '
          '"${insight.content.length > 60 ? insight.content.substring(0, 60) : insight.content}..."',
        );
      }
    }

    return saved;
  }

  Future<String> _getSystemPrompt() async {
    if (_promptRegistry != null) {
      return _promptRegistry!.getActivePrompt();
    }
    return _defaultSystemPrompt;
  }

  /// Stage 1: Select which segments of the episodic source contain extractable
  /// knowledge. Outputs candidate descriptions with evidence spans and skip
  /// annotations. Independently tunable from Stage 2 formatting.
  static const String _stage1SelectionPrompt =
      '''You identify extractable knowledge in episodic input. The source may be a conversation, article, transcript, or any text.

Your job: find segments that contain decisions, designs, domain knowledge, constraints, hypotheses, preferences, or tradeoffs — anything that would materially inform future interactions or decisions.

Rules:
1. SKIP segments that are trivial, ephemeral, or generic. SKIP segments redundant with existing insights shown.
2. For each selected segment, quote the exact evidence span from the source.
3. For each selected segment, write a brief candidate description (what knowledge it contains).
4. Also output skipped segments with a reason (ephemeral, trivial, generic, already_known).
5. One knowledge unit per candidate. If a segment contains two ideas, produce two candidates.
6. Never fabricate — every candidate must trace to a quoted span in the source.

Return JSON:
{
  "selected": [
    {
      "evidenceSpan": "quoted text from source",
      "candidateDescription": "brief description of the knowledge unit",
      "isDurable": true
    }
  ],
  "skipped": [
    {
      "evidenceSpan": "quoted text that was considered but rejected",
      "reason": "ephemeral|trivial|generic|already_known"
    }
  ]
}

Return {"selected": [], "skipped": []} if nothing extractable.''';

  /// Stage 2: Format selected candidates into self-contained atomic insights
  /// with scope, type, and decontextualized content. Independently tunable
  /// from Stage 1 selection. May combine related candidates or split compound ones.
  static const String _stage2FormattingPrompt =
      '''You transform raw knowledge candidates into self-contained atomic insights. Each candidate comes with an evidence span from the source.

Rules:
1. Format: "[Atomic idea]. Because [reasoning]." Both parts required.
2. Decontextualize: replace pronouns, resolve references, expand abbreviations so the insight is understandable WITHOUT the source.
3. One knowledge unit per insight. If a candidate contains two ideas, split into two insights. If two candidates are tightly related, you may combine them into one insight.
4. Assign scope:
   - 'session': This episode only
   - 'project': Named project context (ONLY if project is explicitly named)
   - 'life': Identity-level pattern (ONLY if profound and repeated)
5. Identify type: 'learning', 'project', or 'exploration'.
6. Preserve the evidence span from the candidate.

Return JSON array:
[
  {
    "content": "[decontextualized idea]. Because [reason].",
    "evidenceSpan": "quoted text from source supporting this insight",
    "scope": "session|project|life",
    "type": "learning|project|exploration"
  }
]

Return empty array [] if no candidates provided.''';

  /// Combined single-pass prompt for production use where latency matters.
  /// Stage 1 + Stage 2 fused. Used when PromptRegistry has no override.
  static const String _defaultSystemPrompt =
      '''You extract atomic knowledge units from episodic input. The source may be a conversation, article, transcript, or any text. Extract decisions, designs, domain knowledge, constraints, hypotheses, preferences, and tradeoffs — everything intellectually produced or engaged with.

Rules:
1. Extract NEW atomic insights ONLY. Skip if redundant with existing insights shown.
2. Format: "[Atomic idea]. Because [reasoning]."
3. One knowledge unit per insight. Two ideas = two insights.
4. Only extract knowledge that would materially inform future interactions or decisions. Skip trivial, ephemeral, or generic observations.
5. Include an evidence span: a quoted substring from the source that supports the insight.
6. Identify insight type: 'learning', 'project', or 'exploration'.
7. Assign scope:
   - 'session': This episode only
   - 'project': Named project context (ONLY if project is explicitly named)
   - 'life': Identity-level pattern (ONLY if profound and repeated)
8. Return JSON array:
   [
     {
       "content": "[idea]. Because [reason].",
       "evidenceSpan": "quoted text from source supporting this insight",
       "scope": "session|project|life",
       "type": "learning|project|exploration"
     }
   ]
9. Return empty array [] if nothing new.
10. Never fabricate knowledge not present in the source.

Example response:
[
  {
    "content": "Data sovereignty is a core architectural constraint for the AI system. Because the design repeatedly emphasizes keeping data local and under user control.",
    "evidenceSpan": "keeping data local and under user control",
    "scope": "session",
    "type": "project"
  }
]''';

  static String get defaultSystemPrompt => _defaultSystemPrompt;
  static String get stage1SelectionPrompt => _stage1SelectionPrompt;
  static String get stage2FormattingPrompt => _stage2FormattingPrompt;

  List<AtomicInsight> _parseResponse(String response) {
    try {
      final jsonMatch =
          RegExp(r'\[\s*\{.*\}\s*\]', dotAll: true).firstMatch(response);
      if (jsonMatch == null) {
        if (RegExp(r'\[\s*\]').hasMatch(response)) return [];
        debugPrint('AtomicInsightExtractor: No JSON found in response');
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
                evidenceSpan: json['evidenceSpan'] as String?,
              ))
          .where((insight) => insight.content.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('AtomicInsightExtractor: Failed to parse response: $e');
      return [];
    }
  }

  // ============ DebugIntrospectable ============

  @override
  String get debugName => 'extractor';

  @override
  Map<String, dynamic> getDebugState() => {
        'extractionCount': _extractionCount,
        'insightsSaved': _insightsSaved,
        'duplicatesSkipped': _duplicatesSkipped,
        'lastExtractionAt': _lastExtractionAt?.toIso8601String(),
      };

  @override
  Map<String, DebugAction> getDebugActions() => {
        'getStats': DebugAction(
          description: 'Get extraction statistics',
          handler: (params) async {
            final allInsights = await _insightRepo.findAll();
            final withEmbeddings =
                allInsights.where((i) => i.embedding != null).length;
            final byScope = <String, int>{};
            for (final insight in allInsights) {
              byScope[insight.scope] = (byScope[insight.scope] ?? 0) + 1;
            }
            return {
              'totalInsights': allInsights.length,
              'withEmbeddings': withEmbeddings,
              'byScope': byScope,
              'extractionCount': _extractionCount,
              'insightsSaved': _insightsSaved,
              'duplicatesSkipped': _duplicatesSkipped,
              'lastExtractionAt': _lastExtractionAt?.toIso8601String(),
            };
          },
        ),
        'extractSample': DebugAction(
          description: 'Extract insights from the most recent imported conversation',
          mutates: true,
          handler: (params) async {
            return {'error': 'Use extractor.extractFromConversation with a conversation UUID'};
          },
        ),
      };
}
