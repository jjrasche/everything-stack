import '../../domain/proposition.dart';

/// Output of one encoder run against working memory.
class WorkingMemoryDiff {
  /// New propositions to add
  final List<Proposition> added;

  /// UUIDs of propositions to archive (context pressure)
  final List<String> archived;

  /// Supersession pairs: old proposition replaced by new
  final List<SupersessionRecord> superseded;

  /// Rewrite pairs: dedup merged two propositions into canonical form
  final List<RewriteRecord> rewritten;

  WorkingMemoryDiff({
    this.added = const [],
    this.archived = const [],
    this.superseded = const [],
    this.rewritten = const [],
  });

  bool get isEmpty =>
      added.isEmpty &&
      archived.isEmpty &&
      superseded.isEmpty &&
      rewritten.isEmpty;

  Map<String, dynamic> toJson() => {
        'added': added.map((p) => {'propositionId': p.uuid}).toList(),
        'archived': archived,
        'superseded': superseded.map((s) => s.toJson()).toList(),
        'rewritten': rewritten.map((r) => r.toJson()).toList(),
      };
}

class SupersessionRecord {
  final String oldUuid;
  final String replacedByUuid;
  final String reason;

  SupersessionRecord({
    required this.oldUuid,
    required this.replacedByUuid,
    this.reason = 'contradiction',
  });

  Map<String, dynamic> toJson() => {
        'old': oldUuid,
        'replacedBy': replacedByUuid,
        'reason': reason,
      };
}

class RewriteRecord {
  final String oldUuid;
  final String mergedIntoUuid;

  RewriteRecord({
    required this.oldUuid,
    required this.mergedIntoUuid,
  });

  Map<String, dynamic> toJson() => {
        'old': oldUuid,
        'mergedInto': mergedIntoUuid,
      };
}
