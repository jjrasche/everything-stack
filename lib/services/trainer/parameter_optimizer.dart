/// # Parameter Optimizer Interface
///
/// Abstract interface for parameter optimization strategies.
/// Implementations include Gaussian Process (Bayesian optimization),
/// random search, grid search, etc.

import 'types.dart';

/// Base interface for parameter optimizers
abstract class ParameterOptimizer {
  /// Get parameter bounds for this optimizer
  ParamBounds get paramBounds;

  /// Component type being optimized (e.g., 'context_selector')
  String get componentType;

  /// User ID for multi-user isolation (null = shared)
  String? get userId;

  /// Record a trial outcome (parameter configuration + reward)
  ///
  /// This persists the trial to the database for future use.
  /// Reward should be normalized to [-1, 1] where:
  /// - 1.0 = positive feedback (thumbs up)
  /// - -1.0 = negative feedback (thumbs down)
  Future<void> recordTrial(Map<String, dynamic> params, double reward);

  /// Suggest next parameter configuration to try
  ///
  /// Uses historical trials to suggest promising parameters.
  /// Returns denormalized parameters ready for use.
  Future<Map<String, dynamic>> suggestNext();

  /// Get number of historical trials
  Future<int> getTrialCount();

  /// Clear all historical trials for this component/user
  Future<void> clearHistory();
}
