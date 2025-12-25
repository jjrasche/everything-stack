/// # NamespaceAdaptationState (DEPRECATED)
///
/// ## Status
/// This class was previously embedded in the Personality entity.
/// It's being migrated to the generic AdaptationState pattern with JSON storage.
///
/// Use lib/domain/adaptation_state_generic.dart with componentType: 'namespace_selector'
/// instead of this class going forward.
///
/// KEEP THIS CLASS for backward compatibility only - existing code may still reference it.

/// Embedded value object - NOT a separate @Entity
class NamespaceAdaptationState {
  // ============ Threshold configuration ============

  /// Per-namespace semantic similarity thresholds (0.0-1.0)
  /// Lower = more likely to trigger (high attention)
  /// Higher = less likely to trigger (low attention)
  /// Example: {"task": 0.7, "timer": 0.65, "health": 0.8}
  Map<String, double> namespaceThresholds = {};

  // ============ Learned centroids ============

  /// Per-namespace semantic centroids (embedding vectors)
  /// Initially computed from namespace descriptions
  /// Updated via moving average from positive feedback
  Map<String, List<double>> namespaceCentroids = {};

  // ============ Learning parameters ============

  /// How fast centroids adapt (0.0-1.0)
  /// Higher = faster adaptation, less stability
  /// Lower = slower adaptation, more stability
  double centroidLearningRate = 0.1;

  /// How fast thresholds adapt (0.0-1.0)
  double thresholdLearningRate = 0.05;

  // ============ Version & audit ============

  /// Version for optimistic locking
  int version = 0;

  /// When this state was last trained
  DateTime lastTrainedAt = DateTime.now();

  /// How many training samples have been applied
  int trainingSampleCount = 0;

  // ============ Constructor ============

  NamespaceAdaptationState();

  // ============ Threshold operations ============

  /// Get threshold for a namespace (default: 0.7)
  double getThreshold(String namespaceId) {
    return namespaceThresholds[namespaceId] ?? 0.7;
  }

  /// Set threshold for a namespace
  void setThreshold(String namespaceId, double threshold) {
    namespaceThresholds[namespaceId] = threshold.clamp(0.0, 1.0);
  }

  /// Increase threshold (make harder to trigger)
  void raiseThreshold(String namespaceId) {
    final current = getThreshold(namespaceId);
    setThreshold(namespaceId, current + thresholdLearningRate);
  }

  /// Decrease threshold (make easier to trigger)
  void lowerThreshold(String namespaceId) {
    final current = getThreshold(namespaceId);
    setThreshold(namespaceId, current - thresholdLearningRate);
  }

  // ============ Centroid operations ============

  /// Get centroid for a namespace
  List<double>? getCentroid(String namespaceId) {
    return namespaceCentroids[namespaceId];
  }

  /// Set centroid for a namespace
  void setCentroid(String namespaceId, List<double> centroid) {
    namespaceCentroids[namespaceId] = centroid;
  }

  /// Update centroid via moving average
  /// newCentroid = (1 - learningRate) * oldCentroid + learningRate * sample
  void updateCentroid(String namespaceId, List<double> sample) {
    final old = getCentroid(namespaceId);
    if (old == null || old.length != sample.length) {
      setCentroid(namespaceId, sample);
      return;
    }

    final updated = <double>[];
    for (var i = 0; i < old.length; i++) {
      updated.add((1 - centroidLearningRate) * old[i] +
          centroidLearningRate * sample[i]);
    }
    setCentroid(namespaceId, updated);
  }

  // ============ Training ============

  /// Record that training was applied
  void recordTraining() {
    version++;
    trainingSampleCount++;
    lastTrainedAt = DateTime.now();
  }

  // ============ Serialization ============

  Map<String, dynamic> toJson() => {
        'namespaceThresholds': namespaceThresholds,
        'namespaceCentroids': namespaceCentroids,
        'centroidLearningRate': centroidLearningRate,
        'thresholdLearningRate': thresholdLearningRate,
        'version': version,
        'lastTrainedAt': lastTrainedAt.toIso8601String(),
        'trainingSampleCount': trainingSampleCount,
      };

  factory NamespaceAdaptationState.fromJson(Map<String, dynamic> json) {
    final state = NamespaceAdaptationState();

    if (json['namespaceThresholds'] != null) {
      state.namespaceThresholds =
          (json['namespaceThresholds'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()));
    }

    if (json['namespaceCentroids'] != null) {
      state.namespaceCentroids = (json['namespaceCentroids']
              as Map<String, dynamic>)
          .map((k, v) => MapEntry(k,
              (v as List<dynamic>).map((e) => (e as num).toDouble()).toList()));
    }

    state.centroidLearningRate =
        (json['centroidLearningRate'] as num?)?.toDouble() ?? 0.1;
    state.thresholdLearningRate =
        (json['thresholdLearningRate'] as num?)?.toDouble() ?? 0.05;
    state.version = json['version'] as int? ?? 0;
    state.lastTrainedAt = json['lastTrainedAt'] != null
        ? DateTime.parse(json['lastTrainedAt'] as String)
        : DateTime.now();
    state.trainingSampleCount = json['trainingSampleCount'] as int? ?? 0;

    return state;
  }
}
