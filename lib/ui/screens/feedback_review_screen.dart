/// # Feedback Review Screen
///
/// Shows invocations from a selected turn.
/// User provides feedback (confirm, correct, deny, ignore) on each component.
/// User can trigger training via "Train" button to update adaptation state.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:everything_stack_template/domain/turn.dart';
import 'package:everything_stack_template/domain/feedback.dart';
import 'package:everything_stack_template/domain/invocations.dart';
import 'package:everything_stack_template/ui/providers/turn_providers.dart';
import 'package:everything_stack_template/ui/providers/trainable_providers.dart';
import 'package:everything_stack_template/ui/widgets/stt_feedback_widget.dart';
import 'package:everything_stack_template/ui/widgets/llm_feedback_widget.dart';
import 'package:everything_stack_template/ui/widgets/tts_feedback_widget.dart';

class FeedbackReviewScreen extends ConsumerStatefulWidget {
  final Turn turn;

  const FeedbackReviewScreen({
    super.key,
    required this.turn,
  });

  @override
  ConsumerState<FeedbackReviewScreen> createState() => _FeedbackReviewScreenState();
}

class _FeedbackReviewScreenState extends ConsumerState<FeedbackReviewScreen> {
  bool _isTraining = false;
  String? _trainingError;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Feedback for Turn ${widget.turn.uuid.substring(0, 8)}'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // STT Invocation
              if (widget.turn.sttInvocationId != null)
                _FeedbackSection(
                  componentType: 'STT',
                  invocationId: widget.turn.sttInvocationId!,
                  turnId: widget.turn.uuid,
                  color: Colors.blue,
                ),

              // LLM Invocation
              if (widget.turn.llmInvocationId != null)
                _FeedbackSection(
                  componentType: 'LLM',
                  invocationId: widget.turn.llmInvocationId!,
                  turnId: widget.turn.uuid,
                  color: Colors.purple,
                ),

              // TTS Invocation
              if (widget.turn.ttsInvocationId != null)
                _FeedbackSection(
                  componentType: 'TTS',
                  invocationId: widget.turn.ttsInvocationId!,
                  turnId: widget.turn.uuid,
                  color: Colors.orange,
                ),

              const SizedBox(height: 24),

              // Training Section
              Card(
                color: Colors.amber[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.school, color: Colors.amber[800]),
                          const SizedBox(width: 8),
                          Text(
                            'Learn from Feedback',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.amber[900],
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Review the feedback above, then train the system to learn from your corrections.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      if (_trainingError != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[300]!),
                          ),
                          child: Text(
                            _trainingError!,
                            style: TextStyle(color: Colors.red[900]),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      ElevatedButton.icon(
                        onPressed: _isTraining ? null : _handleTrain,
                        icon: _isTraining
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.psychology),
                        label: Text(_isTraining ? 'Training...' : 'Train System'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleTrain() async {
    setState(() {
      _isTraining = true;
      _trainingError = null;
    });

    try {
      // Get trainable services (Phase 0: LLM + TTS only)
      // STT training deferred to Phase 1
      final llmService = ref.read(llmTrainableProvider);
      final ttsService = ref.read(ttsTrainableProvider);

      // Train each service from feedback for this turn
      if (widget.turn.llmInvocationId != null) {
        await llmService.trainFromFeedback(widget.turn.uuid);
      }
      if (widget.turn.ttsInvocationId != null) {
        await ttsService.trainFromFeedback(widget.turn.uuid);
      }

      // Mark turn as trained
      final turnRepo = ref.read(turnRepositoryProvider);
      final updatedTurn = widget.turn.copyWith(
        markedForFeedback: false,
        feedbackTrainedAt: DateTime.now(),
      );
      await turnRepo.save(updatedTurn);

      // Refresh turns list
      ref.invalidate(turnsForFeedbackProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('System trained successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Pop back to list
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _trainingError = 'Training failed: ${e.toString()}';
        _isTraining = false;
      });
    }
  }
}

class _FeedbackSection extends ConsumerWidget {
  final String componentType;
  final String invocationId;
  final String turnId;
  final Color color;

  const _FeedbackSection({
    required this.componentType,
    required this.invocationId,
    required this.turnId,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invocationAsync = ref.watch(
      invocationByIdProvider((invocationId, componentType.toLowerCase())),
    );

    return invocationAsync.when(
      data: (invocation) {
        if (invocation == null) {
          return _ErrorCard(
            componentType: componentType,
            color: color,
            error: 'Invocation not found',
          );
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                color: color.withOpacity(0.1),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      componentType,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: _buildFeedbackWidget(
                  componentType,
                  invocation,
                  invocationId,
                  turnId,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text('Loading $componentType invocation...'),
            ],
          ),
        ),
      ),
      error: (error, stack) => _ErrorCard(
        componentType: componentType,
        color: color,
        error: error.toString(),
      ),
    );
  }

  Widget _buildFeedbackWidget(
    String componentType,
    dynamic invocation,
    String invocationId,
    String turnId,
  ) {
    switch (componentType.toLowerCase()) {
      case 'stt':
        return STTFeedbackWidget(
          invocation: invocation as STTInvocation,
          invocationId: invocationId,
          turnId: turnId,
        );
      case 'llm':
        return LLMFeedbackWidget(
          invocation: invocation as LLMInvocation,
          invocationId: invocationId,
          turnId: turnId,
        );
      case 'tts':
        return TTSFeedbackWidget(
          invocation: invocation as TTSInvocation,
          invocationId: invocationId,
          turnId: turnId,
        );
      default:
        return Text('Unknown component: $componentType');
    }
  }
}

class _ErrorCard extends StatelessWidget {
  final String componentType;
  final Color color;
  final String error;

  const _ErrorCard({
    required this.componentType,
    required this.color,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              componentType,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.red[900],
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(color: Colors.red[700]),
            ),
          ],
        ),
      ),
    );
  }
}
