/// # TTSService
///
/// Smart orchestration service for text-to-speech capabilities.
/// Holds multiple TTS implementations and coordinates adaptation learning.
///
/// ## Key Responsibilities
/// - Hold Map<String, TTSImplementer> (FlutterTts, Google Cloud, etc.)
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
import './implementations/tts_implementer.dart';
import './types/tts_types.dart';

class TTSService implements Trainable {
  final Map<String, TTSImplementer> _implementers;
  final String _defaultImplementer;
  final InvocationRepository invocationRepo;
  final AdaptationStateRepository adaptationStateRepo;
  final FeedbackRepository feedbackRepo;

  TTSService({
    required Map<String, TTSImplementer> implementers,
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

  /// Synthesize text using adaptation-aware parameters.
  ///
  /// Flow:
  /// 1. Select implementer (specified or default)
  /// 2. Load adaptation state (voice preferences, speech rate)
  /// 3. Call implementer with text
  /// 4. Log invocation for training feedback
  /// 5. Return audio
  Future<TTSInvocationOutput> synthesize({
    required String eventId,
    required String text,
    String? implementerName,
    String? userId,
  }) async {
    // 1. Get implementer (specified or default)
    final implementer = _implementers[implementerName ?? _defaultImplementer]!;

    // 2. Read adaptation state for this implementer + user
    final state = await _getAdaptationState(implementer.implementerName, userId);

    // 3. Call implementer with text
    final output = await implementer.synthesize(
      text: text,
      voicePreference: state.voiceId,
      speechRate: state.speechRate,
      pitch: state.pitch,
    );

    // 4. Log invocation for training feedback
    final invocation = Invocation(
      eventId: eventId,
      componentType: ComponentType.tts,
      implementer: implementer.implementerName,
      success: true,
      confidence: 1.0,
      input: TTSInvocationInput(text: text).toJson(),
      output: output.toJson(),
    );
    await invocationRepo.save(invocation);

    // 5. Return audio output
    return output;
  }

  /// Synthesize text to speech and log (Coordinator compatibility wrapper).
  /// This is a convenience method - synthesize() already logs.
  Future<void> synthesizeAndLog({
    required String text,
    required String eventId,
  }) async {
    // Call the normal synthesize method (which already logs the invocation)
    await synthesize(eventId: eventId, text: text);
  }

  /// Get adaptation state for this implementer, or defaults if not found.
  Future<TTSAdaptationData> _getAdaptationState(
    String implementerName,
    String? userId,
  ) async {
    final state = await adaptationStateRepo.getForComponent(
      ComponentType.tts,
      implementer: implementerName,
      userId: userId,
    );

    return state != null
        ? TTSAdaptationData.fromJson(state.data)
        : TTSAdaptationData.defaults();
  }

  // ============ Trainable Implementation ============

  @override
  Widget buildFeedbackUI(BuildContext context, Invocation invocation) {
    // Parse typed input/output from invocation
    final input = TTSInvocationInput.fromJson(invocation.input!);
    final output = TTSInvocationOutput.fromJson(invocation.output!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Text Synthesized:', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(input.text),
        ),
        const SizedBox(height: 16),
        Text('Audio Duration: ${output.durationSeconds.toStringAsFixed(1)}s',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        Text('Was this voice appropriate?', style: Theme.of(context).textTheme.labelLarge),
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
                // TODO: Record feedback with different voice
              },
              child: const Text('Change Voice'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<void> trainFromFeedback(Invocation invocation, core_feedback.Feedback feedback) async {
    // TODO: Implement training algorithm
    // 1. Parse typed feedback: TTSFeedback.fromJson(feedback.correctedData)
    // 2. Get current AdaptationState for feedback.implementer
    // 3. Update voice preference based on feedback
    // 4. Save updated AdaptationState
  }
}
