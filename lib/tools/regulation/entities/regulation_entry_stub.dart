/// # RegulationEntry (Web Version)
///
/// ## What it does
/// Records a single regulation event (dysregulation catch, intervention, rupture, etc.).
/// This is the web version without ObjectBox decorators.
///
/// ## Platform
/// This file is imported on web platforms only (uses IndexedDB instead of ObjectBox).

import '../../../core/base_entity.dart';

/// Type of regulation event
enum EntryType {
  dysregulationCatch,
  interventionCatch,
  madeWorse,
  household,
  rupture,
}

/// Severity level
enum Severity {
  minor,
  medium,
  major,
}

class RegulationEntry extends BaseEntity {
  // ============ BaseEntity field overrides ============
  @override
  int id = 0;

  @override
  String uuid = '';

  @override
  DateTime createdAt = DateTime.now();

  @override
  DateTime updatedAt = DateTime.now();

  @override
  String? syncId;

  // ============ RegulationEntry fields ============

  /// Entry type (stored as int, accessed via enum)
  int dbEntryType;

  /// Entry type getter/setter
  EntryType get entryType => EntryType.values[dbEntryType];
  set entryType(EntryType value) => dbEntryType = value.index;

  /// Person UUIDs (many-to-many, stored as comma-separated string)
  String dbPersonIds = '';

  /// Person IDs getter/setter
  List<String> get personIds {
    if (dbPersonIds.isEmpty) return [];
    return dbPersonIds.split(',');
  }

  set personIds(List<String> value) {
    dbPersonIds = value.join(',');
  }

  /// Raw transcript from STT
  String rawTranscript;

  /// What strategy was used? (e.g., "walked away", "deep breathing")
  String? regulationStrategy;

  /// Severity (stored as int, accessed via enum)
  int dbSeverity;

  /// Severity getter/setter
  Severity get severity => Severity.values[dbSeverity];
  set severity(Severity value) => dbSeverity = value.index;

  /// Category (e.g., "incredulous", "dismissive", "flooded")
  String? category;

  /// Optional notes
  String? notes;

  // ============ Constructor ============

  RegulationEntry({
    EntryType? entryType,
    List<String>? personIds,
    required this.rawTranscript,
    this.regulationStrategy,
    Severity? severity,
    this.category,
    this.notes,
  })  : dbEntryType = entryType?.index ?? 0,
        dbSeverity = severity?.index ?? 0 {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
    this.personIds = personIds ?? []; // Use setter
  }

  // ============ JSON serialization ============

  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncId': syncId,
        'entryType': entryType.name,
        'personIds': personIds,
        'rawTranscript': rawTranscript,
        'regulationStrategy': regulationStrategy,
        'severity': severity.name,
        'category': category,
        'notes': notes,
      };

  factory RegulationEntry.fromJson(Map<String, dynamic> json) {
    final entry = RegulationEntry(
      entryType: EntryType.values.firstWhere(
        (e) => e.name == json['entryType'],
      ),
      personIds: (json['personIds'] as List).map((e) => e as String).toList(),
      rawTranscript: json['rawTranscript'] as String,
      regulationStrategy: json['regulationStrategy'] as String?,
      severity: Severity.values.firstWhere(
        (e) => e.name == json['severity'],
      ),
      category: json['category'] as String?,
      notes: json['notes'] as String?,
    );
    entry.id = json['id'] as int? ?? 0;
    entry.uuid = json['uuid'] as String? ?? '';
    entry.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    entry.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    entry.syncId = json['syncId'] as String?;
    return entry;
  }
}
