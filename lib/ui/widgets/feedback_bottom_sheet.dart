/// # Feedback Bottom Sheet
///
/// Reusable bottom sheet for collecting binary feedback (thumbs up/down).
/// Used by both ContextPanel and ChatPanel for training feedback.

import 'package:flutter/material.dart';

/// Shows a bottom sheet with thumbs up/down feedback buttons.
///
/// Returns:
/// - `true` for thumbs up (positive feedback)
/// - `false` for thumbs down (negative feedback)
/// - `null` if user canceled (dismissed without selecting)
Future<bool?> showFeedbackBottomSheet(
  BuildContext context, {
  required String title,
  String? description,
}) async {
  return showModalBottomSheet<bool>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),

          if (description != null) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 24),

          // Feedback buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Thumbs Down
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.thumb_down_outlined, size: 32),
                  label: const Text('Not Helpful'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // Thumbs Up
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.thumb_up_outlined, size: 32),
                  label: const Text('Helpful'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Cancel button
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}
