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
