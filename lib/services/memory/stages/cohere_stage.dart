import 'dart:convert' show jsonDecode;

import '../../slm/runners/cohere_runner.dart';
import '../../types/chat_client.dart';
import '../../types/message.dart';
import '../encoder_stage.dart';
import '../encoder_trace.dart';

class CohereInput {
  final List<Sentence> sentences;

  CohereInput({required this.sentences});
}

class CohereResult {
  final List<ConceptSpan> spans;
  final CohereTrace trace;

  CohereResult({required this.spans, required this.trace});
}

/// Group adjacent sentences into concept spans by discourse coherence.
/// Primary: on-device CohereRunner (NLI DeBERTa pairwise scoring).
/// Fallback: LLM via ChatClient (temporary, being phased out).
class CohereStage implements EncoderStage<CohereInput, CohereResult> {
  final CohereRunner? _cohereRunner;
  final ChatClient? _chatClient;
  static const double _defaultThreshold = 0.5;

  CohereStage({CohereRunner? cohereRunner, ChatClient? chatClient})
      : _cohereRunner = cohereRunner,
        _chatClient = chatClient;

  @override
  String get stageName => 'cohere';

  String get _modelName => _cohereRunner != null
      ? 'bert-wiki-paragraphs'
      : 'groq/llama-3.1-8b-instant';

  @override
  Future<CohereResult> process(CohereInput input) async {
    final stopwatch = Stopwatch()..start();

    if (input.sentences.isEmpty) {
      stopwatch.stop();
      return CohereResult(
        spans: [],
        trace: CohereTrace(
          input: [],
          pairScores: [],
          output: [],
          model: _modelName,
          threshold: _defaultThreshold,
          latencyMs: stopwatch.elapsedMilliseconds,
        ),
      );
    }

    if (input.sentences.length == 1) {
      final span = ConceptSpan(
        spanId: 'span_0',
        sentenceIds: [input.sentences.first.id],
      );
      stopwatch.stop();
      return CohereResult(
        spans: [span],
        trace: CohereTrace(
          input: input.sentences.map((s) => s.id).toList(),
          pairScores: [],
          output: [span],
          model: _modelName,
          threshold: _defaultThreshold,
          latencyMs: stopwatch.elapsedMilliseconds,
        ),
      );
    }

    final boundaries = await _findBoundaries(input.sentences);
    final spans = _buildSpans(input.sentences, boundaries);

    stopwatch.stop();

    return CohereResult(
      spans: spans,
      trace: CohereTrace(
        input: input.sentences.map((s) => s.id).toList(),
        pairScores: boundaries,
        output: spans,
        model: _modelName,
        threshold: _defaultThreshold,
        latencyMs: stopwatch.elapsedMilliseconds,
      ),
    );
  }

  Future<List<PairScore>> _findBoundaries(List<Sentence> sentences) async {
    if (_cohereRunner != null) {
      return _findBoundariesWithRunner(sentences);
    }
    return _findBoundariesWithLlm(sentences);
  }

  Future<List<PairScore>> _findBoundariesWithRunner(
      List<Sentence> sentences) async {
    final scores = <PairScore>[];
    for (var i = 0; i < sentences.length - 1; i++) {
      final pair = await _cohereRunner!.score(
        sentences[i].text,
        sentences[i + 1].text,
      );
      scores.add(PairScore(
        pair: [sentences[i].id, sentences[i + 1].id],
        coherenceScore: pair.coherence,
        boundary: pair.coherence < _defaultThreshold,
      ));
    }
    return scores;
  }

  Future<List<PairScore>> _findBoundariesWithLlm(
      List<Sentence> sentences) async {
    final sentenceList = sentences
        .map((s) => '${s.id}: ${s.text}')
        .join('\n');

    final prompt = '''Analyze discourse coherence between adjacent sentences.
For each adjacent pair, output a JSON array of objects with:
- "pair": [id1, id2]
- "boundary": true if the topic changes, false if same topic continues

Sentences:
$sentenceList

Output ONLY a JSON array, no other text.''';

    if (_chatClient == null) {
      throw StateError('CohereStage requires a CohereRunner or ChatClient');
    }
    final response = await _chatClient.chat(
      eventId: 'cohere_${DateTime.now().millisecondsSinceEpoch}',
      messages: [
        Message(role: 'system', content: 'You analyze discourse coherence. Output only valid JSON.'),
        Message(role: 'user', content: prompt),
      ],
    );

    return _parseBoundaries(response, sentences);
  }

  List<PairScore> _parseBoundaries(String response, List<Sentence> sentences) {
    try {
      final cleaned = _extractJson(response);
      final parsed = _parseJsonArray(cleaned);
      return parsed.map((item) {
        final pair = (item['pair'] as List).map((e) => _normalizeSentenceId(e)).toList();
        final boundary = item['boundary'] as bool? ?? false;
        return PairScore(
          pair: pair,
          coherenceScore: boundary ? 0.2 : 0.8,
          boundary: boundary,
        );
      }).toList();
    } catch (_) {
      // Fallback: no boundaries (all sentences in one span)
      return [];
    }
  }

  List<ConceptSpan> _buildSpans(
      List<Sentence> sentences, List<PairScore> pairScores) {
    final boundaryIds = <String>{};
    for (final score in pairScores) {
      if (score.boundary && score.pair.length == 2) {
        boundaryIds.add(score.pair[1]);
      }
    }

    final spans = <ConceptSpan>[];
    var currentIds = <String>[];
    var spanIndex = 0;

    for (final sentence in sentences) {
      if (boundaryIds.contains(sentence.id) && currentIds.isNotEmpty) {
        spans.add(ConceptSpan(spanId: 'span_$spanIndex', sentenceIds: currentIds));
        currentIds = [];
        spanIndex++;
      }
      currentIds.add(sentence.id);
    }

    if (currentIds.isNotEmpty) {
      spans.add(ConceptSpan(spanId: 'span_$spanIndex', sentenceIds: currentIds));
    }

    return spans;
  }

  /// LLM may return bare ints (1, 2) instead of "S1", "S2".
  String _normalizeSentenceId(dynamic rawId) {
    final s = rawId.toString();
    if (s.startsWith('S')) return s;
    return 'S$s';
  }

  String _extractJson(String text) {
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start >= 0 && end > start) {
      return text.substring(start, end + 1);
    }
    return text;
  }

  List<Map<String, dynamic>> _parseJsonArray(String text) {
    final decoded = jsonDecode(text);
    return (decoded as List).cast<Map<String, dynamic>>();
  }
}
