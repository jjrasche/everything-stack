import 'dart:convert' show jsonDecode;

import '../../types/chat_client.dart';
import '../../types/message.dart';
import '../encoder_stage.dart';
import '../encoder_trace.dart';
import '../working_memory_service.dart';

class ClassifyInput {
  final List<ConceptSpan> spans;
  final List<Sentence> sentences;
  final WorkingMemoryService workingMemory;

  ClassifyInput({
    required this.spans,
    required this.sentences,
    required this.workingMemory,
  });
}

class ClassifyResult {
  final List<ClassifyDecision> decisions;
  final ClassifyTrace trace;

  ClassifyResult({required this.decisions, required this.trace});

  List<ConceptSpan> extractSpans(List<ConceptSpan> allSpans) {
    final extractIds = decisions
        .where((d) => d.isExtract)
        .map((d) => d.spanId)
        .toSet();
    return allSpans.where((s) => extractIds.contains(s.spanId)).toList();
  }
}

/// Sequential span classification: extract or skip with reason.
/// Each span sees previous decisions as context.
/// Phase 1: Groq LLM. Phase 3: CRF or SetFit/DeBERTa.
class ClassifyStage implements EncoderStage<ClassifyInput, ClassifyResult> {
  final ChatClient _chatClient;

  ClassifyStage({required ChatClient chatClient})
      : _chatClient = chatClient;

  @override
  String get stageName => 'classify';

  @override
  Future<ClassifyResult> process(ClassifyInput input) async {
    final stopwatch = Stopwatch()..start();
    final decisions = <ClassifyDecision>[];

    for (final span in input.spans) {
      final decision = await _classifySpan(
        span,
        input.sentences,
        input.workingMemory,
        decisions,
      );
      decisions.add(decision);
    }

    stopwatch.stop();

    return ClassifyResult(
      decisions: decisions,
      trace: ClassifyTrace(
        decisions: decisions,
        totalLatencyMs: stopwatch.elapsedMilliseconds,
      ),
    );
  }

  Future<ClassifyDecision> _classifySpan(
    ConceptSpan span,
    List<Sentence> sentences,
    WorkingMemoryService workingMemory,
    List<ClassifyDecision> previousDecisions,
  ) async {
    final spanWatch = Stopwatch()..start();
    final spanText = span.resolveText(sentences);
    final wmContext = workingMemory.propositionsAsContext();

    final previousContext = previousDecisions.isEmpty
        ? 'None yet.'
        : previousDecisions
            .map((d) => '${d.spanId}: ${d.label}${d.reason != null ? ' (${d.reason})' : ''}')
            .join('\n');

    final systemPrompt = '''You classify text spans as "extract" or "skip". Output only valid JSON.

SKIP spans that are:
- ephemeral: greetings, filler, conversational ("okay", "sure", "let me think", "and yeah")
- trivial: too vague to be useful without context ("it differs", "that works")
- generic: common knowledge not specific to this conversation
- already_known: restates something already in working memory
- unresolved: incomplete thought or question without answer

EXTRACT spans that contain a specific fact, decision, constraint, or design choice.
When in doubt, skip. Only extract durable knowledge.''';

    final prompt = '''Span (${span.spanId}):
$spanText

Working memory:
${wmContext.isEmpty ? 'Empty.' : wmContext}

Previous decisions:
$previousContext

Output JSON: {"label": "extract"|"skip", "reason": null|"reason", "confidence": 0.0-1.0}''';

    final response = await _chatClient.chat(
      eventId: 'classify_${span.spanId}_${DateTime.now().millisecondsSinceEpoch}',
      messages: [
        Message(role: 'system', content: systemPrompt),
        Message(role: 'user', content: prompt),
      ],
    );

    spanWatch.stop();
    return _parseDecision(response, span.spanId, spanWatch.elapsedMilliseconds);
  }

  ClassifyDecision _parseDecision(String response, String spanId, int latencyMs) {
    try {
      final json = _extractJson(response);
      final parsed = jsonDecode(json) as Map<String, dynamic>;
      return ClassifyDecision(
        spanId: spanId,
        label: parsed['label'] as String? ?? 'extract',
        reason: parsed['reason'] as String?,
        confidence: (parsed['confidence'] as num?)?.toDouble() ?? 0.5,
        model: 'groq/llama-3.1-8b-instant',
        latencyMs: latencyMs,
      );
    } catch (_) {
      return ClassifyDecision(
        spanId: spanId,
        label: 'extract',
        confidence: 0.5,
        model: 'groq/llama-3.1-8b-instant',
        latencyMs: latencyMs,
      );
    }
  }

  String _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return text.substring(start, end + 1);
    }
    return text;
  }
}
