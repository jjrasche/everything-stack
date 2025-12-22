/// Integration tests for TimerIndexedDBAdapter
///
/// Verifies:
/// 1. Create → save → retrieve → verify
/// 2. Update → verify persistence
/// 3. Delete → verify removal
/// 4. Timer-specific queries (findActive, findExpired, findFired, findByLabel)
/// 5. Cross-platform query equivalence with ObjectBox

import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:everything_stack_template/tools/timer/entities/timer.dart';
import 'package:everything_stack_template/tools/timer/adapters/timer_indexeddb_adapter.dart';

void main() {
  late IdbFactory idbFactory;
  late Database db;
  late TimerIndexedDBAdapter adapter;

  setUp(() async {
    // Use in-memory IndexedDB for testing
    idbFactory = newIdbFactoryMemory();

    // Open database and create object store
    db = await idbFactory.open(
      'timer_test_db',
      version: 1,
      onUpgradeNeeded: (VersionChangeEvent event) {
        final db = event.database;

        // Create 'timers' object store with uuid as keyPath
        final store = db.createObjectStore('timers', keyPath: 'uuid');

        // Create index on 'id' field for findById queries
        store.createIndex('id', 'id', unique: false);
      },
    );

    adapter = TimerIndexedDBAdapter(db);
  });

  tearDown(() async {
    db.close();
    await idbFactory.deleteDatabase('timer_test_db');
  });

  group('TimerIndexedDBAdapter - CRUD Operations', () {
    test('save and retrieve timer', () async {
      final now = DateTime.now();
      final endsAt = now.add(Duration(minutes: 5));

      // Create timer
      final timer = Timer(
        label: '5 minute break',
        durationSeconds: 300,
        setAt: now,
        endsAt: endsAt,
      );

      // Save
      await adapter.save(timer);

      // Retrieve
      final retrieved = await adapter.findByUuid(timer.uuid);

      // Verify
      expect(retrieved, isNotNull);
      expect(retrieved!.uuid, timer.uuid);
      expect(retrieved.label, '5 minute break');
      expect(retrieved.durationSeconds, 300);
      expect(retrieved.fired, false);
    });

    test('update timer and verify changes', () async {
      // Create and save
      final now = DateTime.now();
      final timer = Timer(
        label: 'Original label',
        durationSeconds: 60,
        setAt: now,
        endsAt: now.add(Duration(seconds: 60)),
      );
      await adapter.save(timer);

      // Update
      timer.label = 'Updated label';
      timer.fire();
      await adapter.save(timer);

      // Retrieve and verify
      final retrieved = await adapter.findByUuid(timer.uuid);
      expect(retrieved!.label, 'Updated label');
      expect(retrieved.fired, true);
      expect(retrieved.firedAt, isNotNull);
    });

    test('delete timer', () async {
      // Create and save
      final now = DateTime.now();
      final timer = Timer(
        label: 'To be deleted',
        durationSeconds: 30,
        setAt: now,
        endsAt: now.add(Duration(seconds: 30)),
      );
      await adapter.save(timer);

      // Verify exists
      expect(await adapter.findByUuid(timer.uuid), isNotNull);

      // Delete
      await adapter.deleteByUuid(timer.uuid);

      // Verify removed
      expect(await adapter.findByUuid(timer.uuid), isNull);
    });

    test('findAll returns all timers', () async {
      // Create multiple timers
      final now = DateTime.now();
      final timers = [
        Timer(
          label: 'Timer 1',
          durationSeconds: 60,
          setAt: now,
          endsAt: now.add(Duration(seconds: 60)),
        ),
        Timer(
          label: 'Timer 2',
          durationSeconds: 120,
          setAt: now,
          endsAt: now.add(Duration(seconds: 120)),
        ),
        Timer(
          label: 'Timer 3',
          durationSeconds: 180,
          setAt: now,
          endsAt: now.add(Duration(seconds: 180)),
        ),
      ];

      for (final timer in timers) {
        await adapter.save(timer);
      }

      // Retrieve all
      final all = await adapter.findAll();

      expect(all.length, 3);
      expect(all.map((t) => t.label).toSet(), {'Timer 1', 'Timer 2', 'Timer 3'});
    });

    test('count returns correct number', () async {
      expect(await adapter.count(), 0);

      final now = DateTime.now();
      await adapter.save(Timer(
        label: 'Timer 1',
        durationSeconds: 60,
        setAt: now,
        endsAt: now.add(Duration(seconds: 60)),
      ));
      expect(await adapter.count(), 1);

      await adapter.save(Timer(
        label: 'Timer 2',
        durationSeconds: 120,
        setAt: now,
        endsAt: now.add(Duration(seconds: 120)),
      ));
      expect(await adapter.count(), 2);
    });
  });

  group('TimerIndexedDBAdapter - Timer-Specific Queries', () {
    test('findActive returns only active timers', () async {
      final now = DateTime.now();

      // Active timer (not fired, ends in future)
      final active = Timer(
        label: 'Active timer',
        durationSeconds: 300,
        setAt: now,
        endsAt: now.add(Duration(minutes: 5)),
      );
      await adapter.save(active);

      // Expired timer (not fired, but endsAt is past)
      final expired = Timer(
        label: 'Expired timer',
        durationSeconds: 60,
        setAt: now.subtract(Duration(minutes: 2)),
        endsAt: now.subtract(Duration(minutes: 1)),
      );
      await adapter.save(expired);

      // Fired timer
      final fired = Timer(
        label: 'Fired timer',
        durationSeconds: 120,
        setAt: now.subtract(Duration(minutes: 3)),
        endsAt: now.subtract(Duration(minutes: 1)),
      );
      fired.fire();
      await adapter.save(fired);

      // Query
      final results = await adapter.findActive();

      expect(results.length, 1);
      expect(results.first.label, 'Active timer');
      expect(results.first.isActive, true);
    });

    test('findExpired returns only expired timers', () async {
      final now = DateTime.now();

      // Active timer (not expired)
      final active = Timer(
        label: 'Active timer',
        durationSeconds: 300,
        setAt: now,
        endsAt: now.add(Duration(minutes: 5)),
      );
      await adapter.save(active);

      // Expired timer (past endsAt but not marked as fired)
      final expired = Timer(
        label: 'Expired timer',
        durationSeconds: 60,
        setAt: now.subtract(Duration(minutes: 2)),
        endsAt: now.subtract(Duration(minutes: 1)),
      );
      await adapter.save(expired);

      // Fired timer (should not appear in expired)
      final fired = Timer(
        label: 'Fired timer',
        durationSeconds: 120,
        setAt: now.subtract(Duration(minutes: 3)),
        endsAt: now.subtract(Duration(minutes: 1)),
      );
      fired.fire();
      await adapter.save(fired);

      // Query
      final results = await adapter.findExpired();

      expect(results.length, 1);
      expect(results.first.label, 'Expired timer');
      expect(results.first.hasExpired, true);
    });

    test('findFired returns only fired timers', () async {
      final now = DateTime.now();

      // Active timer
      final active = Timer(
        label: 'Active timer',
        durationSeconds: 300,
        setAt: now,
        endsAt: now.add(Duration(minutes: 5)),
      );
      await adapter.save(active);

      // Fired timer 1
      final fired1 = Timer(
        label: 'Fired 1',
        durationSeconds: 60,
        setAt: now.subtract(Duration(minutes: 2)),
        endsAt: now.subtract(Duration(minutes: 1)),
      );
      fired1.fire();
      await adapter.save(fired1);

      // Fired timer 2 (cancelled)
      final fired2 = Timer(
        label: 'Fired 2',
        durationSeconds: 120,
        setAt: now,
        endsAt: now.add(Duration(minutes: 2)),
      );
      fired2.cancel();
      await adapter.save(fired2);

      // Query
      final results = await adapter.findFired();

      expect(results.length, 2);
      expect(results.every((t) => t.fired), true);
      expect(results.map((t) => t.label).toSet(), {'Fired 1', 'Fired 2'});
    });

    test('findByLabel returns timer with matching label', () async {
      final now = DateTime.now();

      // Create multiple timers
      final timer1 = Timer(
        label: 'pasta',
        durationSeconds: 600,
        setAt: now,
        endsAt: now.add(Duration(minutes: 10)),
      );
      await adapter.save(timer1);

      final timer2 = Timer(
        label: 'meeting',
        durationSeconds: 300,
        setAt: now,
        endsAt: now.add(Duration(minutes: 5)),
      );
      await adapter.save(timer2);

      // Fired timer with same label (should not be found)
      final firedPasta = Timer(
        label: 'pasta',
        durationSeconds: 600,
        setAt: now.subtract(Duration(minutes: 11)),
        endsAt: now.subtract(Duration(minutes: 1)),
      );
      firedPasta.fire();
      await adapter.save(firedPasta);

      // Query for 'pasta'
      final result = await adapter.findByLabel('pasta');
      expect(result, isNotNull);
      expect(result!.label, 'pasta');
      expect(result.fired, false);

      // Query for non-existent label
      final notFound = await adapter.findByLabel('nonexistent');
      expect(notFound, isNull);
    });
  });

  group('TimerIndexedDBAdapter - Time-Based Behavior', () {
    test('timer state transitions correctly', () async {
      final now = DateTime.now();

      // Create timer ending in 2 seconds (more buffer for test reliability)
      final timer = Timer(
        label: 'Short timer',
        durationSeconds: 2,
        setAt: now,
        endsAt: now.add(Duration(seconds: 2)),
      );
      await adapter.save(timer);

      // Initially active
      expect(timer.isActive, true);
      expect(timer.hasExpired, false);
      expect(timer.fired, false);

      // Wait for expiry with buffer for clock precision
      await Future.delayed(Duration(milliseconds: 2200));

      // Now expired but not fired
      final retrieved = await adapter.findByUuid(timer.uuid);
      expect(retrieved!.isActive, false);
      expect(retrieved.hasExpired, true);
      expect(retrieved.fired, false);

      // Fire it
      retrieved.fire();
      await adapter.save(retrieved);

      // Now fired
      final firedTimer = await adapter.findByUuid(timer.uuid);
      expect(firedTimer!.fired, true);
      expect(firedTimer.firedAt, isNotNull);
    });

    test('cancelled timer is marked as fired but with null firedAt', () async {
      final now = DateTime.now();
      final timer = Timer(
        label: 'Cancel test',
        durationSeconds: 300,
        setAt: now,
        endsAt: now.add(Duration(minutes: 5)),
      );
      await adapter.save(timer);

      // Cancel it
      timer.cancel();
      await adapter.save(timer);

      // Verify cancelled state
      final retrieved = await adapter.findByUuid(timer.uuid);
      expect(retrieved!.fired, true);
      expect(retrieved.firedAt, isNull);
      expect(retrieved.wasCancelled, true);
    });
  });

  group('TimerIndexedDBAdapter - Cross-Platform Equivalence', () {
    test('query results match ObjectBox behavior', () async {
      final now = DateTime.now();

      // Create same dataset as ObjectBox tests
      final timers = [
        Timer(
          label: 'Active 1',
          durationSeconds: 300,
          setAt: now,
          endsAt: now.add(Duration(minutes: 5)),
        ),
        Timer(
          label: 'Active 2',
          durationSeconds: 600,
          setAt: now,
          endsAt: now.add(Duration(minutes: 10)),
        ),
        Timer(
          label: 'Expired',
          durationSeconds: 60,
          setAt: now.subtract(Duration(minutes: 2)),
          endsAt: now.subtract(Duration(minutes: 1)),
        ),
        Timer(
          label: 'Fired',
          durationSeconds: 120,
          setAt: now.subtract(Duration(minutes: 3)),
          endsAt: now.subtract(Duration(minutes: 1)),
        )..fire(),
      ];

      for (final timer in timers) {
        await adapter.save(timer);
      }

      // Verify cross-platform query equivalence
      expect((await adapter.findActive()).length, 2);
      expect((await adapter.findExpired()).length, 1);
      expect((await adapter.findFired()).length, 1);
    });
  });
}
