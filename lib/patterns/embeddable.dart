/// # Embeddable
///
/// ## What it does
/// Adds vector embedding field to entity, enabling semantic search.
/// Entity content is converted to embedding via `toEmbeddingInput()`.
///
/// ## What it enables
/// - Find entities by meaning, not just keywords
/// - Search across entity types with unified interface
/// - "Find things like this" functionality
/// - Break data silos - search everything, find anything
///
/// ## Schema addition
/// ```dart
/// List<double>? embedding; // 384 floats for Gemini text-embedding-004
/// ```
///
/// ## Usage
/// ```dart
/// class Note extends BaseEntity with Embeddable {
///   String title;
///   String content;
///
///   @override
///   String toEmbeddingInput() => '$title\n$content';
/// }
///
/// // Generate embedding before save
/// await note.generateEmbedding();
/// await noteRepo.save(note);
///
/// // Search semantically
/// final results = await noteRepo.semanticSearch('weekend plans');
/// ```
///
/// ## Performance
/// - Embedding generation: ~50ms per entity (model dependent)
/// - HNSW index adds ~10% to write time
/// - Search is O(log n) with HNSW
/// - Storage: 384 floats × 4 bytes = 1.5KB per entity
///
/// ## Testing approach
/// Semantic similarity tests. Create entities with known content:
/// - Similar concepts should cluster (score > 0.7)
/// - Dissimilar concepts should separate (score < 0.3)
///
/// Options for verification:
/// 1. Golden set: Human-curated pairs with expected similarity ranges
/// 2. LLM-as-judge: Ask LLM if returned results are relevant to query
///
/// ## Integrates with
/// - Edgeable: Find related by similarity + explicit connection
/// - Locatable: Find similar things nearby
/// - EntityRepository.semanticSearch(): Built-in search method

import '../services/embedding_service.dart';

mixin Embeddable {
  /// Vector embedding for semantic search
  /// 384 dimensions for Gemini text-embedding-004
  List<double>? embedding;

  /// Override to define what text represents this entity semantically.
  /// This is what gets embedded.
  ///
  /// Consider: What words would someone use to find this?
  ///
  /// Examples:
  /// - Note: title + content
  /// - Tool: name + description + category
  /// - Person: name + bio + skills
  String toEmbeddingInput();

  /// Generate embedding from entity content.
  /// Call before save when content changes.
  Future<void> generateEmbedding() async {
    final text = toEmbeddingInput();
    if (text.isEmpty) {
      embedding = null;
      return;
    }
    embedding = await EmbeddingService.instance.generate(text);
  }

  /// Check if embedding needs regeneration.
  /// Override if you track content changes.
  bool get needsReembedding => embedding == null;
}
