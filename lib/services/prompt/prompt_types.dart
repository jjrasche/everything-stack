/// Generic types for the prompt improvement system.
///
/// Any component that uses LLM prompts can plug into the improvement
/// loop by implementing PromptFailure and providing DimensionSpecs.

typedef MetricMap = Map<String, double>;

/// A single output that failed evaluation, with per-dimension scores.
abstract class PromptFailure {
  String get outputContent;
  Map<String, bool> get dimensionScores;
  String get reasoning;
}

/// Describes one evaluation dimension for the mutator.
///
/// [failureGuidance] tells the LLM how to fix the prompt when this
/// dimension fails (e.g., "add clearer instructions about one-fact-per-insight").
class DimensionSpec {
  final String name;
  final double weight;
  final String failureGuidance;

  const DimensionSpec({
    required this.name,
    required this.weight,
    required this.failureGuidance,
  });
}
