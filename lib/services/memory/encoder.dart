import 'encoder_trace.dart';
import 'working_memory_diff.dart';
import 'working_memory_service.dart';
import 'stages/normalize_stage.dart';
import 'stages/segment_stage.dart';
import 'stages/cohere_stage.dart';
import 'stages/classify_stage.dart';
import 'stages/decontextualize_stage.dart';
import 'stages/dedup_stage.dart';

class EncoderResult {
  final WorkingMemoryDiff diff;
  final EncoderTrace trace;

  EncoderResult({required this.diff, required this.trace});
}

/// Pure orchestrator: calls stages in sequence, threads output → input.
/// Does NOT apply the diff — caller decides when to apply.
class Encoder {
  final NormalizeStage _normalizeStage;
  final SegmentStage _segmentStage;
  final CohereStage _cohereStage;
  final ClassifyStage _classifyStage;
  final DecontextualizeStage _decontextualizeStage;
  final DedupStage _dedupStage;

  Encoder({
    required NormalizeStage normalizeStage,
    required SegmentStage segmentStage,
    required CohereStage cohereStage,
    required ClassifyStage classifyStage,
    required DecontextualizeStage decontextualizeStage,
    required DedupStage dedupStage,
  })  : _normalizeStage = normalizeStage,
        _segmentStage = segmentStage,
        _cohereStage = cohereStage,
        _classifyStage = classifyStage,
        _decontextualizeStage = decontextualizeStage,
        _dedupStage = dedupStage;

  Future<EncoderResult> encode({
    required EpisodicSource source,
    required String turnId,
    required WorkingMemoryService workingMemory,
    bool skipDedup = false,
  }) async {
    final wmBefore = workingMemory.propositionUuids();

    final normalizeResult = await _normalizeStage.process(source.text);

    final segmentResult = await _segmentStage.process(normalizeResult.output);

    final cohereResult = await _cohereStage.process(
      CohereInput(sentences: segmentResult.sentences),
    );

    final classifyResult = await _classifyStage.process(ClassifyInput(
      spans: cohereResult.spans,
      sentences: segmentResult.sentences,
      workingMemory: workingMemory,
    ));

    final extractSpans = classifyResult.extractSpans(cohereResult.spans);

    final decontextResult = await _decontextualizeStage.process(
      DecontextualizeInput(
        extractSpans: extractSpans,
        sentences: segmentResult.sentences,
        workingMemory: workingMemory,
        sourceTurnId: turnId,
        sourceEpisodeId: source.episodeId,
      ),
    );

    final DedupResult dedupResult;
    if (skipDedup) {
      dedupResult = DedupResult(
        diff: WorkingMemoryDiff(added: decontextResult.propositions),
        trace: DedupTrace(
          comparisons: [],
          actions: [],
          model: 'skipped',
          latencyMs: 0,
        ),
      );
    } else {
      dedupResult = await _dedupStage.process(DedupInput(
        propositions: decontextResult.propositions,
        workingMemory: workingMemory,
        sourceTurnId: turnId,
        sourceEpisodeId: source.episodeId,
      ));
    }

    // Compute what working memory would look like after applying diff
    // (for trace only — we don't actually apply it)
    final wmAfterPreview = List<String>.from(wmBefore);
    for (final s in dedupResult.diff.superseded) {
      wmAfterPreview.remove(s.oldUuid);
    }
    for (final r in dedupResult.diff.rewritten) {
      wmAfterPreview.remove(r.oldUuid);
    }
    for (final a in dedupResult.diff.added) {
      wmAfterPreview.add(a.uuid);
    }

    return EncoderResult(
      diff: dedupResult.diff,
      trace: EncoderTrace(
        turnId: turnId,
        episodicSource: source,
        workingMemoryBefore: wmBefore,
        normalize: normalizeResult.trace,
        segment: segmentResult.trace,
        cohere: cohereResult.trace,
        classify: classifyResult.trace,
        decontextualize: decontextResult.trace,
        dedup: dedupResult.trace,
        workingMemoryAfter: wmAfterPreview,
      ),
    );
  }
}
