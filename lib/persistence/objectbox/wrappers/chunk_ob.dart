import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/services/semantic_search/chunk.dart';

@Entity()
class ChunkOB {
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

  /// Embedding vector (384 dimensions for Jina).
  /// Stored as Float32List for efficient storage.
  /// Nullable for backwards compatibility with existing data.
  @Property(type: PropertyType.floatVector)
  List<double>? embedding;

  /// Creation timestamp.
  @Property(type: PropertyType.date)
  late DateTime createdAt;

  ChunkOB();

  // ============ Conversion Methods ============

  /// Convert from domain Chunk to ObjectBox wrapper
  factory ChunkOB.fromChunk(Chunk chunk) {
    return ChunkOB()
      ..chunkId = chunk.id
      ..sourceEntityId = chunk.sourceEntityId
      ..sourceEntityType = chunk.sourceEntityType
      ..startToken = chunk.startToken
      ..endToken = chunk.endToken
      ..config = chunk.config
      ..text = chunk.text
      ..embedding = chunk.embedding
      ..createdAt = DateTime.now();
  }

  /// Convert from ObjectBox wrapper back to domain Chunk
  Chunk toChunk() {
    return Chunk(
      id: chunkId,
      sourceEntityId: sourceEntityId,
      sourceEntityType: sourceEntityType,
      startToken: startToken,
      endToken: endToken,
      config: config,
      text: text,
      embedding: embedding,
    );
  }

  /// Validate chunk data before storage.
  void validate() {
    if (chunkId.isEmpty) throw ArgumentError('chunkId cannot be empty');
    if (sourceEntityId.isEmpty) {
      throw ArgumentError('sourceEntityId cannot be empty');
    }
    if (sourceEntityType.isEmpty) {
      throw ArgumentError('sourceEntityType cannot be empty');
    }
    if (endToken <= startToken) {
      throw ArgumentError('endToken must be > startToken');
    }
    if (config != 'parent' && config != 'child' && config != 'invocation') {
      throw ArgumentError('config must be "parent", "child", or "invocation"');
    }
    if (text.isEmpty) throw ArgumentError('text cannot be empty');
  }

  @override
  String toString() =>
      'ChunkOB($chunkId, $sourceEntityType, tokens: ${endToken - startToken}, config: $config)';
}
