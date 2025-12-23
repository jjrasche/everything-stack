/// # NarrativeRetriever
///
/// ## What it does
/// Semantic search across narrative entries. Finds relevant narratives
/// for Intent Engine context injection at classification time.
///
/// ## Retrieval Strategy
/// - Top-K with adaptive threshold (default: top 5, threshold 0.65)
/// - Returns fewer if none meet threshold (better than weak matches)
/// - Filtered by active scopes (Session always, Day/Week/Project/Life by relevance)
///
/// ## Usage
/// ```dart
/// final retriever = NarrativeRetriever(narrativeRepo: narrativeRepo);
///
/// // At turn boundary, retrieve context for Intent Engine
/// final relevant = await retriever.findRelevant(utterance);
/// // Returns top 5 most relevant narrative entries
/// ```

import '../domain/narrative_entry.dart';
import '../domain/narrative_repository.dart';
import 'embedding_service.dart';

class NarrativeRetriever {
  final NarrativeRepository _narrativeRepo;

  NarrativeRetriever({
    required NarrativeRepository narrativeRepo,
    EmbeddingService? embeddingService,
  })  : _narrativeRepo = narrativeRepo;

  /// Find narratives most relevant to current utterance/context.
  ///
  /// Parameters:
  /// - query: Current utterance or conversation snippet
  /// - topK: Maximum results (default 5)
  /// - threshold: Minimum cosine similarity 0-1 (default 0.65)
  /// - includeScopes: Scopes to search (default: all active)
  ///
  /// Returns: List of relevant entries sorted by similarity (highest first)
  Future<List<NarrativeEntry>> findRelevant(
    String query, {
    int topK = 5,
    double threshold = 0.65,
    List<String>? includeScopes,
  }) async {
    try {
      // Query narrative repository with semantic search
      final results = await _narrativeRepo.findRelevant(
        query,
        topK: topK,
        threshold: threshold,
        scopes: includeScopes,
        excludeArchived: true,
      );

      if (results.isEmpty) {
        return [];
      }

      return results;
    } catch (e) {
      return [];
    }
  }

  /// Find narratives for a specific scope (e.g., all Session narratives).
  /// Useful for training checkpoint to show current state.
  Future<List<NarrativeEntry>> findByScope(
    String scope, {
    bool includeArchived = false,
  }) async {
    try {
      return await _narrativeRepo.findByScope(
        scope,
        includeArchived: includeArchived,
      );
    } catch (e) {
      return [];
    }
  }

  /// Find narratives by type within optional scope.
  /// Used to analyze learning vs exploration vs project themes.
  Future<List<NarrativeEntry>> findByType(
    String type, {
    String? scope,
  }) async {
    try {
      return await _narrativeRepo.findByType(type, scope: scope);
    } catch (e) {
      return [];
    }
  }

  /// Format narrative entries for LLM context injection.
  /// Used when passing narratives to Intent Engine prompt.
  String formatForContext(List<NarrativeEntry> entries) {
    if (entries.isEmpty) {
      return '(No relevant narratives)';
    }

    final buffer = StringBuffer();
    buffer.writeln('## Relevant Narratives');
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final scope = entry.scope;
      final type = entry.type != null ? ' [${entry.type}]' : '';
      buffer.writeln('${i + 1}. [${scope.toUpperCase()}]$type ${entry.content}');
    }
    return buffer.toString();
  }

  /// Get narrative summary for a scope.
  /// Returns concise overview of what system currently understands about user.
  Future<String> getScopeSummary(String scope) async {
    try {
      final entries = await findByScope(scope);
      if (entries.isEmpty) {
        return 'No entries in $scope scope yet.';
      }

      final buffer = StringBuffer();
      buffer.writeln('$scope Narrative (${entries.length} entries):');
      for (final entry in entries.take(10)) {
        buffer.writeln('  • ${entry.content}');
      }
      if (entries.length > 10) {
        buffer.writeln('  ... and ${entries.length - 10} more');
      }
      return buffer.toString();
    } catch (e) {
      return 'Error retrieving summary';
    }
  }
}
