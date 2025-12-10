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

import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';
import '../core/base_entity.dart';
import '../patterns/embeddable.dart';
import '../patterns/ownable.dart';
import '../patterns/edgeable.dart';
import '../patterns/versionable.dart';
import '../patterns/file_storable.dart';
import '../patterns/locatable.dart';

part 'note.g.dart';

@Collection()
@JsonSerializable()
class Note extends BaseEntity
    with Embeddable, Ownable, Edgeable, Versionable, FileStorable, Locatable {
  // ============ Isar field overrides ============
  // Override uuid with @Index for O(1) findByUuid() lookups
  // (Isar doesn't inherit indexed fields from base classes)
  @Index(unique: true)
  @override
  String uuid = '';

  // Override syncStatus with @enumerated annotation
  @override
  @enumerated
  SyncStatus syncStatus = SyncStatus.local;

  // Override visibility with @enumerated annotation
  @override
  @enumerated
  Visibility visibility = Visibility.private;

  // ============ Note fields ============
  /// Note title
  String title;

  /// Note content (markdown supported)
  String content;

  /// Optional tags for organization
  List<String> tags;

  /// Whether note is pinned to top
  bool isPinned;

  /// Whether note is archived
  bool isArchived;

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
