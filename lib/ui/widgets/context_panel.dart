/// # Context Panel
///
/// Displays the context bundle selected by ContextSelector.
/// Shows conversation thread + semantic matches with scores.
/// Long-press to provide feedback on context selection quality.

import 'package:flutter/material.dart';
import 'package:everything_stack_template/services/types/context_selector_types.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'feedback_bottom_sheet.dart';
import 'package:timeago/timeago.dart' as timeago;

class ContextPanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _handleLongPress(context),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.psychology, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Context Selection',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  if (feedbackGiven)
                    Icon(Icons.check_circle, color: Colors.green.shade700, size: 20)
                  else
                    const Text(
                      'Long-press to rate',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: contextBundle == null
                  ? const Center(
                      child: Text(
                        'No context selected yet',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Recent Conversation
                        _buildSection(
                          context,
                          title: 'Recent Conversation',
                          items: contextBundle!.conversationThread,
                          showDecay: true,
                        ),

                        const SizedBox(height: 24),

                        // Semantic Matches
                        _buildSection(
                          context,
                          title: 'Semantic Matches',
                          items: contextBundle!.semanticContext,
                          showDecay: false,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
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

  Widget _buildContextItem(
    BuildContext context,
    Invocation inv,
    bool showDecay,
  ) {
    // Extract text content
    final content = inv.toEmbeddingInput();
    final timeAgo = timeago.format(inv.updatedAt);

    // Calculate decay score (simplified - actual score would come from ContextSelector)
    final ageHours = DateTime.now().difference(inv.updatedAt).inHours.toDouble();
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

  double _computeDecay(double ageHours, double halfLifeHours) {
    if (ageHours <= 0) return 1.0;
    return 0.5 * (ageHours / halfLifeHours); // Simplified linear decay for display
  }

  Color _getScoreColor(double score) {
    if (score >= 0.8) return Colors.green;
    if (score >= 0.6) return Colors.orange;
    return Colors.red;
  }

  Future<void> _handleLongPress(BuildContext context) async {
    if (contextBundle == null || feedbackGiven || onFeedback == null) {
      return;
    }

    final result = await showFeedbackBottomSheet(
      context,
      title: 'Rate Context Selection',
      description: 'Was this context selection helpful for generating a good response?',
    );

    if (result != null) {
      onFeedback!(result);
    }
  }
}
