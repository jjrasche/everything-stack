import 'dart:convert' show jsonDecode;

import '../../../domain/proposition.dart';
import '../../types/chat_client.dart';
import '../../types/message.dart';
import '../encoder_stage.dart';
import '../encoder_trace.dart';
import '../working_memory_diff.dart';
import '../working_memory_service.dart';
import 'decontextualize_stage.dart';

class DedupInput {
  final List<Proposition> propositions;
  final WorkingMemoryService workingMemory;
  final String sourceTurnId;
  final String sourceEpisodeId;

  DedupInput({
    required this.propositions,
    required this.workingMemory,
    required this.sourceTurnId,
    required this.sourceEpisodeId,
  });
}

class DedupResult {
  final WorkingMemoryDiff diff;
  final DedupTrace trace;

  DedupResult({required this.diff, required this.trace});
}

/// Pairwise NLI comparison of new propositions against working memory.
/// Phase 1: LLM-based. Phase 3: NLI cross-encoder replaces LLM.
class DedupStage implements EncoderStage<DedupInput, DedupResult> {
  final ChatClient _chatClient;
  final DecontextualizeStage _decontextualizeStage;

  DedupStage({
    required ChatClient chatClient,
    required DecontextualizeStage decontextualizeStage,
  })  : _chatClient = chatClient,
        _decontextualizeStage = decontextualizeStage;

  @override
  String get stageName => 'dedup';

  @override
  Future<DedupResult> process(DedupInput input) async {
    final stopwatch = Stopwatch()..start();
    final wmState = input.workingMemory.state;
    final comparisons = <DedupComparison>[];
    final actions = <DedupAction>[];
    final added = <Proposition>[];
    final superseded = <SupersessionRecord>[];
    final rewritten = <RewriteRecord>[];

    for (final newProp in input.propositions) {
      if (wmState.isEmpty) {
        added.add(newProp);
        actions.add(DedupAction(
          propositionId: newProp.uuid,
          action: 'add',
          source: 'no_wm_entries',
        ));
        continue;
      }

      final result = await _compareAgainstMemory(
        newProp, wmState, input.sourceTurnId, input.sourceEpisodeId,
      );
      comparisons.addAll(result.comparisons);

      switch (result.outcome) {
        case _DedupOutcome.noMatch:
          added.add(newProp);
          actions.add(DedupAction(
            propositionId: newProp.uuid,
            action: 'add',
          ));
        case _DedupOutcome.contradiction:
          added.add(newProp);
          superseded.add(SupersessionRecord(
            oldUuid: result.matchedUuid!,
            replacedByUuid: newProp.uuid,
            reason: 'contradiction',
          ));
          actions.add(DedupAction(
            propositionId: result.matchedUuid!,
            action: 'superseded',
            replacedBy: newProp.uuid,
          ));
          actions.add(DedupAction(
            propositionId: newProp.uuid,
            action: 'add',
            source: 'supersession',
          ));
        case _DedupOutcome.entailment:
          final canonical = await _rewriteCanonical(
            newProp, result.matchedProp!, input.sourceTurnId, input.sourceEpisodeId,
          );
          added.add(canonical);
          rewritten.add(RewriteRecord(
            oldUuid: result.matchedUuid!,
            mergedIntoUuid: canonical.uuid,
          ));
          actions.add(DedupAction(
            propositionId: result.matchedUuid!,
            action: 'superseded_by_rewrite',
            replacedBy: canonical.uuid,
          ));
          actions.add(DedupAction(
            propositionId: newProp.uuid,
            action: 'merged_into_rewrite',
            replacedBy: canonical.uuid,
          ));
          actions.add(DedupAction(
            propositionId: canonical.uuid,
            action: 'add',
            source: 'dedup_rewrite',
          ));
      }
    }

    stopwatch.stop();

    return DedupResult(
      diff: WorkingMemoryDiff(
        added: added,
        superseded: superseded,
        rewritten: rewritten,
      ),
      trace: DedupTrace(
        comparisons: comparisons,
        actions: actions,
        model: 'groq/llama-3.1-8b-instant',
        latencyMs: stopwatch.elapsedMilliseconds,
      ),
    );
  }

  Future<_CompareResult> _compareAgainstMemory(
    Proposition newProp,
    List<Proposition> wmState,
    String sourceTurnId,
    String sourceEpisodeId,
  ) async {
    final comparisons = <DedupComparison>[];

    for (final existing in wmState) {
      final comparison = await _comparePair(newProp, existing);
      comparisons.add(comparison);

      if (comparison.decision == 'bidirectional_entailment') {
        return _CompareResult(
          comparisons: comparisons,
          outcome: _DedupOutcome.entailment,
          matchedUuid: existing.uuid,
          matchedProp: existing,
        );
      }
      if (comparison.decision == 'contradiction') {
        return _CompareResult(
          comparisons: comparisons,
          outcome: _DedupOutcome.contradiction,
          matchedUuid: existing.uuid,
          matchedProp: existing,
        );
      }
    }

    return _CompareResult(
      comparisons: comparisons,
      outcome: _DedupOutcome.noMatch,
    );
  }

  Future<DedupComparison> _comparePair(
    Proposition newProp,
    Proposition existing,
  ) async {
    final prompt = '''Compare these two propositions for semantic relationship.

Proposition A (new): ${newProp.content}
Proposition B (existing): ${existing.content}

Classify as:
- "no_match": unrelated or only loosely related
- "bidirectional_entailment": same meaning in different words
- "contradiction": one negates or updates the other

Output JSON: {"decision": "...", "entailmentScore": 0.0-1.0, "contradictionScore": 0.0-1.0}''';

    final response = await _chatClient.chat(
      eventId: 'dedup_${DateTime.now().millisecondsSinceEpoch}',
      messages: [
        Message(role: 'system', content: 'You compare propositions for semantic relationships. Output only valid JSON.'),
        Message(role: 'user', content: prompt),
      ],
    );

    return _parseComparison(response, newProp.uuid, existing.uuid);
  }

  DedupComparison _parseComparison(
    String response,
    String newId,
    String existingId,
  ) {
    try {
      final json = _extractJson(response);
      final parsed = jsonDecode(json) as Map<String, dynamic>;
      return DedupComparison(
        newPropositionId: newId,
        comparedTo: existingId,
        entailmentScore: (parsed['entailmentScore'] as num?)?.toDouble() ?? 0.0,
        contradictionScore: (parsed['contradictionScore'] as num?)?.toDouble() ?? 0.0,
        decision: parsed['decision'] as String? ?? 'no_match',
      );
    } catch (_) {
      return DedupComparison(
        newPropositionId: newId,
        comparedTo: existingId,
        entailmentScore: 0.0,
        contradictionScore: 0.0,
        decision: 'no_match',
      );
    }
  }

  Future<Proposition> _rewriteCanonical(
    Proposition newProp,
    Proposition existing,
    String sourceTurnId,
    String sourceEpisodeId,
  ) async {
    final results = await _decontextualizeStage.rewrite(
      [existing, newProp],
      sourceTurnId,
      sourceEpisodeId,
    );
    return results.first;
  }

  String _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) return text.substring(start, end + 1);
    return text;
  }
}

enum _DedupOutcome { noMatch, contradiction, entailment }

class _CompareResult {
  final List<DedupComparison> comparisons;
  final _DedupOutcome outcome;
  final String? matchedUuid;
  final Proposition? matchedProp;

  _CompareResult({
    required this.comparisons,
    required this.outcome,
    this.matchedUuid,
    this.matchedProp,
  });
}
