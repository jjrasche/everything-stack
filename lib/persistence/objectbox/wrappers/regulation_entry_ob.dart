/// # RegulationEntryOB - ObjectBox Wrapper
///
/// ObjectBox-decorated version of RegulationEntry domain entity.
/// Contains all ObjectBox decorators (@Entity, @Id, @Property, etc.)
///
/// This wrapper allows RegulationEntry domain entities to remain pure Dart,
/// while providing ObjectBox persistence for native platforms.
///
/// Uses @Transient for enum properties with int storage.

import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/tools/regulation/entities/regulation_entry.dart';

@Entity()
class RegulationEntryOB {
  @Id()
  int id = 0;

  @Unique()
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  // ============ RegulationEntry-specific fields ============

  /// Entry type (stored as int, accessed via enum)
  @Property(type: PropertyType.byte)
  int dbEntryType;

  /// Entry type getter/setter
  @Transient()
  EntryType get entryType => EntryType.values[dbEntryType];
  set entryType(EntryType value) => dbEntryType = value.index;

  /// Person UUIDs (many-to-many, stored as comma-separated string)
  String dbPersonIds = '';

  /// Person IDs getter/setter
  @Transient()
  List<String> get personIds {
    if (dbPersonIds.isEmpty) return [];
    return dbPersonIds.split(',');
  }

  set personIds(List<String> value) {
    dbPersonIds = value.join(',');
  }

  String rawTranscript;
  String? regulationStrategy;

  /// Severity (stored as int, accessed via enum)
  @Property(type: PropertyType.byte)
  int dbSeverity;

  /// Severity getter/setter
  @Transient()
  Severity get severity => Severity.values[dbSeverity];
  set severity(Severity value) => dbSeverity = value.index;

  String? category;
  String? notes;

  // ============ Constructor ============

  RegulationEntryOB({
    required this.rawTranscript,
    this.regulationStrategy,
    this.category,
    this.notes,
  })  : dbEntryType = 0,
        dbSeverity = 0;

  // ============ Conversion to/from domain entity ============

  /// Convert from domain entity to ObjectBox wrapper
  factory RegulationEntryOB.fromRegulationEntry(RegulationEntry entry) {
    return RegulationEntryOB(
      rawTranscript: entry.rawTranscript,
      regulationStrategy: entry.regulationStrategy,
      category: entry.category,
      notes: entry.notes,
    )
      ..id = entry.id
      ..uuid = entry.uuid
      ..createdAt = entry.createdAt
      ..updatedAt = entry.updatedAt
      ..syncId = entry.syncId
      ..entryType = entry.entryType
      ..personIds = entry.personIds
      ..severity = entry.severity;
  }

  /// Convert from ObjectBox wrapper to domain entity
  RegulationEntry toRegulationEntry() {
    final entry = RegulationEntry(
      entryType: entryType,
      personIds: personIds,
      rawTranscript: rawTranscript,
      regulationStrategy: regulationStrategy,
      severity: severity,
      category: category,
      notes: notes,
    );
    entry.id = id;
    entry.uuid = uuid;
    entry.createdAt = createdAt;
    entry.updatedAt = updatedAt;
    entry.syncId = syncId;
    return entry;
  }
}
