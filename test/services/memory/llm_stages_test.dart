import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/types/chat_client.dart';
import 'package:everything_stack_template/services/types/message.dart';
import 'package:everything_stack_template/services/memory/encoder_trace.dart';
import 'package:everything_stack_template/services/memory/working_memory_service.dart';
import 'package:everything_stack_template/services/memory/working_memory_diff.dart';
import 'package:everything_stack_template/services/memory/stages/cohere_stage.dart';
import 'package:everything_stack_template/services/memory/stages/classify_stage.dart';
import 'package:everything_stack_template/services/memory/stages/filter_stage.dart';
import 'package:everything_stack_template/services/memory/stages/decontextualize_stage.dart';
import 'package:everything_stack_template/services/memory/stages/dedup_stage.dart';
import 'package:everything_stack_template/services/slm/runners/filter_runner.dart';
import 'package:everything_stack_template/domain/proposition.dart';

class MockChatClient implements ChatClient {
  final Map<String, String> _responses = {};

  void stubResponse(String eventIdPrefix, String response) {
    _responses[eventIdPrefix] = response;
  }

  @override
  Future<String> chat({
    required String eventId,
    required List<Message> messages,
  }) async {
    for (final entry in _responses.entries) {
      if (eventId.startsWith(entry.key)) return entry.value;
    }
    return '{}';
  }
}

class MockFilterRunner implements FilterRunner {
  FilterPrediction _prediction = FilterPrediction(extractScore: 0.9, skipScore: 0.1);

  void stubPrediction(FilterPrediction prediction) {
    _prediction = prediction;
  }

  @override
  Future<FilterPrediction> predict(String spanText) async => _prediction;
}

void main() {
  late MockChatClient mockChat;
  late WorkingMemoryService workingMemory;

  setUp(() {
    mockChat = MockChatClient();
    workingMemory = WorkingMemoryService(maxCapacity: 50);
  });

  group('CohereStage', () {
    late CohereStage stage;

    setUp(() {
      stage = CohereStage(chatClient: mockChat);
    });

    test('groups all sentences into one span when no boundaries', () async {
      mockChat.stubResponse('cohere_',
          '[{"pair": ["S1", "S2"], "boundary": false}]');

      final result = await stage.process(CohereInput(sentences: [
        Sentence(id: 'S1', text: 'ObjectBox is fast.'),
        Sentence(id: 'S2', text: 'It uses LMDB internally.'),
      ]));

      expect(result.spans, hasLength(1));
      expect(result.spans.first.sentenceIds, ['S1', 'S2']);
      expect(result.spans.first.text, 'ObjectBox is fast. It uses LMDB internally.');
    });

    test('splits at boundary', () async {
      mockChat.stubResponse('cohere_',
          '[{"pair": ["S1", "S2"], "boundary": false}, {"pair": ["S2", "S3"], "boundary": true}]');

      final result = await stage.process(CohereInput(sentences: [
        Sentence(id: 'S1', text: 'ObjectBox is fast.'),
        Sentence(id: 'S2', text: 'It uses LMDB.'),
        Sentence(id: 'S3', text: 'Flutter supports 6 platforms.'),
      ]));

      expect(result.spans, hasLength(2));
      expect(result.spans[0].sentenceIds, ['S1', 'S2']);
      expect(result.spans[1].sentenceIds, ['S3']);
    });

    test('handles single sentence', () async {
      final result = await stage.process(CohereInput(sentences: [
        Sentence(id: 'S1', text: 'Only one.'),
      ]));

      expect(result.spans, hasLength(1));
      expect(result.spans.first.text, 'Only one.');
    });
  });

  group('ClassifyStage', () {
    late ClassifyStage stage;

    setUp(() {
      stage = ClassifyStage(chatClient: mockChat);
    });

    test('classifies span as extract', () async {
      mockChat.stubResponse('classify_',
          '{"label": "extract", "reason": null, "confidence": 0.9}');

      final result = await stage.process(ClassifyInput(
        spans: [ConceptSpan(spanId: 'span_0', sentenceIds: ['S1'], text: 'ObjectBox is fast.')],
        sentences: [Sentence(id: 'S1', text: 'ObjectBox is fast.')],
        workingMemory: workingMemory,
      ));

      expect(result.decisions, hasLength(1));
      expect(result.decisions.first.label, 'extract');
      expect(result.decisions.first.isExtract, isTrue);
    });

    test('classifies span as skip with reason', () async {
      mockChat.stubResponse('classify_',
          '{"label": "skip", "reason": "ephemeral", "confidence": 0.85}');

      final result = await stage.process(ClassifyInput(
        spans: [ConceptSpan(spanId: 'span_0', sentenceIds: ['S1'], text: 'Okay sure.')],
        sentences: [Sentence(id: 'S1', text: 'Okay sure.')],
        workingMemory: workingMemory,
      ));

      expect(result.decisions.first.label, 'skip');
      expect(result.decisions.first.reason, 'ephemeral');
    });

    test('extractSpans filters to extract-labeled spans', () async {
      mockChat.stubResponse('classify_span_0',
          '{"label": "extract", "confidence": 0.9}');
      mockChat.stubResponse('classify_span_1',
          '{"label": "skip", "reason": "trivial", "confidence": 0.8}');

      final allSpans = [
        ConceptSpan(spanId: 'span_0', sentenceIds: ['S1'], text: 'Important fact.'),
        ConceptSpan(spanId: 'span_1', sentenceIds: ['S2'], text: 'Trivial filler.'),
      ];

      final result = await stage.process(ClassifyInput(
        spans: allSpans,
        sentences: [
          Sentence(id: 'S1', text: 'Important fact.'),
          Sentence(id: 'S2', text: 'Trivial filler.'),
        ],
        workingMemory: workingMemory,
      ));

      final extracted = result.extractSpans(allSpans);
      expect(extracted, hasLength(1));
      expect(extracted.first.spanId, 'span_0');
    });
  });

  group('FilterStage', () {
    late MockFilterRunner mockRunner;
    late FilterStage stage;

    setUp(() {
      mockRunner = MockFilterRunner();
      stage = FilterStage(filterRunner: mockRunner);
    });

    test('filters span as extract', () async {
      mockRunner.stubPrediction(
          FilterPrediction(extractScore: 0.9, skipScore: 0.1));

      final result = await stage.process(FilterInput(
        spans: [ConceptSpan(spanId: 'span_0', sentenceIds: ['S1'], text: 'ObjectBox is fast.')],
      ));

      expect(result.decisions, hasLength(1));
      expect(result.decisions.first.label, 'extract');
      expect(result.decisions.first.isExtract, isTrue);
    });

    test('filters span as skip', () async {
      mockRunner.stubPrediction(
          FilterPrediction(extractScore: 0.15, skipScore: 0.85));

      final result = await stage.process(FilterInput(
        spans: [ConceptSpan(spanId: 'span_0', sentenceIds: ['S1'], text: 'Okay sure.')],
      ));

      expect(result.decisions.first.label, 'skip');
      expect(result.decisions.first.isExtract, isFalse);
    });

    test('extractSpans filters to extract-labeled spans', () async {
      // First call returns extract, second returns skip
      final sequentialRunner = _SequentialMockFilterRunner([
        FilterPrediction(extractScore: 0.9, skipScore: 0.1),
        FilterPrediction(extractScore: 0.15, skipScore: 0.85),
      ]);
      stage = FilterStage(filterRunner: sequentialRunner);

      final allSpans = [
        ConceptSpan(spanId: 'span_0', sentenceIds: ['S1'], text: 'Important fact.'),
        ConceptSpan(spanId: 'span_1', sentenceIds: ['S2'], text: 'Trivial filler.'),
      ];

      final result = await stage.process(FilterInput(spans: allSpans));

      final extracted = result.extractSpans(allSpans);
      expect(extracted, hasLength(1));
      expect(extracted.first.spanId, 'span_0');
    });
  });

  group('DecontextualizeStage', () {
    late DecontextualizeStage stage;

    setUp(() {
      stage = DecontextualizeStage(chatClient: mockChat);
    });

    test('produces propositions from extract span', () async {
      mockChat.stubResponse('decontext_',
          '[{"content": "ObjectBox delivers sub-millisecond queries.", "scope": "project", "type": "learning", "sourceIds": ["S1"]}]');

      final result = await stage.process(DecontextualizeInput(
        extractSpans: [ConceptSpan(spanId: 'span_0', sentenceIds: ['S1'], text: 'It is really fast.')],
        sentences: [Sentence(id: 'S1', text: 'It is really fast.')],
        workingMemory: workingMemory,
        sourceTurnId: 'conv_abc_turn_0',
        sourceEpisodeId: 'conv_abc',
      ));

      expect(result.propositions, hasLength(1));
      expect(result.propositions.first.content,
          'ObjectBox delivers sub-millisecond queries.');
      expect(result.propositions.first.scope, 'project');
      expect(result.propositions.first.sourceTurnId, 'conv_abc_turn_0');
    });
  });

  group('DedupStage', () {
    late DedupStage stage;
    late DecontextualizeStage decontextStage;

    setUp(() {
      decontextStage = DecontextualizeStage(chatClient: mockChat);
      stage = DedupStage(
        chatClient: mockChat,
        decontextualizeStage: decontextStage,
      );
    });

    test('adds proposition when working memory is empty', () async {
      final prop = Proposition(
        content: 'ObjectBox is fast.',
        scope: 'project',
        sourceIds: ['S1'],
        sourceTurnId: 'conv_abc_turn_0',
        sourceEpisodeId: 'conv_abc',
      );

      final result = await stage.process(DedupInput(
        propositions: [prop],
        workingMemory: workingMemory,
        sourceTurnId: 'conv_abc_turn_0',
        sourceEpisodeId: 'conv_abc',
      ));

      expect(result.diff.added, hasLength(1));
      expect(result.diff.superseded, isEmpty);
      expect(result.diff.rewritten, isEmpty);
    });

    test('detects no_match and adds', () async {
      workingMemory.applyDiff(WorkingMemoryDiff(added: [
        Proposition(
          content: 'Flutter supports 6 platforms.',
          scope: 'project',
          sourceIds: ['S0'],
          sourceTurnId: 'conv_abc_turn_0',
          sourceEpisodeId: 'conv_abc',
        ),
      ]));

      mockChat.stubResponse('dedup_',
          '{"decision": "no_match", "entailmentScore": 0.1, "contradictionScore": 0.05}');

      final result = await stage.process(DedupInput(
        propositions: [
          Proposition(
            content: 'ObjectBox is fast.',
            scope: 'project',
            sourceIds: ['S1'],
            sourceTurnId: 'conv_abc_turn_1',
            sourceEpisodeId: 'conv_abc',
          ),
        ],
        workingMemory: workingMemory,
        sourceTurnId: 'conv_abc_turn_1',
        sourceEpisodeId: 'conv_abc',
      ));

      expect(result.diff.added, hasLength(1));
      expect(result.diff.superseded, isEmpty);
    });

    test('detects contradiction and supersedes', () async {
      final existing = Proposition(
        content: 'Flutter uses Skia.',
        scope: 'project',
        sourceIds: ['S0'],
        sourceTurnId: 'conv_abc_turn_0',
        sourceEpisodeId: 'conv_abc',
      );
      workingMemory.applyDiff(WorkingMemoryDiff(added: [existing]));

      mockChat.stubResponse('dedup_',
          '{"decision": "contradiction", "entailmentScore": 0.1, "contradictionScore": 0.9}');

      final result = await stage.process(DedupInput(
        propositions: [
          Proposition(
            content: 'Flutter uses Impeller.',
            scope: 'project',
            sourceIds: ['S1'],
            sourceTurnId: 'conv_abc_turn_1',
            sourceEpisodeId: 'conv_abc',
          ),
        ],
        workingMemory: workingMemory,
        sourceTurnId: 'conv_abc_turn_1',
        sourceEpisodeId: 'conv_abc',
      ));

      expect(result.diff.added, hasLength(1));
      expect(result.diff.superseded, hasLength(1));
      expect(result.diff.superseded.first.oldUuid, existing.uuid);
    });
  });
}

class _SequentialMockFilterRunner implements FilterRunner {
  final List<FilterPrediction> _predictions;
  int _index = 0;

  _SequentialMockFilterRunner(this._predictions);

  @override
  Future<FilterPrediction> predict(String spanText) async {
    final prediction = _predictions[_index % _predictions.length];
    _index++;
    return prediction;
  }
}
