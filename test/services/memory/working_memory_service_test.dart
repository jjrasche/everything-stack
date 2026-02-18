import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/proposition.dart';
import 'package:everything_stack_template/services/memory/working_memory_diff.dart';
import 'package:everything_stack_template/services/memory/working_memory_service.dart';

Proposition _makeProposition({
  String content = 'test proposition',
  String scope = 'session',
  String? type,
  String status = 'active',
  String sourceTurnId = 'conv_abc_turn_0',
  String sourceEpisodeId = 'conv_abc',
  List<String> sourceIds = const ['S1'],
}) {
  return Proposition(
    content: content,
    scope: scope,
    type: type,
    sourceIds: sourceIds,
    sourceTurnId: sourceTurnId,
    sourceEpisodeId: sourceEpisodeId,
    status: status,
  );
}

void main() {
  group('WorkingMemoryService', () {
    late WorkingMemoryService service;

    setUp(() {
      service = WorkingMemoryService(maxCapacity: 5);
    });

    test('starts empty', () {
      expect(service.state, isEmpty);
      expect(service.entityList, isEmpty);
    });

    test('applyDiff adds propositions', () {
      final prop = _makeProposition(content: 'ObjectBox supports all 6 platforms');
      final diff = WorkingMemoryDiff(added: [prop]);

      service.applyDiff(diff);

      expect(service.state, hasLength(1));
      expect(service.state.first.content, 'ObjectBox supports all 6 platforms');
    });

    test('applyDiff archives propositions by uuid', () {
      final prop = _makeProposition(content: 'old fact');
      service.applyDiff(WorkingMemoryDiff(added: [prop]));
      expect(service.state, hasLength(1));

      service.applyDiff(WorkingMemoryDiff(archived: [prop.uuid]));
      expect(service.state, isEmpty);
    });

    test('applyDiff supersedes propositions', () {
      final oldProp = _makeProposition(content: 'Flutter uses Skia');
      final newProp = _makeProposition(content: 'Flutter uses Impeller');
      service.applyDiff(WorkingMemoryDiff(added: [oldProp]));

      service.applyDiff(WorkingMemoryDiff(
        superseded: [
          SupersessionRecord(
            oldUuid: oldProp.uuid,
            replacedByUuid: newProp.uuid,
          ),
        ],
        added: [newProp],
      ));

      expect(service.state, hasLength(1));
      expect(service.state.first.content, 'Flutter uses Impeller');
    });

    test('applyDiff handles rewrites', () {
      final oldProp = _makeProposition(content: 'OB is fast');
      final canonical = _makeProposition(content: 'ObjectBox delivers sub-ms queries');
      service.applyDiff(WorkingMemoryDiff(added: [oldProp]));

      service.applyDiff(WorkingMemoryDiff(
        rewritten: [
          RewriteRecord(
            oldUuid: oldProp.uuid,
            mergedIntoUuid: canonical.uuid,
          ),
        ],
        added: [canonical],
      ));

      expect(service.state, hasLength(1));
      expect(service.state.first.content, 'ObjectBox delivers sub-ms queries');
    });

    test('evicts oldest when capacity exceeded', () {
      for (var i = 0; i < 6; i++) {
        final prop = _makeProposition(content: 'fact $i');
        service.applyDiff(WorkingMemoryDiff(added: [prop]));
      }

      expect(service.state, hasLength(5));
      // Oldest (fact 0) should be evicted
      expect(service.state.any((p) => p.content == 'fact 0'), isFalse);
      expect(service.state.any((p) => p.content == 'fact 5'), isTrue);
    });

    test('propositionsAsContext formats for LLM prompt', () {
      service.applyDiff(WorkingMemoryDiff(added: [
        _makeProposition(content: 'Dart is null-safe'),
        _makeProposition(content: 'Flutter supports 6 platforms'),
      ]));

      final context = service.propositionsAsContext();
      expect(context, contains('Dart is null-safe'));
      expect(context, contains('Flutter supports 6 platforms'));
    });

    test('entityList extracts entity names from propositions', () {
      service.applyDiff(WorkingMemoryDiff(added: [
        _makeProposition(content: 'ObjectBox supports HNSW indexing'),
        _makeProposition(content: 'Flutter uses Impeller rendering engine'),
        _makeProposition(content: 'ObjectBox stores data locally'),
      ]));

      // entityList should contain unique names mentioned across propositions
      // Implementation will extract from content — exact behavior tested after impl
      final entities = service.entityList;
      expect(entities, isA<List<String>>());
    });
  });
}
