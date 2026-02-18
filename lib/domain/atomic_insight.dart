/// Single insight extracted from conversations in "[Fact]. Because [reason]." format.
/// Scoped temporally (session, day, week, project, life) with Embeddable for semantic search.

import 'package:json_annotation/json_annotation.dart';
import '../core/base_entity.dart';
import '../patterns/embeddable.dart';

// JSON serialization generated code
part 'atomic_insight.g.dart';

@JsonSerializable()
class AtomicInsight extends BaseEntity with Embeddable {
  // ============ BaseEntity field overrides ============
  /// Database auto-generated ID (inherited from BaseEntity)
  @override
  int id = 0;

  /// Universal unique identifier (inherited from BaseEntity)
  @override
  String uuid = '';

  /// When insight was created (inherited from BaseEntity)
  @override
  DateTime createdAt = DateTime.now();

  /// When insight was last modified (inherited from BaseEntity)
  @override
  DateTime updatedAt = DateTime.now();

  /// For sync identification across devices (inherited from BaseEntity)
  @override
  String? syncId;

  // ============ AtomicInsight fields ============

  /// Freeform text content: "[Atomic idea]. Because [reason]."
  /// Example: "Distributed power enables freedom. Because centralized systems
  /// always optimize for the center, not the edges."
  String content;

  /// Scope where this insight lives: 'session', 'day', 'week', 'project', 'life'
  String scope;

  /// Optional type tag: 'learning', 'project', 'exploration'
  String? type;

  /// Quoted substring from the episodic source that supports this insight.
  /// Stage 1 produces this alongside the insight content for 1:1 evidence alignment.
  String? evidenceSpan;

  /// Optional project UUID (if scope='project' or insight is within a project)
  String? projectId;

  /// Whether this insight is archived (removed from active context)
  bool isArchived;

  /// When this insight was archived (null if not archived)
  DateTime? archivedAt;

  // ============ Pattern field overrides ============

  /// Embedding vector for semantic search
  /// Stored as Float64List in ObjectBox
  @override
  List<double>? embedding;

  /// Sync status stored as int (enum index)
  @JsonKey(includeFromJson: false, includeToJson: false)
  int get dbSyncStatus => syncStatus.index;
  set dbSyncStatus(int value) => syncStatus = SyncStatus.values[value];

  AtomicInsight({
    required this.content,
    required this.scope,
    this.type,
    this.evidenceSpan,
    this.projectId,
    this.isArchived = false,
  }) {
    // Ensure uuid is generated if not set
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  // ============ JSON Serialization ============

  Map<String, dynamic> toJson() => _$AtomicInsightToJson(this);
  factory AtomicInsight.fromJson(Map<String, dynamic> json) =>
      _$AtomicInsightFromJson(json);

  // ============ Embeddable ============

  /// Return the content itself for embedding.
  /// Atomic insights are already concise, so no need to extract/summarize.
  @override
  String toEmbeddingInput() => content;
}
