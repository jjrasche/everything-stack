/// # NoteOB (ObjectBox Wrapper)
///
/// ## What it does
/// ObjectBox-specific wrapper for Note entity.
/// Anti-Corruption Layer: Keeps domain entities clean while preserving
/// ObjectBox's code generation and type safety.
///
/// ## Design
/// - Lives in persistence layer only
/// - Has all ObjectBox annotations (@Entity, @Id, @HnswIndex, etc.)
/// - Domain Note class stays annotation-free (web-safe)
/// - Adapter handles conversion between Note ↔ NoteOB

import 'package:objectbox/objectbox.dart';
import '../../../domain/note.dart';
import '../../../core/base_entity.dart' show SyncStatus;

@Entity()
class NoteOB {
  @Id()
  int id = 0;

  @Unique(onConflict: ConflictStrategy.replace)
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  // Note fields
  String title = '';
  String content = '';
  String dbTags = ''; // Comma-separated
  bool isPinned = false;
  bool isArchived = false;

  // Pattern fields
  @HnswIndex(dimensions: 384)
  @Property(type: PropertyType.floatVector)
  List<double>? embedding;

  int dbSyncStatus = 0; // SyncStatus.index
  int dbVisibility = 0; // Visibility.index
  String? ownerId;
  String dbSharedWith = ''; // Comma-separated
  String dbAttachments = ''; // JSON string
  double? latitude;
  double? longitude;
  String? locationName;

  // ============ Conversion Methods ============

  /// Convert domain Note to ObjectBox wrapper
  static NoteOB fromNote(Note note) {
    return NoteOB()
      ..id = note.id
      ..uuid = note.uuid
      ..createdAt = note.createdAt
      ..updatedAt = note.updatedAt
      ..syncId = note.syncId
      ..title = note.title
      ..content = note.content
      ..dbTags = note.dbTags
      ..isPinned = note.isPinned
      ..isArchived = note.isArchived
      ..embedding = note.embedding
      ..dbSyncStatus = note.dbSyncStatus
      ..dbVisibility = note.dbVisibility
      ..ownerId = note.ownerId
      ..dbSharedWith = note.dbSharedWith
      ..dbAttachments = note.dbAttachments
      ..latitude = note.latitude
      ..longitude = note.longitude
      ..locationName = note.locationName;
  }

  /// Convert ObjectBox wrapper to domain Note
  Note toNote() {
    final note = Note(
      title: title,
      content: content,
      tags: dbTags.isEmpty ? [] : dbTags.split(','),
      isPinned: isPinned,
      isArchived: isArchived,
    );

    // Set inherited fields
    note.id = id;
    note.uuid = uuid;
    note.createdAt = createdAt;
    note.updatedAt = updatedAt;
    note.syncId = syncId;

    // Set pattern fields
    note.embedding = embedding;
    note.dbSyncStatus = dbSyncStatus;
    note.dbVisibility = dbVisibility;
    note.ownerId = ownerId;
    note.dbSharedWith = dbSharedWith;
    note.dbAttachments = dbAttachments;
    note.latitude = latitude;
    note.longitude = longitude;
    note.locationName = locationName;

    return note;
  }
}
