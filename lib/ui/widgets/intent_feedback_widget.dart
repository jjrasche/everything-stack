/// # Intent Feedback Widget
///
/// Allows user to provide feedback on Intent detection.
/// Shows detected intent, confidence, and resolved tools.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:everything_stack_template/domain/invocations.dart';
import 'package:everything_stack_template/domain/feedback.dart' as feedback_model;
import 'package:everything_stack_template/ui/providers/trainable_providers.dart';

class IntentFeedbackWidget extends ConsumerStatefulWidget {
  final IntentInvocation invocation;
  final String invocationId;
  final String turnId;

  const IntentFeedbackWidget({
    super.key,
    required this.invocation,
    required this.invocationId,
    required this.turnId,
  });

  @override
  ConsumerState<IntentFeedbackWidget> createState() => _IntentFeedbackWidgetState();
}

class _IntentFeedbackWidgetState extends ConsumerState<IntentFeedbackWidget> {
  late TextEditingController _correctedToolController;
  late Map<String, dynamic> _correctedSlots;
  feedback_model.FeedbackAction? _selectedAction;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _correctedToolController = TextEditingController(text: widget.invocation.toolName);
    // Parse slotsJson
    try {
      _correctedSlots = widget.invocation.slotsJson.isNotEmpty
          ? Map<String, dynamic>.from(
              Uri.splitQueryString(widget.invocation.slotsJson))
          : {};
    } catch (e) {
      _correctedSlots = {};
    }
  }

  @override
  void dispose() {
    _correctedToolController.dispose();
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

        // Tool display
        Text(
          'Detected Tool & Slots',
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.invocation.toolName.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.purple[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.purple[400]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.build, size: 16, color: Colors.purple[700]),
                      const SizedBox(width: 4),
                      Text(
                        widget.invocation.toolName,
                        style: TextStyle(
                          color: Colors.purple[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble, size: 16, color: Colors.grey[700]),
                      const SizedBox(width: 4),
                      Text(
                        'Conversational (no tool)',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_correctedSlots.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _correctedSlots.entries.map((entry) {
                    return Chip(
                      label: Text('${entry.key}: ${entry.value}'),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ],
            ],
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ActionButton(
              icon: Icons.check_circle,
              label: 'Confirm',
              color: Colors.green,
              isSelected: _selectedAction == feedback_model.FeedbackAction.confirm,
              onPressed: () => setState(() => _selectedAction = feedback_model.FeedbackAction.confirm),
              tooltip: 'Intent classification is correct',
            ),
            _ActionButton(
              icon: Icons.edit,
              label: 'Correct',
              color: Colors.blue,
              isSelected: _selectedAction == feedback_model.FeedbackAction.correct,
              onPressed: () => setState(() => _selectedAction = feedback_model.FeedbackAction.correct),
              tooltip: 'Provide the correct intent',
            ),
            _ActionButton(
              icon: Icons.cancel,
              label: 'Deny',
              color: Colors.red,
              isSelected: _selectedAction == feedback_model.FeedbackAction.deny,
              onPressed: () => setState(() => _selectedAction = feedback_model.FeedbackAction.deny),
              tooltip: 'Intent classification is wrong',
            ),
            _ActionButton(
              icon: Icons.skip_next,
              label: 'Ignore',
              color: Colors.grey,
              isSelected: _selectedAction == feedback_model.FeedbackAction.ignore,
              onPressed: () => setState(() => _selectedAction = feedback_model.FeedbackAction.ignore),
              tooltip: 'Skip learning from this',
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Correction input
        if (_selectedAction == feedback_model.FeedbackAction.correct) ...[
          Text(
            'Correct Tool Name',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _correctedToolController,
            decoration: InputDecoration(
              hintText: 'Enter the correct tool (or empty for conversational)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Save button
        if (_selectedAction != null && _selectedAction != feedback_model.FeedbackAction.ignore)
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
        componentType: 'intent',
        action: _selectedAction!,
        correctedData: _selectedAction == feedback_model.FeedbackAction.correct
            ? jsonEncode({'toolName': _correctedToolController.text, 'slots': _correctedSlots})
            : null,
      );

      final feedbackRepo = ref.read(feedbackRepositoryProvider);
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
