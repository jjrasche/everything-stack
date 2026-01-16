/// # Enrichable Interface
///
/// Entities that need async enrichment implement this interface.
/// Entity explicitly declares which enrichment steps it needs.
///
/// ## Usage
///
/// ```dart
/// class Invocation extends BaseEntity with SemanticIndexable implements Enrichable {
///   @override
///   List<String> get enrichmentSteps => ['semantic_enrichment'];
/// }
///
/// class Task extends BaseEntity with SemanticIndexable, Categorizable implements Enrichable {
///   @override
///   List<String> get enrichmentSteps => ['semantic_enrichment', 'categorization'];
/// }
/// ```
///
/// ## Why Explicit Declaration?
///
/// - No fragile `super.addEnrichmentSteps()` chains
/// - Mixin order doesn't affect behavior
/// - Clear what each entity needs
/// - Easy to read and debug

/// Interface for entities that need async enrichment
abstract class Enrichable {
  /// Entity declares what enrichment steps it needs
  ///
  /// Common steps:
  /// - 'semantic_enrichment' - chunking + embedding + HNSW indexing
  /// - 'categorization' - entity classification with tags
  List<String> get enrichmentSteps;
}
