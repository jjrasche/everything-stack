/// # ToolSelectionAdaptationState
///
/// ## What it does
/// Stores learned weights for tool selection within a specific namespace.
/// Statistical classifier: tracks success rates and keyword associations per tool.
/// EMBEDDED inside Personality.toolAttentionPerNamespace[namespaceId].
///
/// ## Two-hop architecture
/// 1. LLM picks namespace (uses NamespaceAdaptationState thresholds)
/// 2. Statistical classifier picks tool (uses THIS state)
///
/// ## Key insight
/// Once LLM says "this is a task request", the statistical classifier
/// decides between task.create, task.complete, task.list, etc.
/// This keeps the LLM call count low while allowing fine-grained tool selection.
///
/// ## Training
/// When user feedback indicates wrong tool:
/// - Decrease success rate for wrongly-selected tool
/// - Increase success rate for correct tool
/// - Update keyword weights to associate correction patterns
///
/// ## Usage
/// ```dart
/// // Access via Personality
/// final personality = await personalityRepo.getActive();
/// final taskState = personality.toolAttentionPerNamespace['task'];
///
/// // Score a tool
/// final score = taskState.scoreTool('create', utteranceKeywords);
/// ```

/// Embedded value object - NOT a separate @Entity
class ToolSelectionAdaptationState {
  // ============ Identity ============

  /// Which namespace is this for?
  String namespaceId;

  // ============ Tool success rates ============

  /// Per-tool historical success rates (0.0-1.0)
  /// Higher = more likely to be correct
  /// Example: {"create": 0.85, "complete": 0.72, "list": 0.90}
  Map<String, double> toolSuccessRates = {};

  // ============ Keyword weights ============

  /// Per-tool keyword association weights
  /// Maps tool -> keyword -> weight
  /// Example: {"create": {"add": 1.5, "new": 1.3}, "complete": {"done": 1.8, "finish": 1.6}}
  Map<String, Map<String, double>> toolKeywordWeights = {};

  // ============ Learning parameters ============

  /// How fast success rates adapt (0.0-1.0)
  double successRateLearningRate = 0.1;

  /// How fast keyword weights adapt (0.0-1.0)
  double keywordLearningRate = 0.05;

  // ============ Version & audit ============

  int version = 0;
  DateTime lastTrainedAt = DateTime.now();
  int trainingSampleCount = 0;

  // ============ Constructor ============

  ToolSelectionAdaptationState({required this.namespaceId});

  // ============ Success rate operations ============

  /// Get success rate for a tool (default: 0.5)
  double getSuccessRate(String toolName) {
    return toolSuccessRates[toolName] ?? 0.5;
  }

  /// Set success rate for a tool
  void setSuccessRate(String toolName, double rate) {
    toolSuccessRates[toolName] = rate.clamp(0.0, 1.0);
  }

  /// Increase success rate (positive feedback)
  void boostSuccessRate(String toolName) {
    final current = getSuccessRate(toolName);
    setSuccessRate(toolName, current + successRateLearningRate * (1 - current));
  }

  /// Decrease success rate (negative feedback)
  void penalizeSuccessRate(String toolName) {
    final current = getSuccessRate(toolName);
    setSuccessRate(toolName, current - successRateLearningRate * current);
  }

  // ============ Keyword weight operations ============

  /// Get weight for a keyword on a tool (default: 1.0)
  double getKeywordWeight(String toolName, String keyword) {
    return toolKeywordWeights[toolName]?[keyword] ?? 1.0;
  }

  /// Set weight for a keyword on a tool
  void setKeywordWeight(String toolName, String keyword, double weight) {
    toolKeywordWeights.putIfAbsent(toolName, () => {});
    toolKeywordWeights[toolName]![keyword] = weight.clamp(0.1, 5.0);
  }

  /// Boost keyword weight (positive association)
  void boostKeyword(String toolName, String keyword) {
    final current = getKeywordWeight(toolName, keyword);
    setKeywordWeight(toolName, keyword, current + keywordLearningRate);
  }

  /// Penalize keyword weight (negative association)
  void penalizeKeyword(String toolName, String keyword) {
    final current = getKeywordWeight(toolName, keyword);
    setKeywordWeight(toolName, keyword, current - keywordLearningRate);
  }

  // ============ Scoring ============

  /// Score a tool given utterance keywords
  /// Returns: successRate * sum(keywordWeights)
  double scoreTool(String toolName, List<String> keywords) {
    final successRate = getSuccessRate(toolName);
    var keywordScore = 0.0;

    for (final keyword in keywords) {
      keywordScore += getKeywordWeight(toolName, keyword);
    }

    // Normalize by keyword count to avoid length bias
    if (keywords.isNotEmpty) {
      keywordScore /= keywords.length;
    } else {
      keywordScore = 1.0;
    }

    return successRate * keywordScore;
  }

  /// Score all known tools and return sorted by score
  List<MapEntry<String, double>> rankTools(List<String> keywords) {
    final scores = <String, double>{};

    for (final toolName in toolSuccessRates.keys) {
      scores[toolName] = scoreTool(toolName, keywords);
    }

    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted;
  }

  // ============ Training ============

  /// Record that training was applied
  void recordTraining() {
    version++;
    trainingSampleCount++;
    lastTrainedAt = DateTime.now();
  }

  /// Apply feedback: boost correct tool, penalize wrong one
  void applyFeedback({
    required String selectedTool,
    required String correctTool,
    required List<String> keywords,
  }) {
    if (selectedTool == correctTool) {
      // Positive feedback: boost this tool
      boostSuccessRate(correctTool);
      for (final keyword in keywords) {
        boostKeyword(correctTool, keyword);
      }
    } else {
      // Negative feedback: penalize selected, boost correct
      penalizeSuccessRate(selectedTool);
      boostSuccessRate(correctTool);
      for (final keyword in keywords) {
        penalizeKeyword(selectedTool, keyword);
        boostKeyword(correctTool, keyword);
      }
    }
    recordTraining();
  }

  // ============ Serialization ============

  Map<String, dynamic> toJson() => {
        'namespaceId': namespaceId,
        'toolSuccessRates': toolSuccessRates,
        'toolKeywordWeights': toolKeywordWeights,
        'successRateLearningRate': successRateLearningRate,
        'keywordLearningRate': keywordLearningRate,
        'version': version,
        'lastTrainedAt': lastTrainedAt.toIso8601String(),
        'trainingSampleCount': trainingSampleCount,
      };

  factory ToolSelectionAdaptationState.fromJson(Map<String, dynamic> json) {
    final state = ToolSelectionAdaptationState(
      namespaceId: json['namespaceId'] as String,
    );

    if (json['toolSuccessRates'] != null) {
      state.toolSuccessRates =
          (json['toolSuccessRates'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()));
    }

    if (json['toolKeywordWeights'] != null) {
      state.toolKeywordWeights =
          (json['toolKeywordWeights'] as Map<String, dynamic>).map(
        (toolName, weights) => MapEntry(
          toolName,
          (weights as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble())),
        ),
      );
    }

    state.successRateLearningRate =
        (json['successRateLearningRate'] as num?)?.toDouble() ?? 0.1;
    state.keywordLearningRate =
        (json['keywordLearningRate'] as num?)?.toDouble() ?? 0.05;
    state.version = json['version'] as int? ?? 0;
    state.lastTrainedAt = json['lastTrainedAt'] != null
        ? DateTime.parse(json['lastTrainedAt'] as String)
        : DateTime.now();
    state.trainingSampleCount = json['trainingSampleCount'] as int? ?? 0;

    return state;
  }
}
