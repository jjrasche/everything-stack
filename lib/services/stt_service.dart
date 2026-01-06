/// # STTService
///
/// Smart orchestration service for speech-to-text capabilities.
/// Holds multiple STT implementations and coordinates adaptation learning.
///
/// ## Key Responsibilities
/// - Hold Map<String, STTImplementer> (Deepgram, Google Speech, etc.)
/// - Select implementer (specified or default)
/// - Read/apply adaptation state per implementer
/// - Log invocations for training feedback
/// - Train from feedback (update AdaptationState)
///
/// ## Design Pattern
/// Service (smart, orchestration) = Composition of Implementers (dumb, API wrappers)

import 'package:flutter/material.dart';

import '../core/invocation.dart';
import '../core/invocation_repository.dart';
import '../core/adaptation_state_repository.dart';
import '../core/adaptation_state.dart';
import '../core/feedback.dart' as core_feedback;
import '../core/feedback_repository.dart';
import '../core/trainable.dart';
import '../core/component_types.dart';
import './implementations/stt_implementer.dart';
import './types/stt_types.dart';

abstract class STTService implements Trainable {
  final Map<String, STTImplementer> _implementers;
  final String _defaultImplementer;
  final InvocationRepository invocationRepo;
  final AdaptationStateRepository adaptationStateRepo;
  final FeedbackRepository feedbackRepo;

  STTService({
    required Map<String, STTImplementer> implementers,
    required String defaultImplementer,
    required this.invocationRepo,
    required this.adaptationStateRepo,
    required this.feedbackRepo,
  })  : _implementers = implementers,
        _defaultImplementer = defaultImplementer {
    if (!_implementers.containsKey(_defaultImplementer)) {
      throw ArgumentError(
        'Default implementer "$_defaultImplementer" not found in implementers',
      );
    }
  }

  /// Recognize audio using adaptation-aware parameters.
  ///
  /// Flow:
  /// 1. Select implementer (specified or default)
  /// 2. Load adaptation state (confidence threshold, feedback count)
  /// 3. Call implementer with audio
  /// 4. Log invocation for training feedback
  /// 5. Return transcription
  Future<String> recognize({
    required String eventId,
    required String audioId,
    required double durationSeconds,
    String? implementerName,
    String? userId,
  }) async {
    // 1. Get implementer (specified or default)
    final implementer = _implementers[implementerName ?? _defaultImplementer]!;

    // 2. Read adaptation state for this implementer + user
    final state = await _getAdaptationState(implementer.implementerName, userId);

    // 3. Call implementer with audio
    final output = await implementer.recognize(
      audioId: audioId,
      durationSeconds: durationSeconds,
    );

    // 4. Log invocation for training feedback
    final invocation = Invocation(
      eventId: eventId,
      componentType: ComponentType.stt,
      implementer: implementer.implementerName,
      success: output.confidence >= state.confidenceThreshold,
      confidence: output.confidence,
      input: STTInvocationInput(
        audioId: audioId,
        durationSeconds: durationSeconds,
      ).toJson(),
      output: output.toJson(),
    );
    await invocationRepo.save(invocation);

    // 5. Return transcription
    return output.transcription;
  }

  /// Get adaptation state for this implementer, or defaults if not found.
  Future<STTAdaptationData> _getAdaptationState(
    String implementerName,
    String? userId,
  ) async {
    final state = await adaptationStateRepo.getForComponent(
      ComponentType.stt,
      implementer: implementerName,
      userId: userId,
    );

    return state != null
        ? STTAdaptationData.fromJson(state.data)
        : STTAdaptationData.defaults();
  }

  // ============ Trainable Implementation ============

  @override
  Widget buildFeedbackUI(BuildContext context, Invocation invocation) {
    // Parse typed input/output from invocation
    final output = STTInvocationOutput.fromJson(invocation.output!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Transcription:', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(output.transcription),
        ),
        const SizedBox(height: 16),
        Text('Was this transcription correct?', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton(
              onPressed: () {
                // TODO: Record feedback
              },
              child: const Text('Yes'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                // TODO: Show correction dialog
              },
              child: const Text('Correct'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<void> trainFromFeedback(Invocation invocation, core_feedback.Feedback feedback) async {
    // TODO: Implement training algorithm
    // 1. Parse typed feedback: STTFeedback.fromJson(feedback.correctedData)
    // 2. Get current AdaptationState for feedback.implementer
    // 3. Update confidence threshold based on feedback
    // 4. Save updated AdaptationState
  }
}
