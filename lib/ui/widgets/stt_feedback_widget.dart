/// # STT Feedback Widget
///
/// Allows user to provide feedback on STT (speech-to-text) invocation.
/// Shows transcription and confidence score.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:everything_stack_template/domain/invocations.dart';
import 'package:everything_stack_template/domain/feedback.dart'
    as feedback_model;
import 'package:everything_stack_template/services/service_locator.dart';

class STTFeedbackWidget extends ConsumerStatefulWidget {
  final STTInvocation invocation;
  final String invocationId;
  final String turnId;

  const STTFeedbackWidget({
    super.key,
    required this.invocation,
    required this.invocationId,
    required this.turnId,
  });

  @override
  ConsumerState<STTFeedbackWidget> createState() => _STTFeedbackWidgetState();
}

class _STTFeedbackWidgetState extends ConsumerState<STTFeedbackWidget> {
  late TextEditingController _correctionController;
  feedback_model.FeedbackAction? _selectedAction;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _correctionController =
        TextEditingController(text: widget.invocation.output);
  }

  @override
  void dispose() {
    _correctionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Confidence indicator
        Row(
          children: [
            const Text('Confidence: '),
            Text(
              '${(widget.invocation.confidence * 100).toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LinearProgressIndicator(
                value: widget.invocation.confidence,
                minHeight: 8,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  _getConfidenceColor(widget.invocation.confidence),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Transcription display
        Text(
          'Transcription',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Text(
            widget.invocation.output,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 16),

        // Feedback actions
        Text(
          'Your Feedback',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 8),
        _FeedbackActionButtons(
          selectedAction: _selectedAction,
          onActionSelected: (action) {
            setState(() => _selectedAction = action);
          },
        ),
        const SizedBox(height: 16),

        // Correction input (if needed)
        if (_selectedAction == feedback_model.FeedbackAction.correct) ...[
          Text(
            'Corrected Transcription',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _correctionController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Enter the correct transcription',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Save feedback button
        if (_selectedAction != null &&
            _selectedAction != feedback_model.FeedbackAction.ignore)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveFeedback,
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Feedback'),
            ),
          )
        else if (_selectedAction == feedback_model.FeedbackAction.ignore)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[400]!),
            ),
            child: const Row(
              children: [
                Icon(Icons.info, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text('This feedback will not be used for training'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _saveFeedback() async {
    if (_selectedAction == null) return;

    setState(() => _isSaving = true);

    try {
      final feedback = feedback_model.Feedback(
        invocationId: widget.invocationId,
        turnId: widget.turnId,
        componentType: 'stt',
        action: _selectedAction!,
        correctedData: _selectedAction == feedback_model.FeedbackAction.correct
            ? _correctionController.text
            : null,
      );

      final feedbackRepo = ServiceLocator.feedbackRepository;
      await feedbackRepo.save(feedback);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feedback saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving feedback: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.6) return Colors.amber;
    return Colors.red;
  }
}

class _FeedbackActionButtons extends StatelessWidget {
  final feedback_model.FeedbackAction? selectedAction;
  final Function(feedback_model.FeedbackAction) onActionSelected;

  const _FeedbackActionButtons({
    required this.selectedAction,
    required this.onActionSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ActionButton(
          icon: Icons.check_circle,
          label: 'Confirm',
          color: Colors.green,
          isSelected: selectedAction == feedback_model.FeedbackAction.confirm,
          onPressed: () =>
              onActionSelected(feedback_model.FeedbackAction.confirm),
          tooltip: 'Transcription is correct',
        ),
        _ActionButton(
          icon: Icons.edit,
          label: 'Correct',
          color: Colors.blue,
          isSelected: selectedAction == feedback_model.FeedbackAction.correct,
          onPressed: () =>
              onActionSelected(feedback_model.FeedbackAction.correct),
          tooltip: 'I\'ll provide the correct transcription',
        ),
        _ActionButton(
          icon: Icons.cancel,
          label: 'Deny',
          color: Colors.red,
          isSelected: selectedAction == feedback_model.FeedbackAction.deny,
          onPressed: () => onActionSelected(feedback_model.FeedbackAction.deny),
          tooltip: 'Transcription is wrong',
        ),
        _ActionButton(
          icon: Icons.skip_next,
          label: 'Ignore',
          color: Colors.grey,
          isSelected: selectedAction == feedback_model.FeedbackAction.ignore,
          onPressed: () =>
              onActionSelected(feedback_model.FeedbackAction.ignore),
          tooltip: 'Skip learning from this',
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onPressed;
  final String tooltip;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
              border: Border.all(
                color: isSelected ? color : Colors.grey[400]!,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
