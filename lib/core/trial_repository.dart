/// Manages trial records for GP training across all trainable components.

import 'trial.dart';

abstract class TrialRepository {
  /// Get recent trials for a component (most recent first)
  ///
  /// Used by GP optimizer to load historical trials for training.
  ///
  /// Parameters:
  /// - [componentType]: Which component ('context_selector', 'tool_selector', etc.)
  /// - [userId]: Optional user ID for multi-user isolation (null = all users)
  /// - [limit]: Maximum number of trials to return (default: 100)
  ///
  /// Returns: Trials ordered by createdAt DESC (newest first)
  Future<List<Trial>> getRecent({
    required String componentType,
    String? userId,
    int limit = 100,
  });

  /// Find all trials for a component
  ///
  /// Parameters:
  /// - [componentType]: Which component
  /// - [userId]: Optional user ID filter
  ///
  /// Returns: All trials for that component
  Future<List<Trial>> findByComponent({
    required String componentType,
    String? userId,
  });

  /// Find trial by ID
  ///
  /// Parameters:
  /// - [id]: Trial UUID
  ///
  /// Returns: Trial if found, null otherwise
  Future<Trial?> findById(String id);

  /// Save trial
  ///
  /// Parameters:
  /// - [trial]: Trial to save
  ///
  /// Returns: Saved trial
  Future<Trial> save(Trial trial);

  /// Save multiple trials (batch operation)
  ///
  /// Parameters:
  /// - [trials]: Trials to save
  ///
  /// Returns: Saved trials
  Future<List<Trial>> saveAll(List<Trial> trials);

  /// Delete trial
  ///
  /// Parameters:
  /// - [id]: Trial UUID
  ///
  /// Returns: true if deleted, false if not found
  Future<bool> delete(String id);

  /// Delete old trials (keep latest N per component)
  ///
  /// Used to prevent unbounded growth of trial history.
  ///
  /// Parameters:
  /// - [componentType]: Which component to clean
  /// - [keepLatest]: How many recent trials to keep (default: 100)
  /// - [userId]: Optional user ID (null = all users)
  ///
  /// Returns: Number of trials deleted
  Future<int> deleteOldTrials({
    required String componentType,
    int keepLatest = 100,
    String? userId,
  });

  /// Delete all trials for a component
  ///
  /// Parameters:
  /// - [componentType]: Which component
  /// - [userId]: Optional user ID
  ///
  /// Returns: Number of trials deleted
  Future<int> deleteByComponent({
    required String componentType,
    String? userId,
  });

  /// Get count of trials for a component
  ///
  /// Parameters:
  /// - [componentType]: Which component
  /// - [userId]: Optional user ID
  ///
  /// Returns: Number of trials
  Future<int> count({
    required String componentType,
    String? userId,
  });
}
