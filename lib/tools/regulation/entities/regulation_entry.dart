
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

  /// Entry type
  EntryType entryType;

  /// Person UUIDs
  List<String> personIds;

  /// Raw transcript from STT
  String rawTranscript;

  /// What strategy was used? (e.g., "walked away", "deep breathing")
  String? regulationStrategy;

  /// Severity
  Severity severity;

  /// Category (e.g., "incredulous", "dismissive", "flooded")
  String? category;

  /// Optional notes
  String? notes;

  // ============ Constructor ============

  RegulationEntry({
    required this.entryType,
    List<String>? personIds,
    required this.rawTranscript,
    this.regulationStrategy,
    required this.severity,
    this.category,
    this.notes,
  }) : personIds = personIds ?? [] {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
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
