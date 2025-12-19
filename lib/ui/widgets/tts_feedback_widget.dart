/// # TTS Feedback Widget
///
/// Allows user to provide feedback on TTS (text-to-speech) output.
/// Shows generated audio parameters and speech rate.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:everything_stack_template/domain/invocations.dart';
import 'package:everything_stack_template/domain/feedback.dart' as feedback_model;
import 'package:everything_stack_template/ui/providers/trainable_providers.dart';

class TTSFeedbackWidget extends ConsumerStatefulWidget {
  final TTSInvocation invocation;
  final String invocationId;
  final String turnId;

  const TTSFeedbackWidget({
    super.key,
    required this.invocation,
    required this.invocationId,
    required this.turnId,
  });

  @override
  ConsumerState<TTSFeedbackWidget> createState() => _TTSFeedbackWidgetState();
}

class _TTSFeedbackWidgetState extends ConsumerState<TTSFeedbackWidget> {
  feedback_model.FeedbackAction? _selectedAction;
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Text to synthesize
        Text(
          'Text to Synthesize',
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
            widget.invocation.text,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 16),

        // Audio info
        Text(
          'Audio Output',
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
              _ParameterRow('Audio ID', widget.invocation.audioId.substring(0, 8)),
              _ParameterRow('Status', widget.invocation.lastError == null ? 'OK' : 'Error'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Feedback actions
        Text(
          'Voice Quality Feedback',
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
              label: 'Satisfied',
              color: Colors.green,
              isSelected: _selectedAction == feedback_model.FeedbackAction.confirm,
              onPressed: () => setState(() => _selectedAction = feedback_model.FeedbackAction.confirm),
              tooltip: 'Voice quality and speed are good',
            ),
            _ActionButton(
              icon: Icons.tune,
              label: 'Adjust Settings',
              color: Colors.blue,
              isSelected: _selectedAction == feedback_model.FeedbackAction.correct,
              onPressed: () => setState(() => _selectedAction = feedback_model.FeedbackAction.correct),
              tooltip: 'I want different voice or speed settings',
            ),
            _ActionButton(
              icon: Icons.cancel,
              label: 'Unsatisfied',
              color: Colors.red,
              isSelected: _selectedAction == feedback_model.FeedbackAction.deny,
              onPressed: () => setState(() => _selectedAction = feedback_model.FeedbackAction.deny),
              tooltip: 'Voice quality or speed is poor',
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

        // Notes
        if (_selectedAction == feedback_model.FeedbackAction.correct)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What needs adjustment?',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _AdjustmentOption(
                        label: 'Slower',
                        selected: false,
                        onTap: () {},
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AdjustmentOption(
                        label: 'Faster',
                        selected: false,
                        onTap: () {},
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _AdjustmentOption(
                        label: 'Different Voice',
                        selected: false,
                        onTap: () {},
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
        else if (_selectedAction == feedback_model.FeedbackAction.deny)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[300]!),
            ),
            child: Text(
              'Your dissatisfaction will help the system learn better voice settings.',
              style: TextStyle(color: Colors.red[700], fontSize: 13),
            ),
          ),
        const SizedBox(height: 16),

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
        componentType: 'tts',
        action: _selectedAction!,
        correctedData: null,
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
}

class _ParameterRow extends StatelessWidget {
  final String label;
  final String value;

  const _ParameterRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(color: Colors.grey[700])),
        ],
      ),
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

class _AdjustmentOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AdjustmentOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.blue[100] : Colors.transparent,
          border: Border.all(
            color: selected ? Colors.blue : Colors.blue[200]!,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Colors.blue[900] : Colors.blue[700],
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
