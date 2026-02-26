import 'dart:convert' show jsonDecode;

import '../../../domain/proposition.dart';
import '../../types/chat_client.dart';
import '../../types/message.dart';
import '../encoder_stage.dart';
import '../encoder_trace.dart';
import '../working_memory_service.dart';

class DecontextualizeInput {
  final List<ConceptSpan> extractSpans;
  final List<Sentence> sentences;
  final WorkingMemoryService workingMemory;
  final String sourceTurnId;
  final String sourceEpisodeId;

  DecontextualizeInput({
    required this.extractSpans,
    required this.sentences,
    required this.workingMemory,
    required this.sourceTurnId,
    required this.sourceEpisodeId,
  });
}

class DecontextualizeResult {
  final List<Proposition> propositions;
  final DecontextualizeTrace trace;

  DecontextualizeResult({required this.propositions, required this.trace});
}

/// Per-span decontextualization into self-contained propositions.
/// Phase 1: Groq LLM. Phase 3: T5-3B fine-tuned.
class DecontextualizeStage
    implements EncoderStage<DecontextualizeInput, DecontextualizeResult> {
  final ChatClient _chatClient;

  DecontextualizeStage({required ChatClient chatClient})
      : _chatClient = chatClient;

  @override
  String get stageName => 'decontextualize';

  @override
  Future<DecontextualizeResult> process(DecontextualizeInput input) async {
    final stopwatch = Stopwatch()..start();
    final allPropositions = <Proposition>[];
    final spanTraces = <DecontextualizeSpanTrace>[];

    for (final span in input.extractSpans) {
      final result = await _decontextualizeSpan(
        span,
        input.sentences,
        input.workingMemory,
        input.sourceTurnId,
        input.sourceEpisodeId,
      );
      allPropositions.addAll(result.propositions);
      spanTraces.add(result.trace);
    }

    stopwatch.stop();

    return DecontextualizeResult(
      propositions: allPropositions,
      trace: DecontextualizeTrace(
        spans: spanTraces,
        totalLatencyMs: stopwatch.elapsedMilliseconds,
      ),
    );
  }

  /// Also callable from dedup stage for rewrite.
  Future<List<Proposition>> rewrite(
    List<Proposition> toMerge,
    String sourceTurnId,
    String sourceEpisodeId,
  ) async {
    final combined = toMerge.map((p) => p.content).join('\n');
    final allSourceIds = toMerge.expand((p) => p.sourceIds).toSet().toList();

    final prompt = '''Rewrite these propositions into a single canonical form.
Preserve all information. Remove redundancy. One self-contained proposition.

Propositions:
$combined

Output JSON: {"content": "...", "scope": "session|project|life", "type": "learning|project|exploration"}''';

    final response = await _chatClient.chat(
      eventId: 'rewrite_${DateTime.now().millisecondsSinceEpoch}',
      messages: [
        Message(role: 'system', content: 'You rewrite propositions into canonical form. Output only valid JSON.'),
        Message(role: 'user', content: prompt),
      ],
    );

    try {
      final json = _extractJson(response);
      final parsed = jsonDecode(json) as Map<String, dynamic>;
      return [
        Proposition(
          content: parsed['content'] as String,
          scope: parsed['scope'] as String? ?? 'session',
          type: parsed['type'] as String?,
          sourceIds: allSourceIds,
          sourceTurnId: sourceTurnId,
          sourceEpisodeId: sourceEpisodeId,
        ),
      ];
    } catch (_) {
      return toMerge;
    }
  }

  Future<_SpanResult> _decontextualizeSpan(
    ConceptSpan span,
    List<Sentence> sentences,
    WorkingMemoryService workingMemory,
    String sourceTurnId,
    String sourceEpisodeId,
  ) async {
    final spanWatch = Stopwatch()..start();
    final spanText = span.text;
    final surrounding = _findSurrounding(span, sentences);
    final entityList = workingMemory.entityList;

    final systemPrompt = '''You decompose a concept span into atomic, self-contained propositions.

Rules:
- Each proposition must be understandable WITHOUT the source text.
- Replace all pronouns with specific referents from known entities or surrounding context.
- BARE ASSERTIVE FORM: Write propositions as standalone knowledge claims, never as observations about a person. No "The user wants/thinks/believes/decided". Test: "It is known that [proposition]" must read naturally.
  WRONG: "The user wants to use AWS Lambda for the backend."
  RIGHT: "AWS Lambda is the chosen backend for the therapy tracker."
  WRONG: "The user believes React Native adds too much complexity."
  RIGHT: "React Native adds 10x complexity for 5% benefit compared to a PWA for simple tracking apps."
- STRICT ATOMICITY: One fact per proposition. Never bundle items with "includes X, Y, and Z" or "X and Y". If a span lists 4 benefits, output 4 propositions. If a sentence has 2 facts joined by "and", split into 2 propositions.
  WRONG: "PWA benefits include offline capability, add-to-homescreen, no app store review, and cross-device compatibility."
  RIGHT (4 separate propositions): "PWAs work offline." / "PWAs install to homescreen." / "PWAs bypass app store review." / "PWAs are cross-device compatible."
- Skip filler, greetings, hedging, and meta-commentary.
- Output 0 propositions if the span contains no durable knowledge.
- Scope: session (this conversation only), project (named project), life (identity-level).
- Type: learning (discovered fact), project (decision/requirement), exploration (investigated option).
- Output ONLY a valid JSON array.''';

    final prompt = '''Text:
$spanText

Surrounding context:
$surrounding

Known entities: ${entityList.join(', ')}

Output JSON array: [{"content": "...", "scope": "...", "type": "...", "sourceIds": ["S1", "S2"]}]''';

    final response = await _chatClient.chat(
      eventId: 'decontext_${span.spanId}_${DateTime.now().millisecondsSinceEpoch}',
      messages: [
        Message(role: 'system', content: systemPrompt),
        Message(role: 'user', content: prompt),
      ],
    );

    spanWatch.stop();
    final propositions = _parsePropositions(
      response, span, sourceTurnId, sourceEpisodeId,
    );
    final outputJson = propositions
        .map((p) => {
              'propositionId': p.uuid,
              'text': p.content,
              'sourceIds': p.sourceIds,
              'scope': p.scope,
              'type': p.type,
            })
        .toList();

    return _SpanResult(
      propositions: propositions,
      trace: DecontextualizeSpanTrace(
        spanId: span.spanId,
        output: outputJson,
        model: 'groq/llama-3.1-8b-instant',
        latencyMs: spanWatch.elapsedMilliseconds,
      ),
    );
  }

  List<Proposition> _parsePropositions(
    String response,
    ConceptSpan span,
    String sourceTurnId,
    String sourceEpisodeId,
  ) {
    try {
      final json = _extractJsonArray(response);
      final parsed = jsonDecode(json) as List;
      return parsed.map((item) {
        final map = item as Map<String, dynamic>;
        final sourceIds = (map['sourceIds'] as List?)?.cast<String>() ?? span.sentenceIds;
        return Proposition(
          content: map['content'] as String,
          scope: map['scope'] as String? ?? 'session',
          type: map['type'] as String?,
          sourceIds: sourceIds,
          sourceTurnId: sourceTurnId,
          sourceEpisodeId: sourceEpisodeId,
        );
      }).toList();
    } catch (_) {
      return [
        Proposition(
          content: span.sentenceIds.join(' '),
          scope: 'session',
          sourceIds: span.sentenceIds,
          sourceTurnId: sourceTurnId,
          sourceEpisodeId: sourceEpisodeId,
        ),
      ];
    }
  }

  String _findSurrounding(ConceptSpan span, List<Sentence> sentences) {
    final spanIdSet = span.sentenceIds.toSet();
    final allIds = sentences.map((s) => s.id).toList();
    final firstIdx = allIds.indexOf(span.sentenceIds.first);
    final lastIdx = allIds.indexOf(span.sentenceIds.last);

    final contextIds = <String>[];
    for (var i = (firstIdx - 2).clamp(0, allIds.length); i <= (lastIdx + 2).clamp(0, allIds.length - 1); i++) {
      if (!spanIdSet.contains(allIds[i])) {
        contextIds.add(allIds[i]);
      }
    }

    return sentences
        .where((s) => contextIds.contains(s.id))
        .map((s) => s.text)
        .join(' ');
  }

  String _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) return text.substring(start, end + 1);
    return text;
  }

  String _extractJsonArray(String text) {
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start >= 0 && end > start) return text.substring(start, end + 1);
    return text;
  }
}

class _SpanResult {
  final List<Proposition> propositions;
  final DecontextualizeSpanTrace trace;

  _SpanResult({required this.propositions, required this.trace});
}
