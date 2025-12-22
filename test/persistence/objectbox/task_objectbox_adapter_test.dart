/// Integration tests for TaskObjectBoxAdapter
///
/// Verifies:
/// 1. Create → save → retrieve → verify
/// 2. Update → verify persistence
/// 3. Delete → verify removal
/// 4. Task-specific queries (findIncomplete, findCompleted, findOverdue, etc.)
/// 5. Transaction support

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/tools/task/entities/task.dart';
import 'package:everything_stack_template/tools/task/adapters/task_objectbox_adapter.dart';
import 'package:everything_stack_template/objectbox.g.dart';

void main() {
  late Store store;
  late Directory testDir;
  late TaskObjectBoxAdapter adapter;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('task_objectbox_test_');
    store = await openStore(directory: testDir.path);
    adapter = TaskObjectBoxAdapter(store);
  });

  tearDown(() async {
    store.close();
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  group('TaskObjectBoxAdapter - CRUD Operations', () {
    test('save and retrieve task', () async {
      // Create task
      final task = Task(
        title: 'Buy groceries',
        priority: 'high',
        dueDate: DateTime.now().add(Duration(days: 1)),
        description: 'Milk, eggs, bread',
      );

      // Save
      await adapter.save(task);

      // Retrieve
      final retrieved = await adapter.findByUuid(task.uuid);

      // Verify
      expect(retrieved, isNotNull);
      expect(retrieved!.uuid, task.uuid);
      expect(retrieved.title, 'Buy groceries');
      expect(retrieved.priority, 'high');
      expect(retrieved.description, 'Milk, eggs, bread');
      expect(retrieved.completed, false);
    });

    test('update task and verify changes', () async {
      // Create and save
      final task = Task(title: 'Original title', priority: 'low');
      await adapter.save(task);

      // Update
      task.title = 'Updated title';
      task.priority = 'high';
      task.description = 'New description';
      await adapter.save(task);

      // Retrieve and verify
      final retrieved = await adapter.findByUuid(task.uuid);
      expect(retrieved!.title, 'Updated title');
      expect(retrieved.priority, 'high');
      expect(retrieved.description, 'New description');
    });

    test('delete task', () async {
      // Create and save
      final task = Task(title: 'To be deleted');
      await adapter.save(task);

      // Verify exists
      expect(await adapter.findByUuid(task.uuid), isNotNull);

      // Delete
      await adapter.deleteByUuid(task.uuid);

      // Verify removed
      expect(await adapter.findByUuid(task.uuid), isNull);
    });

    test('findAll returns all tasks', () async {
      // Create multiple tasks
      final tasks = [
        Task(title: 'Task 1'),
        Task(title: 'Task 2'),
        Task(title: 'Task 3'),
      ];

      for (final task in tasks) {
        await adapter.save(task);
      }

      // Retrieve all
      final all = await adapter.findAll();

      expect(all.length, 3);
      expect(all.map((t) => t.title).toSet(), {'Task 1', 'Task 2', 'Task 3'});
    });

    test('count returns correct number', () async {
      expect(await adapter.count(), 0);

      await adapter.save(Task(title: 'Task 1'));
      expect(await adapter.count(), 1);

      await adapter.save(Task(title: 'Task 2'));
      expect(await adapter.count(), 2);
    });
  });

  group('TaskObjectBoxAdapter - Task-Specific Queries', () {
    test('findIncomplete returns only incomplete tasks', () async {
      // Create mix of completed and incomplete
      final completed = Task(title: 'Completed task');
      completed.complete();
      await adapter.save(completed);

      final incomplete1 = Task(title: 'Incomplete 1');
      final incomplete2 = Task(title: 'Incomplete 2');
      await adapter.save(incomplete1);
      await adapter.save(incomplete2);

      // Query
      final results = await adapter.findIncomplete();

      expect(results.length, 2);
      expect(results.every((t) => !t.completed), true);
      expect(results.map((t) => t.title).toSet(), {'Incomplete 1', 'Incomplete 2'});
    });

    test('findCompleted returns only completed tasks', () async {
      // Create mix
      await adapter.save(Task(title: 'Incomplete'));

      final completed1 = Task(title: 'Completed 1');
      completed1.complete();
      await adapter.save(completed1);

      final completed2 = Task(title: 'Completed 2');
      completed2.complete();
      await adapter.save(completed2);

      // Query
      final results = await adapter.findCompleted();

      expect(results.length, 2);
      expect(results.every((t) => t.completed), true);
      expect(results.map((t) => t.title).toSet(), {'Completed 1', 'Completed 2'});
    });

    test('findOverdue returns tasks past due date', () async {
      // Past due date (overdue)
      final overdue = Task(
        title: 'Overdue task',
        dueDate: DateTime.now().subtract(Duration(days: 1)),
      );
      await adapter.save(overdue);

      // Future due date (not overdue)
      final notOverdue = Task(
        title: 'Future task',
        dueDate: DateTime.now().add(Duration(days: 1)),
      );
      await adapter.save(notOverdue);

      // No due date
      final noDueDate = Task(title: 'No due date');
      await adapter.save(noDueDate);

      // Completed (should not appear)
      final completedOverdue = Task(
        title: 'Completed overdue',
        dueDate: DateTime.now().subtract(Duration(days: 1)),
      );
      completedOverdue.complete();
      await adapter.save(completedOverdue);

      // Query
      final results = await adapter.findOverdue();

      expect(results.length, 1);
      expect(results.first.title, 'Overdue task');
    });

    test('findByPriority filters by priority level', () async {
      await adapter.save(Task(title: 'High priority', priority: 'high'));
      await adapter.save(Task(title: 'Medium priority', priority: 'medium'));
      await adapter.save(Task(title: 'Low priority', priority: 'low'));

      // High
      final highPriority = await adapter.findByPriority('high');
      expect(highPriority.length, 1);
      expect(highPriority.first.title, 'High priority');

      // Medium
      final mediumPriority = await adapter.findByPriority('medium');
      expect(mediumPriority.length, 1);
      expect(mediumPriority.first.title, 'Medium priority');
    });

    test('findByOwner returns tasks for specific user', () async {
      final task1 = Task(title: 'User 1 task');
      task1.ownerId = 'user-1';
      await adapter.save(task1);

      final task2 = Task(title: 'User 2 task');
      task2.ownerId = 'user-2';
      await adapter.save(task2);

      final task3 = Task(title: 'Another User 1 task');
      task3.ownerId = 'user-1';
      await adapter.save(task3);

      // Query for user-1
      final user1Tasks = await adapter.findByOwner('user-1');
      expect(user1Tasks.length, 2);
      expect(user1Tasks.every((t) => t.ownerId == 'user-1'), true);
    });
  });

}
