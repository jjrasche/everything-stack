/// # NarrativeEntry
///
/// ## What it does
/// Represents a single entry in the system's self-model narrative.
/// Entries are freeform text with optional type tags, organized by scope
/// (session, day, week, project, life).
///
/// ## Patterns used
/// - Embeddable: Semantic search across narrative entries for relevance
///
/// ## Storage
/// Entries are stored per scope in ObjectBox. Each scope maintains its own
/// timeline. Session/Day auto-update. Projects/Life only via training.
///
/// ## Usage
/// ```dart
/// // Create session entry during conversation
/// final entry = NarrativeEntry(
///   content: 'Building conversational AI. Because friction between thought and execution kills what matters.',
///   scope: 'session',
///   type: 'learning',
/// );
/// await narrativeRepo.save(entry);
///
/// // Retrieve relevant entries for Intent Engine context
/// final relevant = await narrativeRepo.findRelevant(utterance, topK: 5);
/// ```

import 'package:json_annotation/json_annotation.dart';
import '../core/base_entity.dart';
import '../patterns/embeddable.dart';

// JSON serialization generated code
part 'narrative_entry.g.dart';

@JsonSerializable()
class NarrativeEntry extends BaseEntity with Embeddable {
  // ============ BaseEntity field overrides ============
  /// Database auto-generated ID (inherited from BaseEntity)
  @override
  int id = 0;

  /// Universal unique identifier (inherited from BaseEntity)
  @override
  String uuid = '';

  /// When entry was created (inherited from BaseEntity)
  @override
  DateTime createdAt = DateTime.now();

  /// When entry was last modified (inherited from BaseEntity)
  @override
  DateTime updatedAt = DateTime.now();

  /// For sync identification across devices (inherited from BaseEntity)
  @override
  String? syncId;

  // ============ NarrativeEntry fields ============

  /// Freeform text content: "[Atomic idea]. Because [reason]."
  /// Example: "Distributed power enables freedom. Because centralized systems
  /// always optimize for the center, not the edges."
  String content;

  /// Scope where this entry lives: 'session', 'day', 'week', 'project', 'life'
  String scope;

  /// Optional type tag: 'learning', 'project', 'exploration'
  String? type;

  /// Optional project UUID (if scope='project' or entry is within a project)
  String? projectId;

  /// Whether this entry is archived (removed from active narratives)
  bool isArchived;

  /// When this entry was archived (null if not archived)
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

  NarrativeEntry({
    required this.content,
    required this.scope,
    this.type,
    this.projectId,
    this.isArchived = false,
  }) {
    // Ensure uuid is generated if not set
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  // ============ JSON Serialization ============

  Map<String, dynamic> toJson() => _$NarrativeEntryToJson(this);
  factory NarrativeEntry.fromJson(Map<String, dynamic> json) =>
      _$NarrativeEntryFromJson(json);

  // ============ Embeddable ============

  /// Return the content itself for embedding.
  /// Narrative entries are already concise, so no need to extract/summarize.
  @override
  String toEmbeddingInput() => content;
}
