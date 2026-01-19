/// # Context Selector Training Unit Test
///
/// Unit tests for GP-based training logic in ContextSelector.
/// Verifies trial persistence, GP convergence, and parameter updates.

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/core/trial.dart';
import 'package:everything_stack_template/core/trial_repository.dart';
import 'package:everything_stack_template/services/trainer/gaussian_process_optimizer.dart';
import 'dart:math';

/// Mock trial repository for testing
class MockTrialRepository implements TrialRepository {
  final List<Trial> _trials = [];

  @override
  Future<Trial> save(Trial trial) async {
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
  group('ContextSelector GP Training', () {
    late MockTrialRepository trialRepo;

    final testBounds = {
      'conversationThreadSize': (3.0, 15.0),
      'maxSemanticResults': (5.0, 25.0),
      'semanticThreshold': (0.5, 0.9),
    };

    setUp(() {
      trialRepo = MockTrialRepository();
    });

    test('GP optimizer loads historical trials from database', () async {
      // 1. Create synthetic trials (known pattern: higher threadSize = higher reward)
      final trials = [
        Trial(
          componentType: 'context_selector',
          paramsJson: jsonEncode({
            'conversationThreadSize': 0.2, // Normalized
            'maxSemanticResults': 0.5,
            'semanticThreshold': 0.5,
          }),
          reward: 0.3,
        ),
        Trial(
          componentType: 'context_selector',
          paramsJson: jsonEncode({
            'conversationThreadSize': 0.4,
            'maxSemanticResults': 0.5,
            'semanticThreshold': 0.5,
          }),
          reward: 0.5,
        ),
        Trial(
          componentType: 'context_selector',
          paramsJson: jsonEncode({
            'conversationThreadSize': 0.6,
            'maxSemanticResults': 0.5,
            'semanticThreshold': 0.5,
          }),
          reward: 0.7,
        ),
        Trial(
          componentType: 'context_selector',
          paramsJson: jsonEncode({
            'conversationThreadSize': 0.8,
            'maxSemanticResults': 0.5,
            'semanticThreshold': 0.5,
          }),
          reward: 0.9,
        ),
        Trial(
          componentType: 'context_selector',
          paramsJson: jsonEncode({
            'conversationThreadSize': 1.0,
            'maxSemanticResults': 0.5,
            'semanticThreshold': 0.5,
          }),
          reward: 1.0,
        ),
      ];

      // 2. Save trials to database
      for (final trial in trials) {
        await trialRepo.save(trial);
      }

      // 3. Verify trials persisted
      final loadedTrials = await trialRepo.getRecent(
        componentType: 'context_selector',
        userId: null,
        limit: 100,
      );

      expect(loadedTrials.length, 5);

      // 4. Create GP optimizer (should load trials from database)
      final optimizer = GaussianProcessOptimizer(
        paramBounds: testBounds,
        componentType: 'context_selector',
        userId: null,
        trialRepo: trialRepo,
        minTrialsForGP: 5,
      );

      // 5. Verify optimizer loaded trials
      expect(await optimizer.getTrialCount(), 5);

      // 6. Get GP suggestion
      final suggestion = await optimizer.suggestNext();

      expect(suggestion['conversationThreadSize'], greaterThanOrEqualTo(10));
    });

    test('GP converges to optimum within 20 trials', () async {
      // Define synthetic reward function
      // Optimal: conversationThreadSize=12, maxSemanticResults=20, semanticThreshold=0.8
      double syntheticReward(Map<String, dynamic> params) {
        final threadSize = params['conversationThreadSize'] as int;
        final semanticResults = params['maxSemanticResults'] as int;
        final threshold = params['semanticThreshold'] as double;

        final threadDist = (threadSize - 12).abs() / 12.0;
        final semanticDist = (semanticResults - 20).abs() / 20.0;
        final thresholdDist = (threshold - 0.8).abs() / 0.3;

        final totalDist = (threadDist + semanticDist + thresholdDist) / 3.0;

        return 1.0 - totalDist;
      }

      final optimizer = GaussianProcessOptimizer(
        paramBounds: testBounds,
        componentType: 'context_selector',
        userId: null,
        trialRepo: trialRepo,
        minTrialsForGP: 5,
        random: Random(42), // Deterministic
      );

      double bestReward = -1.0;
      Map<String, dynamic>? bestParams;

      // Run 20 trials
      print('\n🧪 Starting GP optimization (target: threadSize=12, semantic=20, threshold=0.8)\n');

      for (int i = 0; i < 20; i++) {
        final params = await optimizer.suggestNext();
        final reward = syntheticReward(params);

        await optimizer.recordTrial(params, reward);

        if (reward > bestReward) {
          bestReward = reward;
          bestParams = params;
          print('🎯 NEW BEST (trial $i): reward=${reward.toStringAsFixed(3)} | '
              'threadSize=${params['conversationThreadSize']}, '
              'semantic=${params['maxSemanticResults']}, '
              'threshold=${(params['semanticThreshold'] as double).toStringAsFixed(2)}');
        } else {
          print('   Trial $i: reward=${reward.toStringAsFixed(3)} | '
              'threadSize=${params['conversationThreadSize']}, '
              'semantic=${params['maxSemanticResults']}, '
              'threshold=${(params['semanticThreshold'] as double).toStringAsFixed(2)}');
        }
      }

      print('\n✅ FINAL RESULT:');
      print('   Best reward: ${bestReward.toStringAsFixed(3)}');
      print('   Best params: threadSize=${bestParams!['conversationThreadSize']}, '
          'semantic=${bestParams['maxSemanticResults']}, '
          'threshold=${(bestParams['semanticThreshold'] as double).toStringAsFixed(2)}');
      print('   Target:      threadSize=12, semantic=20, threshold=0.80\n');

      // Verify convergence
      expect(bestReward, greaterThan(0.7));

      // Verify best params are close to optimal
      expect(bestParams!['conversationThreadSize'], greaterThanOrEqualTo(10));
      expect(bestParams['conversationThreadSize'], lessThanOrEqualTo(15));
    });

    test('trials persist across optimizer restarts', () async {
      // Create optimizer and record trials
      final optimizer1 = GaussianProcessOptimizer(
        paramBounds: testBounds,
        componentType: 'context_selector',
        userId: null,
        trialRepo: trialRepo,
      );

      await optimizer1.recordTrial({
        'conversationThreadSize': 8,
        'maxSemanticResults': 12,
        'semanticThreshold': 0.7,
      }, 0.5);

      await optimizer1.recordTrial({
        'conversationThreadSize': 10,
        'maxSemanticResults': 15,
        'semanticThreshold': 0.75,
      }, 0.8);

      expect(await optimizer1.getTrialCount(), 2);

      // Create NEW optimizer instance (simulates app restart)
      final optimizer2 = GaussianProcessOptimizer(
        paramBounds: testBounds,
        componentType: 'context_selector',
        userId: null,
        trialRepo: trialRepo,
      );

      // Should see same trials
      expect(await optimizer2.getTrialCount(), 2);

      // Add another trial
      await optimizer2.recordTrial({
        'conversationThreadSize': 12,
        'maxSemanticResults': 18,
        'semanticThreshold': 0.8,
      }, 0.9);

      expect(await optimizer2.getTrialCount(), 3);
    });
  });
}
