/// # Context Panel
///
/// Displays the context bundle selected by ContextSelector.
/// Shows conversation thread + semantic matches with scores.
/// Long-press to provide feedback on context selection quality.
/// Includes real-time similarity threshold slider for testing.
/// Includes search box for querying semantic index directly.

import 'dart:math' show exp, ln2;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/services/types/context_selector_types.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/services/semantic_search/search_result.dart';
import 'package:everything_stack_template/services/semantic_search/semantic_search_service.dart';
import 'feedback_bottom_sheet.dart';
import 'package:timeago/timeago.dart' as timeago;

class ContextPanel extends StatefulWidget {
  final ContextBundle? contextBundle;
  final bool feedbackGiven;
  final Function(bool isPositive)? onFeedback;

  const ContextPanel({
    Key? key,
    this.contextBundle,
    required this.feedbackGiven,
    this.onFeedback,
  }) : super(key: key);

  @override
  State<ContextPanel> createState() => _ContextPanelState();
}

class _ContextPanelState extends State<ContextPanel> {
  double _similarityThreshold = 0.0; // Start at 0.0 to show all

  // Search state
  final TextEditingController _searchController = TextEditingController();
  List<SemanticSearchResult> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;
  bool _showSearchResults = false;

  SemanticSearchService? get _searchService {
    try {
      return GetIt.instance<SemanticSearchService>();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    print('🔎 [ContextPanel] Search triggered with query: "$query"');

    if (query.trim().isEmpty) {
      print('🔎 [ContextPanel] Empty query, clearing results');
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
        _searchError = null;
      });
      return;
    }

    final searchService = _searchService;
    if (searchService == null) {
      print('❌ [ContextPanel] Search service not available from GetIt');
      setState(() {
        _searchError = 'Search service not available';
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      print('🔎 [ContextPanel] Calling searchService.search("${query.trim()}")...');
      final results = await searchService.search(
        query.trim(),
        limit: 10,
      );
      print('✅ [ContextPanel] Search returned ${results.length} results');
      for (int i = 0; i < results.length; i++) {
        final r = results[i];
        print('   [$i] similarity=${r.similarity.toStringAsFixed(3)} entity=${r.sourceEntity?.runtimeType}');
      }
      setState(() {
        _searchResults = results;
        _showSearchResults = true;
        _isSearching = false;
      });
    } catch (e, stack) {
      print('❌ [ContextPanel] Search error: $e');
      print('   Stack: $stack');
      setState(() {
        _searchError = e.toString();
        _isSearching = false;
        _showSearchResults = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate total context count and filter semantic matches
    final conversationCount =
        widget.contextBundle?.conversationThread.length ?? 0;
    final allSemanticMatches = widget.contextBundle?.semanticContext ?? [];

    // Filter semantic matches by similarity threshold (now using actual similarity scores)
    final filteredSemanticMatches = allSemanticMatches.where((result) {
      return result.similarity >= _similarityThreshold;
    }).toList();

    final totalCount = conversationCount + filteredSemanticMatches.length;

    return Semantics(
      explicitChildNodes: true,
      child: GestureDetector(
        onLongPress: () => _handleLongPress(context),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              // Header with Search
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: Column(
                  children: [
                    // Search Box
                    Semantics(
                      label: 'context_panel.search_bar',
                      textField: true,
                      container: true,
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search semantic index...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? Semantics(
                                  label: 'context_panel.search_clear',
                                  button: true,
                                  container: true,
                                  child: IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      _performSearch('');
                                    },
                                  ),
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        style: const TextStyle(fontSize: 14),
                        onSubmitted: _performSearch,
                        onChanged: (value) {
                          // Rebuild to show/hide clear button
                          setState(() {});
                        },
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Title Row
                    Row(
                      children: [
                        Icon(
                          _showSearchResults ? Icons.search : Icons.psychology,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _showSearchResults
                              ? 'Search Results (${_searchResults.length})'
                              : 'Context Selection ($totalCount)',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        if (_showSearchResults)
                          TextButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchResults = [];
                                _showSearchResults = false;
                                _searchError = null;
                              });
                            },
                            child: const Text('Back to Context'),
                          )
                        else if (widget.feedbackGiven)
                          Icon(Icons.check_circle,
                              color: Colors.green.shade700, size: 20)
                        else
                          const Text(
                            'Long-press to rate',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                      ],
                    ),

                    // Similarity threshold slider (only in context mode)
                    if (!_showSearchResults &&
                        widget.contextBundle != null &&
                        allSemanticMatches.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text(
                            'Similarity Filter:',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Expanded(
                            child: Semantics(
                              label: 'context_panel.similarity_slider',
                              slider: true,
                              container: true,
                              child: Slider(
                                value: _similarityThreshold,
                                min: 0.0,
                                max: 1.0,
                                divisions: 20,
                                label: _similarityThreshold.toStringAsFixed(2),
                                onChanged: (value) {
                                  setState(() {
                                    _similarityThreshold = value;
                                  });
                                },
                              ),
                            ),
                          ),
                          Text(
                            _similarityThreshold.toStringAsFixed(2),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Content
              Expanded(
                child: _buildContent(
                  context,
                  filteredSemanticMatches,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<SemanticSearchResult> filteredSemanticMatches,
  ) {
    // Show loading indicator
    if (_isSearching) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Searching...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    // Show search error
    if (_searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade400, size: 48),
              const SizedBox(height: 16),
              Text(
                'Search Error',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _searchError!,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Show search results
    if (_showSearchResults) {
      if (_searchResults.isEmpty) {
        return const Center(
          child: Text(
            'No results found',
            style: TextStyle(color: Colors.grey),
          ),
        );
      }

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSemanticSection(
            context,
            title: 'Search Results',
            items: _searchResults,
            semanticHalfLifeHours: 720.0, // Default decay for display
          ),
        ],
      );
    }

    // Show normal context (no search active)
    if (widget.contextBundle == null) {
      return const Center(
        child: Text(
          'No context selected yet\n\nUse search above to explore the semantic index',
          style: TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Recent Conversation
        _buildSection(
          context,
          title: 'Recent Conversation',
          items: widget.contextBundle!.conversationThread,
          showDecay: true,
        ),

        const SizedBox(height: 24),

        // Semantic Matches (filtered by threshold)
        _buildSemanticSection(
          context,
          title: 'Semantic Matches',
          items: filteredSemanticMatches,
          semanticHalfLifeHours: widget.contextBundle!.params.semanticHalfLifeHours,
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Invocation> items,
    required bool showDecay,
  }) {
    if (items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'None',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title (${items.length})',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((inv) => _buildContextItem(context, inv, showDecay)),
      ],
    );
  }

  Widget _buildSemanticSection(
    BuildContext context, {
    required String title,
    required List<SemanticSearchResult> items,
    required double semanticHalfLifeHours,
  }) {
    if (items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'None',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title (${items.length})',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((result) =>
            _buildSemanticItem(context, result, semanticHalfLifeHours)),
      ],
    );
  }

  Widget _buildSemanticItem(
    BuildContext context,
    SemanticSearchResult result,
    double semanticHalfLifeHours,
  ) {
    // Get content from chunk
    final content = result.chunk.text;
    final entityType = result.chunk.sourceEntityType;
    final similarity = result.similarity;

    // Get timestamp from source entity if available
    final now = DateTime.now();
    final entityTime = result.sourceEntity?.updatedAt ?? now;
    final ageHours = now.difference(entityTime).inMinutes / 60.0;
    final decay = _computeDecay(ageHours, semanticHalfLifeHours);
    final fusedScore = similarity * decay;

    final timeAgo = result.sourceEntity != null
        ? timeago.format(result.sourceEntity!.updatedAt)
        : 'unknown';

    // Calculate explicit age in days/hours
    final ageDays = ageHours / 24.0;
    final ageDisplay = ageDays >= 1.0
        ? '${ageDays.toStringAsFixed(1)}d'
        : '${ageHours.toStringAsFixed(1)}h';

    // Get conversation name for Claude imports
    String? conversationName;
    if (result.sourceEntity is Invocation) {
      final inv = result.sourceEntity as Invocation;
      conversationName = inv.metadata?['sourceConversationName'] as String?;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Score badges: Similarity | Decay | Fused + entity type + timestamp
          Row(
            children: [
              // Similarity badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: _getScoreColor(similarity),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'S:${(similarity * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Decay badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: _getScoreColor(decay),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'D:${(decay * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Fused score badge (similarity * decay)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'F:${(fusedScore * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                entityType.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              // Age badge (days or hours)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade600,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  ageDisplay,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                timeAgo,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),

          // Conversation name (for Claude imports)
          if (conversationName != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.folder_outlined,
                    size: 12, color: Colors.blue.shade400),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    conversationName,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.blue.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 6),

          // Content
          Text(
            content.length > 150 ? '${content.substring(0, 150)}...' : content,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade800,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildContextItem(
    BuildContext context,
    Invocation inv,
    bool showDecay,
  ) {
    // Extract text content
    final content = inv.toEmbeddingInput();
    final timeAgo = timeago.format(inv.updatedAt);

    // Calculate decay score (simplified - actual score would come from ContextSelector)
    final ageHours =
        DateTime.now().difference(inv.updatedAt).inHours.toDouble();
    final halfLife = showDecay ? 24.0 : 720.0; // conversation vs semantic
    final decayScore = _computeDecay(ageHours, halfLife);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Score badge + type + timestamp
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getScoreColor(decayScore),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  decayScore.toStringAsFixed(2),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                inv.componentType.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                timeAgo,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Content
          Text(
            content.length > 100 ? '${content.substring(0, 100)}...' : content,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade800,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Compute temporal decay score using exponential half-life formula
  /// (matches ContextSelector._computeDecay for consistency)
  double _computeDecay(double ageHours, double halfLifeHours) {
    if (ageHours <= 0) return 1.0;
    return exp(-ln2 * ageHours / halfLifeHours);
  }

  Color _getScoreColor(double score) {
    if (score >= 0.8) return Colors.green;
    if (score >= 0.6) return Colors.orange;
    return Colors.red;
  }

  Future<void> _handleLongPress(BuildContext context) async {
    if (widget.contextBundle == null ||
        widget.feedbackGiven ||
        widget.onFeedback == null) {
      return;
    }

    final result = await showFeedbackBottomSheet(
      context,
      title: 'Rate Context Selection',
      description:
          'Was this context selection helpful for generating a good response?',
    );

    if (result != null) {
      widget.onFeedback!(result);
    }
  }
}
