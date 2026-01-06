import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/services/semantic_search/chunk.dart';

/// ObjectBox entity for persisting chunks to database.
///
/// Enables:
/// - Rebuilding HNSW index if lost or corrupted
/// - Querying chunks by entity for debugging
/// - Cross-session chunk history
///
/// See Chunk model for the domain representation.
@Entity()
class ChunkEntity {
  @Id()
  int id = 0;

  /// UUID for HNSW index lookup.
  /// Maps directly to HNSW chunk ID.
  @Index()
  late String chunkId;

  /// UUID of source entity (Invocation, Note, etc).
  /// Links back to the entity that generated this chunk.
  @Index()
  late String sourceEntityId;

  /// Type name of source entity (for entity loader routing).
  late String sourceEntityType;

  /// Starting token position in original entity text.
  late int startToken;

  /// Ending token position in original entity text.
  late int endToken;

  /// Chunk level: 'parent' (~250 tokens) or 'child' (~20 tokens).
  late String config;

  /// Full chunk text (needed for reconstruction after HNSW search).
  late String text;

  /// Creation timestamp.
  late DateTime createdAt;

  ChunkEntity({
    required this.chunkId,
    required this.sourceEntityId,
    required this.sourceEntityType,
    required this.startToken,
    required this.endToken,
    required this.config,
    required this.text,
  }) {
    createdAt = DateTime.now();
  }

  /// Convert to domain Chunk model.
  Chunk toDomain() {
    return Chunk(
      id: chunkId,
      sourceEntityId: sourceEntityId,
      sourceEntityType: sourceEntityType,
      startToken: startToken,
      endToken: endToken,
      config: config,
      text: text,
    );
  }

  /// Validate chunk data before storage.
  void validate() {
    if (chunkId.isEmpty) throw ArgumentError('chunkId cannot be empty');
    if (sourceEntityId.isEmpty) throw ArgumentError('sourceEntityId cannot be empty');
    if (sourceEntityType.isEmpty) throw ArgumentError('sourceEntityType cannot be empty');
    if (endToken <= startToken) throw ArgumentError('endToken must be > startToken');
    if (config != 'parent' && config != 'child') {
      throw ArgumentError('config must be "parent" or "child"');
    }
    if (text.isEmpty) throw ArgumentError('text cannot be empty');
  }

  @override
  String toString() =>
      'ChunkEntity($chunkId, $sourceEntityType, tokens: ${endToken - startToken}, config: $config)';
}
