import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:everything_stack_template/domain/edge.dart';
import 'package:everything_stack_template/domain/edge_repository.dart';
import 'package:everything_stack_template/core/base_entity.dart';

void main() {
  late Isar isar;
  late EdgeRepository repo;

  setUp(() async {
    // Create in-memory Isar instance
    isar = await Isar.open(
      [EdgeSchema],
      directory: '',
      name: 'test_${DateTime.now().millisecondsSinceEpoch}',
    );
    repo = EdgeRepository(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
  });

  group('EdgeRepository', () {
    group('save', () {
      test('saves edge to database', () async {
        final edge = Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        );

        await repo.save(edge);
        final saved = await repo.findBetween('note-1', 'project-1');

        expect(saved, isNotEmpty);
        expect(saved[0].sourceUuid, 'note-1');
        expect(saved[0].targetUuid, 'project-1');
        expect(saved[0].edgeType, 'belongs_to');
      });

      test('enforces uniqueness: composite key sourceUuid+targetUuid+edgeType',
          () async {
        final edge1 = Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        );

        final edge2 = Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        );

        await repo.save(edge1);
        expect(
          () => repo.save(edge2),
          throwsA(isA<DuplicateEdgeException>()),
        );
      });

      test('allows same source and target with different edge types', () async {
        final edge1 = Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        );

        final edge2 = Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'related_to',
        );

        await repo.save(edge1);
        await repo.save(edge2);

        final edges = await repo.findBetween('note-1', 'project-1');
        expect(edges, hasLength(2));
      });

      test('sets createdAt at construction time', () async {
        final beforeCreate = DateTime.now();
        final edge = Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        );
        final afterCreate = DateTime.now();

        await repo.save(edge);
        final saved = await repo.findBetween('note-1', 'project-1');

        // createdAt set at construction, not save
        expect(
            saved[0].createdAt.isBefore(afterCreate) ||
                saved[0].createdAt.isAtSameMomentAs(afterCreate),
            isTrue);
        expect(
            saved[0].createdAt.isAfter(beforeCreate) ||
                saved[0].createdAt.isAtSameMomentAs(beforeCreate),
            isTrue);
      });

      test('preserves metadata when saving', () async {
        final edge = Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
          metadata: '{"strength": 0.95}',
        );

        await repo.save(edge);
        final saved = await repo.findBetween('note-1', 'project-1');

        expect(saved[0].metadata, '{"strength": 0.95}');
      });
    });

    group('delete', () {
      test('deletes edge by composite key', () async {
        final edge = Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        );

        await repo.save(edge);
        await repo.delete('note-1', 'project-1', 'belongs_to');

        final remaining = await repo.findBetween('note-1', 'project-1');
        expect(remaining, isEmpty);
      });

      test('returns false when edge does not exist', () async {
        final deleted = await repo.delete('note-1', 'project-1', 'belongs_to');
        expect(deleted, isFalse);
      });
    });

    group('findBySource', () {
      test('finds all edges from source entity', () async {
        // note-1 -> project-1
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        ));

        // note-1 -> project-2
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-2',
          edgeType: 'belongs_to',
        ));

        // note-2 -> project-1 (different source)
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-2',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        ));

        final edges = await repo.findBySource('note-1');

        expect(edges, hasLength(2));
        expect(
          edges.every((e) => e.sourceUuid == 'note-1'),
          isTrue,
        );
      });

      test('returns empty list when source has no edges', () async {
        final edges = await repo.findBySource('nonexistent');
        expect(edges, isEmpty);
      });
    });

    group('findByTarget', () {
      test('finds all edges to target entity', () async {
        // note-1 -> project-1
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        ));

        // note-2 -> project-1
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-2',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        ));

        // note-1 -> project-2 (different target)
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-2',
          edgeType: 'belongs_to',
        ));

        final edges = await repo.findByTarget('project-1');

        expect(edges, hasLength(2));
        expect(
          edges.every((e) => e.targetUuid == 'project-1'),
          isTrue,
        );
      });

      test('returns empty list when target has no edges', () async {
        final edges = await repo.findByTarget('nonexistent');
        expect(edges, isEmpty);
      });
    });

    group('findBetween', () {
      test('finds all edges between two entities', () async {
        // note-1 -> project-1 (belongs_to)
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        ));

        // note-1 -> project-1 (related_to)
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'related_to',
        ));

        // note-1 -> project-2 (different target)
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-2',
          edgeType: 'belongs_to',
        ));

        final edges = await repo.findBetween('note-1', 'project-1');

        expect(edges, hasLength(2));
        expect(
          edges.every(
              (e) => e.sourceUuid == 'note-1' && e.targetUuid == 'project-1'),
          isTrue,
        );
      });

      test('returns empty list when no edge exists between entities', () async {
        final edges = await repo.findBetween('note-1', 'project-1');
        expect(edges, isEmpty);
      });
    });

    group('findByType', () {
      test('finds all edges of specific type', () async {
        // Setup: multiple edge types
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        ));

        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-2',
          targetType: 'Project',
          targetUuid: 'project-2',
          edgeType: 'belongs_to',
        ));

        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-3',
          targetType: 'Tag',
          targetUuid: 'tag-1',
          edgeType: 'tagged',
        ));

        final belongsToEdges = await repo.findByType('belongs_to');
        final taggedEdges = await repo.findByType('tagged');

        expect(belongsToEdges, hasLength(2));
        expect(
          belongsToEdges.every((e) => e.edgeType == 'belongs_to'),
          isTrue,
        );
        expect(taggedEdges, hasLength(1));
        expect(taggedEdges[0].edgeType, 'tagged');
      });

      test('returns empty list for non-existent edge type', () async {
        final edges = await repo.findByType('nonexistent');
        expect(edges, isEmpty);
      });
    });

    group('traverse', () {
      test('traverses 1-hop outgoing edges', () async {
        // note-1 -> project-1
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        ));

        // note-1 -> project-2
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-2',
          edgeType: 'belongs_to',
        ));

        final results = await repo.traverse(
          startUuid: 'note-1',
          depth: 1,
          direction: 'outgoing',
        );

        expect(results.keys, containsAll(['project-1', 'project-2']));
      });

      test('traverses 1-hop incoming edges', () async {
        // note-1 -> project-1
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        ));

        // note-2 -> project-1
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-2',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        ));

        final results = await repo.traverse(
          startUuid: 'project-1',
          depth: 1,
          direction: 'incoming',
        );

        expect(results.keys, containsAll(['note-1', 'note-2']));
      });

      test('traverses multi-hop (2-depth) outgoing edges', () async {
        // note-1 -> project-1
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        ));

        // project-1 -> team-1 (2-hop)
        await repo.save(Edge(
          sourceType: 'Project',
          sourceUuid: 'project-1',
          targetType: 'Team',
          targetUuid: 'team-1',
          edgeType: 'belongs_to',
        ));

        final results = await repo.traverse(
          startUuid: 'note-1',
          depth: 2,
          direction: 'outgoing',
        );

        expect(results.keys, containsAll(['project-1', 'team-1']));
      });

      test('traverses multi-hop (3-depth) edges', () async {
        // note-1 -> project-1 -> team-1 -> org-1
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        ));

        await repo.save(Edge(
          sourceType: 'Project',
          sourceUuid: 'project-1',
          targetType: 'Team',
          targetUuid: 'team-1',
          edgeType: 'belongs_to',
        ));

        await repo.save(Edge(
          sourceType: 'Team',
          sourceUuid: 'team-1',
          targetType: 'Organization',
          targetUuid: 'org-1',
          edgeType: 'belongs_to',
        ));

        final results = await repo.traverse(
          startUuid: 'note-1',
          depth: 3,
          direction: 'outgoing',
        );

        expect(results.keys, containsAll(['project-1', 'team-1', 'org-1']));
        // Depth information should indicate hop distance
        expect(results['project-1'], 1);
        expect(results['team-1'], 2);
        expect(results['org-1'], 3);
      });

      test('returns empty map for non-existent start UUID', () async {
        final results = await repo.traverse(
          startUuid: 'nonexistent',
          depth: 1,
          direction: 'outgoing',
        );

        expect(results, isEmpty);
      });

      test('does not include start node in results', () async {
        // note-1 -> project-1
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        ));

        final results = await repo.traverse(
          startUuid: 'note-1',
          depth: 1,
          direction: 'outgoing',
        );

        expect(results.containsKey('note-1'), isFalse);
      });

      test('respects direction: only outgoing edges when direction=outgoing',
          () async {
        // note-1 -> project-1 (outgoing from note-1)
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        ));

        // note-2 -> note-1 (incoming to note-1)
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-2',
          targetType: 'Note',
          targetUuid: 'note-1',
          edgeType: 'references',
        ));

        final outgoing = await repo.traverse(
          startUuid: 'note-1',
          depth: 1,
          direction: 'outgoing',
        );

        expect(outgoing.keys, contains('project-1'));
        expect(outgoing.keys, isNot(contains('note-2')));
      });

      test('respects direction: only incoming edges when direction=incoming',
          () async {
        // note-1 -> project-1 (outgoing from note-1)
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        ));

        // note-2 -> note-1 (incoming to note-1)
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-2',
          targetType: 'Note',
          targetUuid: 'note-1',
          edgeType: 'references',
        ));

        final incoming = await repo.traverse(
          startUuid: 'note-1',
          depth: 1,
          direction: 'incoming',
        );

        expect(incoming.keys, contains('note-2'));
        expect(incoming.keys, isNot(contains('project-1')));
      });

      test('handles bidirectional traversal (both directions)', () async {
        // note-1 -> project-1
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        ));

        // note-2 -> note-1
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-2',
          targetType: 'Note',
          targetUuid: 'note-1',
          edgeType: 'references',
        ));

        final both = await repo.traverse(
          startUuid: 'note-1',
          depth: 1,
          direction: 'both',
        );

        expect(both.keys, containsAll(['project-1', 'note-2']));
      });

      test('avoids cycles in multi-hop traversal', () async {
        // Create a cycle: note-1 -> project-1 -> note-1
        await repo.save(Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        ));

        await repo.save(Edge(
          sourceType: 'Project',
          sourceUuid: 'project-1',
          targetType: 'Note',
          targetUuid: 'note-1',
          edgeType: 'contains',
        ));

        final results = await repo.traverse(
          startUuid: 'note-1',
          depth: 3,
          direction: 'outgoing',
        );

        // Should find project-1 at depth 1, but not cycle back to note-1
        expect(results.keys, contains('project-1'));
        expect(results['project-1'], 1);
        // The cycle shouldn't cause infinite recursion, and shouldn't revisit note-1
        final hasRevisited = results.values.where((d) => d > 2).isNotEmpty;
        expect(hasRevisited, isFalse);
      });
    });

    group('sync methods', () {
      test('findUnsynced returns only edges with local status', () async {
        // Create synced edge
        final synced = Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        );
        await repo.save(synced);
        await repo.markSynced(synced.uuid, 'remote-id-1');

        // Create unsynced edge
        final unsynced = Edge(
          sourceType: 'Note',
          sourceUuid: 'note-2',
          targetType: 'Project',
          targetUuid: 'project-2',
          edgeType: 'belongs_to',
        );
        await repo.save(unsynced);

        final unsyncedEdges = await repo.findUnsynced();

        expect(unsyncedEdges, hasLength(1));
        expect(unsyncedEdges[0].uuid, unsynced.uuid);
        expect(unsyncedEdges[0].syncStatus, SyncStatus.local);
      });

      test('markSynced updates syncStatus and syncId', () async {
        final edge = Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        );

        await repo.save(edge);
        expect(edge.syncStatus, SyncStatus.local);
        expect(edge.syncId, isNull);

        await repo.markSynced(edge.uuid, 'remote-edge-123');

        final updated = await repo.findByUuid(edge.uuid);
        expect(updated!.syncStatus, SyncStatus.synced);
        expect(updated.syncId, 'remote-edge-123');
      });

      test('new edges default to local sync status', () async {
        final edge = Edge(
          sourceType: 'Note',
          sourceUuid: 'note-1',
          targetType: 'Project',
          targetUuid: 'project-1',
          edgeType: 'belongs_to',
        );

        await repo.save(edge);
        final saved = await repo.findByUuid(edge.uuid);

        expect(saved!.syncStatus, SyncStatus.local);
      });
    });
  });
}
