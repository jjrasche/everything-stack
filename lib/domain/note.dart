/// # Note
///
/// ## What it does
/// Core entity for the Notes demo app. Demonstrates pattern composition
/// and serves as the first real entity in the system.
///
/// ## Patterns used
/// - Embeddable: Semantic search across notes
/// - Ownable: Multi-user with sharing
/// - Edgeable: Link notes to each other or other entities
/// - Versionable: Track change history
/// - FileStorable: Attach images, PDFs, etc.
/// - Locatable: Geo-tagged notes
///
/// ## Usage
/// ```dart
/// final note = Note(
///   title: 'Meeting Notes',
///   content: 'Discussed project timeline...',
/// );
/// note.ownerId = currentUser.id;
/// await noteRepo.save(note);
///
/// // Semantic search
/// final results = await noteRepo.semanticSearch('project deadlines');
///
/// // Link to another note
/// await edgeRepo.connect(note, otherNote, edgeType: EdgeTypes.references);
/// ```

import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';
import '../core/base_entity.dart';
import '../patterns/embeddable.dart';
import '../patterns/ownable.dart';
import '../patterns/edgeable.dart';
import '../patterns/versionable.dart';
import '../patterns/file_storable.dart';
import '../patterns/locatable.dart';

// JSON serialization generated code
part 'note.g.dart';

@JsonSerializable()
class Note extends BaseEntity
    with Embeddable, Ownable, Edgeable, Versionable, FileStorable, Locatable {
  // ============ BaseEntity field overrides ============
  /// Database auto-generated ID (inherited from BaseEntity)
  @override
  int id = 0;

  /// Universal unique identifier (inherited from BaseEntity)
  @override
  String uuid = '';

  /// When entity was created (inherited from BaseEntity)
  @override
  DateTime createdAt = DateTime.now();

  /// When entity was last modified (inherited from BaseEntity)
  @override
  DateTime updatedAt = DateTime.now();

  /// For sync identification across devices (inherited from BaseEntity)
  @override
  String? syncId;

  // ============ Note fields ============
  /// Note title
  String title;

  /// Note content (markdown supported)
  String content;

  /// Optional tags for organization
  List<String> tags;

  /// Internal storage for tags as string (for database persistence)
  @JsonKey(includeFromJson: false, includeToJson: false)
  String get dbTags => tags.join(',');
  set dbTags(String value) => tags = value.isEmpty ? [] : value.split(',');

  /// Whether note is pinned to top
  bool isPinned;

  /// Whether note is archived
  bool isArchived;

  // ============ Pattern field overrides ============

  /// Embedding vector for semantic search
  /// 384 dimensions for typical embedding models
  @override
  List<double>? embedding;

  /// Sync status stored as int (enum index)
  @JsonKey(includeFromJson: false, includeToJson: false)
  int get dbSyncStatus => syncStatus.index;
  set dbSyncStatus(int value) => syncStatus = SyncStatus.values[value];

  /// Visibility stored as int (enum index)
  @JsonKey(includeFromJson: false, includeToJson: false)
  int get dbVisibility => visibility.index;
  set dbVisibility(int value) => visibility = Visibility.values[value];

  // ============ Ownable field overrides ============
  /// User ID of owner
  @override
  String? ownerId;

  /// User IDs this is shared with
  @override
  List<String> sharedWith = [];

  /// Internal storage for sharedWith
  @JsonKey(includeFromJson: false, includeToJson: false)
  String get dbSharedWith => sharedWith.join(',');
  set dbSharedWith(String value) =>
      sharedWith = value.isEmpty ? [] : value.split(',');

  // ============ FileStorable field overrides ============
  /// Attachments
  @override
  List<FileMetadata> attachments = [];

  /// Database storage for attachments
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  String get dbAttachments {
    if (attachments.isEmpty) return '';
    return jsonEncode(attachments.map((a) => a.toJson()).toList());
  }

  @override
  set dbAttachments(String value) {
    if (value.isEmpty) {
      attachments = [];
      return;
    }
    final List<dynamic> decoded = jsonDecode(value);
    attachments = decoded
        .map((json) => FileMetadata.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // ============ Locatable field overrides ============
  /// Latitude in decimal degrees
  @override
  double? latitude;

  /// Longitude in decimal degrees
  @override
  double? longitude;

  /// Human-readable location name
  @override
  String? locationName;

  Note({
    required this.title,
    this.content = '',
    this.tags = const [],
    this.isPinned = false,
    this.isArchived = false,
  }) {
    // Ensure uuid is generated if not set
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  // ============ JSON Serialization ============

  Map<String, dynamic> toJson() => _$NoteToJson(this);
  factory Note.fromJson(Map<String, dynamic> json) => _$NoteFromJson(json);

  // ============ Embeddable ============

  /// Define what text represents this note for semantic search.
  /// Include title, content, and tags.
  @override
  String toEmbeddingInput() {
    final parts = <String>[title];
    if (content.isNotEmpty) parts.add(content);
    if (tags.isNotEmpty) parts.add(tags.join(' '));
    return parts.join('\n');
  }

  // ============ Edgeable ============

  @override
  String get edgeableType => 'Note';
}
