/// # Edgeable
///
/// ## What it does
/// Enables flexible entity-to-entity connections without schema changes.
/// Creates a shallow graph layer over relational data.
///
/// ## What it enables
/// - Connect any entity to any entity
/// - Discover relationships without foreign keys
/// - "Related items" functionality
/// - Flexible categorization and grouping
/// - Human-curated and AI-inferred connections
///
/// ## Schema
/// Edges stored in separate Edge entities:
/// ```dart
/// Edge {
///   sourceType, sourceUuid,
///   targetType, targetUuid,
///   edgeType,
///   metadata
/// }
/// ```
///
/// ## Usage
/// ```dart
/// // Connect a note to a project
/// await edgeRepo.connect(
///   source: note,
///   target: project,
///   edgeType: 'belongs_to',
/// );
///
/// // Find all notes connected to project
/// final notes = await edgeRepo.findConnected<Note>(
///   target: project,
///   edgeType: 'belongs_to',
/// );
///
/// // Multi-hop: find notes connected to projects connected to user
/// final userNotes = await edgeRepo.traverse(
///   start: user,
///   path: ['owns', 'belongs_to'],
///   targetType: 'Note',
/// );
/// ```
///
/// ## Performance
/// - Index on (sourceType, sourceUuid) and (targetType, targetUuid)
/// - Unique constraint on full edge prevents duplicates
/// - 1-3 hop traversal via SQL/Dart is fine
/// - Deep traversal (4+ hops) may need graph DB
///
/// ## Testing approach
/// Traversal tests:
/// - Create entity graph with known structure
/// - Verify single-hop queries return correct entities
/// - Verify multi-hop traversal follows correct path
/// - Test edge creation idempotency (no duplicates)
/// - Test edge deletion cascades correctly
///
/// ## Integrates with
/// - Embeddable: Find related by explicit connection + similarity
/// - Ownable: Only traverse edges user has access to
///
/// ## Not for
/// - Deep graph algorithms (PageRank, community detection)
/// - High-frequency writes to edges
/// - If you need these, consider a graph database

import '../core/base_entity.dart';

/// Marker mixin for entities that can have edges
mixin Edgeable on BaseEntity {
  /// Get entity type name for edge storage
  String get edgeableType => runtimeType.toString();
}

/// Represents a connection between two entities
class Edge {
  int? id;

  /// Source entity type name
  String sourceType;

  /// Source entity UUID (universal identifier)
  String sourceUuid;

  /// Target entity type name
  String targetType;

  /// Target entity UUID (universal identifier)
  String targetUuid;

  /// Type of relationship (e.g., 'belongs_to', 'references', 'similar_to')
  String edgeType;

  /// Optional metadata about the edge
  Map<String, dynamic>? metadata;

  /// When edge was created
  DateTime createdAt = DateTime.now();

  /// Who created this edge (user ID or 'system' for AI-generated)
  String? createdBy;

  Edge({
    required this.sourceType,
    required this.sourceUuid,
    required this.targetType,
    required this.targetUuid,
    required this.edgeType,
    this.metadata,
    this.createdBy,
  });

  /// Create edge from two entities
  static Edge between<S extends Edgeable, T extends Edgeable>(
    S source,
    T target, {
    required String edgeType,
    Map<String, dynamic>? metadata,
    String? createdBy,
  }) {
    return Edge(
      sourceType: source.edgeableType,
      sourceUuid: source.uuid,
      targetType: target.edgeableType,
      targetUuid: target.uuid,
      edgeType: edgeType,
      metadata: metadata,
      createdBy: createdBy,
    );
  }
}

/// Edge types for common relationships
class EdgeTypes {
  static const belongsTo = 'belongs_to';
  static const references = 'references';
  static const similarTo = 'similar_to'; // AI-inferred
  static const relatedTo = 'related_to'; // Human-curated
  static const parentOf = 'parent_of';
  static const childOf = 'child_of';
}
