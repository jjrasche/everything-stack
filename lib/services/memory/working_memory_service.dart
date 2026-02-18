import '../../domain/proposition.dart';
import 'working_memory_diff.dart';

/// Bounded in-memory set of active propositions.
/// The encoder reads from and writes to this via diffs.
class WorkingMemoryService {
  final int maxCapacity;
  final List<Proposition> _propositions = [];

  WorkingMemoryService({this.maxCapacity = 100});

  /// Current active propositions (oldest first).
  List<Proposition> get state => List.unmodifiable(_propositions);

  /// Extract unique entity-like terms from current propositions.
  /// Used by decontextualize stage for coreference resolution.
  List<String> get entityList {
    final entities = <String>{};
    for (final prop in _propositions) {
      entities.addAll(_extractEntityCandidates(prop.content));
    }
    return entities.toList()..sort();
  }

  /// Apply a diff produced by the encoder.
  void applyDiff(WorkingMemoryDiff diff) {
    _removeArchived(diff.archived);
    _removeSuperseded(diff.superseded);
    _removeRewritten(diff.rewritten);
    _addPropositions(diff.added);
    _evictOldest();
  }

  /// Format all propositions as numbered list for LLM prompts.
  String propositionsAsContext() {
    if (_propositions.isEmpty) return '';
    final buffer = StringBuffer();
    for (var i = 0; i < _propositions.length; i++) {
      buffer.writeln('${i + 1}. ${_propositions[i].content}');
    }
    return buffer.toString().trimRight();
  }

  /// Current proposition UUIDs (for trace logging).
  List<String> propositionUuids() =>
      _propositions.map((p) => p.uuid).toList();

  // ============ Diff Application ============

  void _removeArchived(List<String> uuids) {
    _propositions.removeWhere((p) => uuids.contains(p.uuid));
  }

  void _removeSuperseded(List<SupersessionRecord> records) {
    final supersededUuids = records.map((r) => r.oldUuid).toSet();
    _propositions.removeWhere((p) => supersededUuids.contains(p.uuid));
  }

  void _removeRewritten(List<RewriteRecord> records) {
    final rewrittenUuids = records.map((r) => r.oldUuid).toSet();
    _propositions.removeWhere((p) => rewrittenUuids.contains(p.uuid));
  }

  void _addPropositions(List<Proposition> added) {
    _propositions.addAll(added);
  }

  void _evictOldest() {
    while (_propositions.length > maxCapacity) {
      _propositions.removeAt(0);
    }
  }

  // ============ Entity Extraction ============

  /// Naive capitalized-word extraction for entity candidates.
  /// Sufficient for Phase 1; GLiNER replaces this in Phase 3.
  List<String> _extractEntityCandidates(String text) {
    final words = text.split(RegExp(r'\s+'));
    final candidates = <String>[];
    for (final word in words) {
      final cleaned = word.replaceAll(RegExp(r'[.,;:!?()"]'), '');
      if (cleaned.length > 1 && cleaned[0] == cleaned[0].toUpperCase() &&
          cleaned[0] != cleaned[0].toLowerCase()) {
        candidates.add(cleaned);
      }
    }
    return candidates;
  }
}
