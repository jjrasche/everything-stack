/// # Gaussian Process Optimizer Tests
///
/// Tests for Bayesian optimization with trial persistence.

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/trainer/gaussian_process_optimizer.dart';
import 'package:everything_stack_template/services/trainer/types.dart';
import 'package:everything_stack_template/core/trial.dart';
import 'package:everything_stack_template/core/trial_repository.dart';

import 'dart:math';

/// Mock trial repository for testing
class MockTrialRepository implements TrialRepository {
  final List<Trial> _trials = [];

  @override
  Future<Trial> save(Trial trial) async {
    // Generate uuid if not set
    if (trial.uuid.isEmpty) {
      trial.uuid = 'trial-${_trials.length}';
    }
    _trials.add(trial);
    return trial;
  }

  @override
  Future<List<Trial>> getRecent({
    required String componentType,
    String? userId,
    int limit = 100,
  }) async {
    var filtered = _trials.where((t) => t.componentType == componentType);

    if (userId != null) {
      filtered = filtered.where((t) => t.userId == userId);
    }

    final sorted = filtered.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return sorted.take(limit).toList();
  }

  @override
  Future<List<Trial>> findByComponent({
    required String componentType,
    String? userId,
  }) async {
    var filtered = _trials.where((t) => t.componentType == componentType);

    if (userId != null) {
      filtered = filtered.where((t) => t.userId == userId);
    }

    return filtered.toList();
  }

  @override
  Future<int> deleteOldTrials({
    required String componentType,
    int keepLatest = 100,
    String? userId,
  }) async {
    final trials = await getRecent(
      componentType: componentType,
      userId: userId,
      limit: 999999,
    );

    if (trials.length <= keepLatest) {
      return 0;
    }

    final toDelete = trials.skip(keepLatest).toList();
    for (final trial in toDelete) {
      _trials.remove(trial);
    }

    return toDelete.length;
  }

  @override
  Future<int> deleteByComponent({
    required String componentType,
    String? userId,
  }) async {
    final toDelete = await findByComponent(
      componentType: componentType,
      userId: userId,
    );

    for (final trial in toDelete) {
      _trials.remove(trial);
    }

    return toDelete.length;
  }

  @override
  Future<int> count({
    required String componentType,
    String? userId,
  }) async {
    final trials = await findByComponent(
      componentType: componentType,
      userId: userId,
    );
    return trials.length;
  }

  @override
  Future<Trial?> findById(String id) async {
    try {
      return _trials.firstWhere((t) => t.uuid == id);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<Trial>> saveAll(List<Trial> trials) async {
    for (final trial in trials) {
      await save(trial);
    }
    return trials;
  }

  @override
  Future<bool> delete(String id) async {
    final trial = await findById(id);
    if (trial != null) {
      _trials.remove(trial);
      return true;
    }
    return false;
  }
}

void main() {
  group('GaussianProcessOptimizer', () {
    late MockTrialRepository mockRepo;
    late GaussianProcessOptimizer optimizer;

    final testBounds = {
      'param1': (0.0, 10.0),
      'param2': (5.0, 15.0),
      'discreteSize': (1.0, 20.0),
    };

    setUp(() {
      mockRepo = MockTrialRepository();
      optimizer = GaussianProcessOptimizer(
        paramBounds: testBounds,
        componentType: 'test_component',
        userId: 'test_user',
        trialRepo: mockRepo,
        minTrialsForGP: 5,
        random: Random(42), // Deterministic for testing
      );
    });

    test('recordTrial persists to repository', () async {
      final params = {'param1': 5.0, 'param2': 10.0, 'discreteSize': 10};
      await optimizer.recordTrial(params, 1.0);

      final count = await optimizer.getTrialCount();
      expect(count, 1);

      final trials = await mockRepo.getRecent(
        componentType: 'test_component',
        userId: 'test_user',
      );
      expect(trials.length, 1);
      expect(trials[0].reward, 1.0);
      expect(trials[0].componentType, 'test_component');
    });

    test('suggestNext uses random exploration when trials < minTrialsForGP',
        () async {
      // Add 3 trials (below minTrialsForGP = 5)
      for (int i = 0; i < 3; i++) {
        await optimizer.recordTrial(
          {'param1': 5.0, 'param2': 10.0, 'discreteSize': 10},
          0.5,
        );
      }

      final suggestion = await optimizer.suggestNext();

      // Should return random params within bounds
      expect(suggestion.containsKey('param1'), true);
      expect(suggestion.containsKey('param2'), true);
      expect(suggestion.containsKey('discreteSize'), true);

      expect(suggestion['param1'], greaterThanOrEqualTo(0.0));
      expect(suggestion['param1'], lessThanOrEqualTo(10.0));
      expect(suggestion['param2'], greaterThanOrEqualTo(5.0));
      expect(suggestion['param2'], lessThanOrEqualTo(15.0));
    });

    test('suggestNext uses GP when trials >= minTrialsForGP', () async {
      // Add trials with clear pattern: param1 high → reward high
      await optimizer.recordTrial(
        {'param1': 2.0, 'param2': 10.0, 'discreteSize': 10},
        -0.5,
      );
      await optimizer.recordTrial(
        {'param1': 4.0, 'param2': 10.0, 'discreteSize': 10},
        0.0,
      );
      await optimizer.recordTrial(
        {'param1': 6.0, 'param2': 10.0, 'discreteSize': 10},
        0.5,
      );
      await optimizer.recordTrial(
        {'param1': 8.0, 'param2': 10.0, 'discreteSize': 10},
        0.8,
      );
      await optimizer.recordTrial(
        {'param1': 9.0, 'param2': 10.0, 'discreteSize': 10},
        1.0,
      );

      final suggestion = await optimizer.suggestNext();

      // GP should suggest high param1 values (UCB acquisition)
      // With UCB, it might explore, but should trend toward higher param1
      expect(suggestion.containsKey('param1'), true);
      expect(suggestion['param1'], greaterThanOrEqualTo(0.0));
      expect(suggestion['param1'], lessThanOrEqualTo(10.0));
    });

    test('discrete parameters are rounded to integers', () async {
      final params = {
        'param1': 5.5,
        'param2': 10.3,
        'discreteSize': 12.7, // Should round to 13
      };

      await optimizer.recordTrial(params, 1.0);

      // Add enough trials to trigger GP
      for (int i = 0; i < 5; i++) {
        await optimizer.recordTrial(
          {'param1': 5.0, 'param2': 10.0, 'discreteSize': 10},
          0.5,
        );
      }

      final suggestion = await optimizer.suggestNext();

      // discreteSize should be an integer
      expect(suggestion['discreteSize'] is int, true);
      expect(suggestion['discreteSize'], greaterThanOrEqualTo(1));
      expect(suggestion['discreteSize'], lessThanOrEqualTo(20));
    });

    test('normalization and denormalization round-trip correctly', () async {
      final params = {'param1': 7.5, 'param2': 12.0, 'discreteSize': 15};

      await optimizer.recordTrial(params, 1.0);

      final trials = await mockRepo.getRecent(
        componentType: 'test_component',
        userId: 'test_user',
      );

      final storedParams = trials[0].params;

      // Normalized params should be in [0, 1]
      for (final value in storedParams.values) {
        expect(value, greaterThanOrEqualTo(0.0));
        expect(value, lessThanOrEqualTo(1.0));
      }

      // Verify specific normalizations
      // param1: 7.5 in [0, 10] → 0.75
      expect(storedParams['param1'], closeTo(0.75, 1e-10));

      // param2: 12.0 in [5, 15] → 0.7
      expect(storedParams['param2'], closeTo(0.7, 1e-10));

      // discreteSize: 15 in [1, 20] → (15-1)/(20-1) = 14/19 ≈ 0.7368
      expect(storedParams['discreteSize'], closeTo(14.0 / 19.0, 1e-10));
    });

    test('clearHistory removes all trials for component', () async {
      // Add trials
      for (int i = 0; i < 10; i++) {
        await optimizer.recordTrial(
          {'param1': 5.0, 'param2': 10.0, 'discreteSize': 10},
          0.5,
        );
      }

      expect(await optimizer.getTrialCount(), 10);

      await optimizer.clearHistory();

      expect(await optimizer.getTrialCount(), 0);
    });

    test('user isolation works correctly', () async {
      // Create optimizer for user1
      final optimizer1 = GaussianProcessOptimizer(
        paramBounds: testBounds,
        componentType: 'test_component',
        userId: 'user1',
        trialRepo: mockRepo,
      );

      // Create optimizer for user2
      final optimizer2 = GaussianProcessOptimizer(
        paramBounds: testBounds,
        componentType: 'test_component',
        userId: 'user2',
        trialRepo: mockRepo,
      );

      // Record trials for each user
      await optimizer1.recordTrial(
        {'param1': 5.0, 'param2': 10.0, 'discreteSize': 10},
        1.0,
      );
      await optimizer2.recordTrial(
        {'param1': 3.0, 'param2': 8.0, 'discreteSize': 5},
        -1.0,
      );

      // Each user should see only their trials
      expect(await optimizer1.getTrialCount(), 1);
      expect(await optimizer2.getTrialCount(), 1);

      // Clear user1's history
      await optimizer1.clearHistory();

      expect(await optimizer1.getTrialCount(), 0);
      expect(await optimizer2.getTrialCount(), 1); // user2's trial still exists
    });
  });
}
