/// # Turn List Screen
///
/// Displays all turns marked for feedback.
/// User selects a turn to provide feedback on invocations from that turn.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:everything_stack_template/domain/turn.dart';
import 'package:everything_stack_template/ui/providers/turn_providers.dart';

class TurnListScreen extends ConsumerWidget {
  const TurnListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final turnsAsync = ref.watch(turnsForFeedbackProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feedback Review'),
        elevation: 0,
      ),
      body: turnsAsync.when(
        data: (turns) {
          if (turns.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.task_alt,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No turns awaiting feedback',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Come back when turns are marked for review',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: turns.length,
            itemBuilder: (context, index) {
              final turn = turns[index];
              return _TurnListItem(
                turn: turn,
                onTap: () {
                  // Select turn for feedback review
                  // Note: FeedbackReviewScreen was removed in recent refactoring
                  // TODO: Implement feedback review UI in Phase 2
                  ref.read(selectedTurnProvider.notifier).state = turn;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Turn selected. Feedback review UI coming soon.'),
                    ),
                  );
                },
              );
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error,
                size: 64,
                color: Colors.red[400],
              ),
              const SizedBox(height: 16),
              Text(
                'Error loading turns',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  error.toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TurnListItem extends StatelessWidget {
  final Turn turn;
  final VoidCallback onTap;

  const _TurnListItem({
    required this.turn,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final invocationCount = turn.getInvocationIds().length;
    final timestamp = turn.createdAt;
    final formattedTime = _formatDateTime(timestamp);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        title: Text(
          'Turn ${turn.uuid.substring(0, 8)}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              formattedTime,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                if (turn.sttInvocationId != null) _ComponentBadge(label: 'STT'),
                if (turn.llmInvocationId != null) _ComponentBadge(label: 'LLM'),
                if (turn.ttsInvocationId != null) _ComponentBadge(label: 'TTS'),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$invocationCount items',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey[400],
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) {
      return 'just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
  }
}

class _ComponentBadge extends StatelessWidget {
  final String label;

  const _ComponentBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = {
      'STT': Colors.blue,
      'LLM': Colors.purple,
      'TTS': Colors.orange,
    };

    final color = colors[label] ?? Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}
