/// Per-turn trace through all encoder stages.
/// Each stage logs input, output, model, and latency.
class EncoderTrace {
  final String turnId;
  final EpisodicSource episodicSource;
  final List<String> workingMemoryBefore;
  final NormalizeTrace normalize;
  final SegmentTrace segment;
  final CohereTrace cohere;
  final ClassifyTrace classify;
  final DecontextualizeTrace decontextualize;
  final DedupTrace dedup;
  final List<String> workingMemoryAfter;

  EncoderTrace({
    required this.turnId,
    required this.episodicSource,
    required this.workingMemoryBefore,
    required this.normalize,
    required this.segment,
    required this.cohere,
    required this.classify,
    required this.decontextualize,
    required this.dedup,
    required this.workingMemoryAfter,
  });

  Map<String, dynamic> toJson() => {
        'turnId': turnId,
        'episodicSource': episodicSource.toJson(),
        'workingMemoryBefore': workingMemoryBefore,
        'stages': {
          'normalize': normalize.toJson(),
          'segment': segment.toJson(),
          'cohere': cohere.toJson(),
          'classify': classify.toJson(),
          'decontextualize': decontextualize.toJson(),
          'dedup': dedup.toJson(),
        },
        'workingMemoryAfter': workingMemoryAfter,
      };
}

class EpisodicSource {
  final String text;
  final String speaker;
  final String episodeId;

  EpisodicSource({
    required this.text,
    required this.speaker,
    required this.episodeId,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'speaker': speaker,
        'episodeId': episodeId,
      };
}

class NormalizeTrace {
  final String input;
  final double punctuationRatio;
  final bool punctuationNeeded;
  final String? punctuateModel;
  final int? punctuateLatencyMs;
  final int splitCount;
  final List<Map<String, dynamic>> splitDetails;
  final String output;
  final int totalLatencyMs;

  NormalizeTrace({
    required this.input,
    required this.punctuationRatio,
    required this.punctuationNeeded,
    this.punctuateModel,
    this.punctuateLatencyMs,
    required this.splitCount,
    this.splitDetails = const [],
    required this.output,
    required this.totalLatencyMs,
  });

  Map<String, dynamic> toJson() => {
        'input': input,
        'punctuationRatio': punctuationRatio,
        'punctuationNeeded': punctuationNeeded,
        if (punctuateModel != null) 'punctuateModel': punctuateModel,
        if (punctuateLatencyMs != null)
          'punctuateLatencyMs': punctuateLatencyMs,
        'splitCount': splitCount,
        'splitDetails': splitDetails,
        'output': output,
        'totalLatencyMs': totalLatencyMs,
      };
}

class Sentence {
  final String id;
  final String text;

  Sentence({required this.id, required this.text});

  Map<String, dynamic> toJson() => {'id': id, 'text': text};
}

class SegmentTrace {
  final String input;
  final List<Sentence> output;
  final String model;
  final int latencyMs;

  SegmentTrace({
    required this.input,
    required this.output,
    required this.model,
    required this.latencyMs,
  });

  Map<String, dynamic> toJson() => {
        'input': input,
        'output': output.map((s) => s.toJson()).toList(),
        'model': model,
        'latencyMs': latencyMs,
      };
}

class PairScore {
  final List<String> pair;
  final double coherenceScore;
  final bool boundary;

  PairScore({
    required this.pair,
    required this.coherenceScore,
    required this.boundary,
  });

  Map<String, dynamic> toJson() => {
        'pair': pair,
        'coherenceScore': coherenceScore,
        'boundary': boundary,
      };
}

class ConceptSpan {
  final String spanId;
  final List<String> sentenceIds;

  ConceptSpan({required this.spanId, required this.sentenceIds});

  Map<String, dynamic> toJson() => {
        'spanId': spanId,
        'sentenceIds': sentenceIds,
      };

  /// Reconstruct span text from sentence list
  String resolveText(List<Sentence> sentences) {
    final idSet = sentenceIds.toSet();
    return sentences
        .where((s) => idSet.contains(s.id))
        .map((s) => s.text)
        .join(' ');
  }
}

class CohereTrace {
  final List<String> input;
  final List<PairScore> pairScores;
  final List<ConceptSpan> output;
  final String model;
  final double threshold;
  final int latencyMs;

  CohereTrace({
    required this.input,
    required this.pairScores,
    required this.output,
    required this.model,
    required this.threshold,
    required this.latencyMs,
  });

  Map<String, dynamic> toJson() => {
        'input': input,
        'pairScores': pairScores.map((p) => p.toJson()).toList(),
        'output': output.map((s) => s.toJson()).toList(),
        'model': model,
        'threshold': threshold,
        'latencyMs': latencyMs,
      };
}

class ClassifyDecision {
  final String spanId;
  final String label;
  final String? reason;
  final double confidence;
  final String model;
  final int latencyMs;

  ClassifyDecision({
    required this.spanId,
    required this.label,
    this.reason,
    required this.confidence,
    required this.model,
    required this.latencyMs,
  });

  bool get isExtract => label == 'extract';

  Map<String, dynamic> toJson() => {
        'spanId': spanId,
        'label': label,
        if (reason != null) 'reason': reason,
        'confidence': confidence,
        'model': model,
        'latencyMs': latencyMs,
      };
}

class ClassifyTrace {
  final bool sequential;
  final List<ClassifyDecision> decisions;
  final int totalLatencyMs;

  ClassifyTrace({
    this.sequential = true,
    required this.decisions,
    required this.totalLatencyMs,
  });

  Map<String, dynamic> toJson() => {
        'sequential': sequential,
        'decisions': decisions.map((d) => d.toJson()).toList(),
        'totalLatencyMs': totalLatencyMs,
      };
}

class DecontextualizeSpanTrace {
  final String spanId;
  final List<Map<String, dynamic>> output;
  final String model;
  final int latencyMs;

  DecontextualizeSpanTrace({
    required this.spanId,
    required this.output,
    required this.model,
    required this.latencyMs,
  });

  Map<String, dynamic> toJson() => {
        'spanId': spanId,
        'output': output,
        'model': model,
        'latencyMs': latencyMs,
      };
}

class DecontextualizeTrace {
  final bool perSpan;
  final List<DecontextualizeSpanTrace> spans;
  final int totalLatencyMs;

  DecontextualizeTrace({
    this.perSpan = true,
    required this.spans,
    required this.totalLatencyMs,
  });

  Map<String, dynamic> toJson() => {
        'perSpan': perSpan,
        'spans': spans.map((s) => s.toJson()).toList(),
        'totalLatencyMs': totalLatencyMs,
      };
}

class DedupComparison {
  final String newPropositionId;
  final String comparedTo;
  final double entailmentScore;
  final double contradictionScore;
  final String decision;
  final bool rewriteTriggered;
  final Map<String, dynamic>? rewriteOutput;
  final String? rewriteModel;
  final int? rewriteLatencyMs;

  DedupComparison({
    required this.newPropositionId,
    required this.comparedTo,
    required this.entailmentScore,
    required this.contradictionScore,
    required this.decision,
    this.rewriteTriggered = false,
    this.rewriteOutput,
    this.rewriteModel,
    this.rewriteLatencyMs,
  });

  Map<String, dynamic> toJson() => {
        'newPropositionId': newPropositionId,
        'comparedTo': comparedTo,
        'entailmentScore': entailmentScore,
        'contradictionScore': contradictionScore,
        'decision': decision,
        'rewriteTriggered': rewriteTriggered,
        if (rewriteOutput != null) 'rewriteOutput': rewriteOutput,
        if (rewriteModel != null) 'rewriteModel': rewriteModel,
        if (rewriteLatencyMs != null) 'rewriteLatencyMs': rewriteLatencyMs,
      };
}

class DedupAction {
  final String propositionId;
  final String action;
  final String? replacedBy;
  final String? source;

  DedupAction({
    required this.propositionId,
    required this.action,
    this.replacedBy,
    this.source,
  });

  Map<String, dynamic> toJson() => {
        'propositionId': propositionId,
        'action': action,
        if (replacedBy != null) 'replacedBy': replacedBy,
        if (source != null) 'source': source,
      };
}

class DedupTrace {
  final List<DedupComparison> comparisons;
  final List<DedupAction> actions;
  final String model;
  final int latencyMs;

  DedupTrace({
    required this.comparisons,
    required this.actions,
    required this.model,
    required this.latencyMs,
  });

  Map<String, dynamic> toJson() => {
        'comparisons': comparisons.map((c) => c.toJson()).toList(),
        'actions': actions.map((a) => a.toJson()).toList(),
        'model': model,
        'latencyMs': latencyMs,
      };
}
