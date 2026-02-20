import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/types/chat_client.dart';
import 'package:everything_stack_template/services/types/message.dart';
import 'package:everything_stack_template/services/memory/encoder.dart';
import 'package:everything_stack_template/services/memory/encoder_trace.dart';
import 'package:everything_stack_template/services/memory/working_memory_service.dart';
import 'package:everything_stack_template/services/memory/stages/normalize_stage.dart';
import 'package:everything_stack_template/services/memory/stages/segment_stage.dart';
import 'package:everything_stack_template/services/memory/stages/cohere_stage.dart';
import 'package:everything_stack_template/services/memory/stages/recohere_stage.dart';
import 'package:everything_stack_template/services/memory/stages/filter_stage.dart';
import 'package:everything_stack_template/services/memory/stages/decontextualize_stage.dart';
import 'package:everything_stack_template/services/memory/stages/dedup_stage.dart';
import 'package:everything_stack_template/services/slm/runners/filter_runner.dart';

class MockChatClient implements ChatClient {
  @override
  Future<String> chat({
    required String eventId,
    required List<Message> messages,
  }) async {
    if (eventId.startsWith('cohere_')) {
      return '[{"pair": ["S1", "S2"], "boundary": false}]';
    }
    if (eventId.startsWith('decontext_')) {
      return '[{"content": "ObjectBox supports all six Flutter platforms.", "scope": "project", "type": "learning", "sourceIds": ["S1", "S2"]}]';
    }
    if (eventId.startsWith('dedup_')) {
      return '{"decision": "no_match", "entailmentScore": 0.1, "contradictionScore": 0.0}';
    }
    return '{}';
  }
}

/// Always predicts extract for encoder integration tests.
class _ExtractAllFilterRunner implements FilterRunner {
  @override
  Future<FilterPrediction> predict(String spanText) async =>
      FilterPrediction(extractScore: 0.9, skipScore: 0.1);
}

void main() {
  group('Encoder', () {
    late Encoder encoder;
    late WorkingMemoryService workingMemory;
    late MockChatClient mockChat;

    setUp(() {
      mockChat = MockChatClient();
      workingMemory = WorkingMemoryService(maxCapacity: 50);

      final decontextStage = DecontextualizeStage(
        chatClient: mockChat,
      );

      encoder = Encoder(
        normalizeStage: NormalizeStage(),
        segmentStage: SegmentStage(),
        cohereStage: CohereStage(chatClient: mockChat),
        recoherStage: RecoherStage(),
        filterStage: FilterStage(filterRunner: _ExtractAllFilterRunner()),
        decontextualizeStage: decontextStage,
        dedupStage: DedupStage(
          chatClient: mockChat,
          decontextualizeStage: decontextStage,
        ),
      );
    });

    test('produces diff and trace from episodic source', () async {
      final source = EpisodicSource(
        text: 'I chose ObjectBox. It supports all six platforms.',
        speaker: 'user',
        episodeId: 'conv_abc',
      );

      final result = await encoder.encode(
        source: source,
        turnId: 'conv_abc_turn_0',
        workingMemory: workingMemory,
      );

      expect(result.diff.added, isNotEmpty);
      expect(result.trace.turnId, 'conv_abc_turn_0');
      expect(result.trace.normalize.input, source.text);
      expect(result.trace.segment.output, isNotEmpty);
      expect(result.trace.filter.decisions, isNotEmpty);
      expect(result.trace.decontextualize.spans, isNotEmpty);
    });

    test('does not apply diff to working memory', () async {
      final source = EpisodicSource(
        text: 'ObjectBox is fast.',
        speaker: 'user',
        episodeId: 'conv_abc',
      );

      await encoder.encode(
        source: source,
        turnId: 'conv_abc_turn_0',
        workingMemory: workingMemory,
      );

      // Encoder does NOT apply the diff — caller decides
      expect(workingMemory.state, isEmpty);
    });

    test('accumulates across turns when caller applies diff', () async {
      final source1 = EpisodicSource(
        text: 'ObjectBox supports all six platforms.',
        speaker: 'user',
        episodeId: 'conv_abc',
      );

      final result1 = await encoder.encode(
        source: source1,
        turnId: 'conv_abc_turn_0',
        workingMemory: workingMemory,
      );
      workingMemory.applyDiff(result1.diff);

      expect(workingMemory.state, isNotEmpty);

      final source2 = EpisodicSource(
        text: 'Flutter uses Impeller for rendering.',
        speaker: 'user',
        episodeId: 'conv_abc',
      );

      final result2 = await encoder.encode(
        source: source2,
        turnId: 'conv_abc_turn_1',
        workingMemory: workingMemory,
      );
      workingMemory.applyDiff(result2.diff);

      expect(workingMemory.state.length, greaterThanOrEqualTo(2));
    });
  });
}
