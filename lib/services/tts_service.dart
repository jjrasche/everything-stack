library;

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:get_it/get_it.dart';

import '../core/invocation.dart';
import '../core/invocation_repository.dart';
import '../core/adaptation_state_repository.dart';
import '../core/feedback.dart' as core_feedback;
import '../core/feedback_repository.dart';
import '../core/trainable.dart';
import '../core/component_types.dart';
import '../core/platform_detector.dart';
import '../core/event.dart';
import './implementations/tts_implementer.dart';
import './implementations/flutter_tts_implementer.dart';
import './types/tts_types.dart';
import './event_bus.dart';

class TTSService with Trainable<TTSAdaptationData> {
  final Map<String, TTSImplementer> _implementers;
  final String _defaultImplementer;
  final InvocationRepository invocationRepo;
  final AdaptationStateRepository adaptationStateRepo;
  final FeedbackRepository feedbackRepo;

  // Track playback state for barge-in
  bool _isPlaying = false;
  String? _currentEventId;

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

    final defaultImpl = _implementers[_defaultImplementer]!;
    if (!defaultImpl.supportedPlatforms.contains(currentPlatform)) {
      throw UnsupportedError(
        'Default TTS implementer "$_defaultImplementer" does not support '
        'platform "$currentPlatform". Supported platforms: ${defaultImpl.supportedPlatforms}',
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
    final state =
        await _getAdaptationState(implementer.implementerName, userId);

    // 3. Track playback state
    _isPlaying = true;
    _currentEventId = eventId;

    // 4. Publish tts_started event (for barge-in detection)
    final eventBus = GetIt.instance<EventBus>();
    await eventBus.publish(Event(
      eventType: 'tts_started',
      correlationId: eventId,
      source: 'tts',
      payloadJson: jsonEncode({'text': text}),
    ));
    debugPrint('🔊 [TTSService] TTS started');

    // 4. Call implementer with text
    final output = await implementer.synthesize(
      text: text,
      voiceId: state.voiceId,
      speechRate: state.speechRate,
      pitch: state.pitch,
    );

    // 5. Update playback state
    _isPlaying = false;
    _currentEventId = null;

    // 6. Publish tts_completed event (for auto-resume listening)
    await eventBus.publish(Event(
      eventType: 'tts_completed',
      correlationId: eventId,
      source: 'tts',
      payloadJson: jsonEncode({
        'text': text,
        'duration_seconds': output.durationSeconds,
      }),
    ));
    debugPrint('✅ [TTSService] TTS completed');

    // 7. Log invocation for training feedback
    await recordInvocation(
      eventId,
      Invocation(
        eventId: eventId,
        componentType: ComponentType.tts,
        implementer: implementer.implementerName,
        success: true,
        confidence: 1.0,
        input: TTSInvocationInput(text: text).toJson(),
        output: output.toJson(),
      ),
    );

    // 8. Return audio output
    return output;
  }

  /// Stop TTS playback (for barge-in).
  ///
  /// Called by Coordinator when user starts speaking during TTS.
  /// Publishes tts_stopped event for logging/debugging.
  Future<void> stop() async {
    if (!_isPlaying) {
      debugPrint('ℹ️ [TTSService] stop() called but not playing');
      return;
    }

    debugPrint('🛑 [TTSService] Stopping TTS (barge-in)');

    final implementer = _implementers[_defaultImplementer]!;
    if (implementer is FlutterTtsImplementer) {
      await implementer.stop();
    }

    // Publish tts_stopped event
    final eventBus = GetIt.instance<EventBus>();
    await eventBus.publish(Event(
      eventType: 'tts_stopped',
      correlationId: _currentEventId ?? 'unknown',
      source: 'tts',
      payloadJson: jsonEncode({'reason': 'barge_in'}),
    ));

    _isPlaying = false;
    _currentEventId = null;

    debugPrint('✅ [TTSService] TTS stopped');
  }

  /// Whether TTS is currently playing (for barge-in detection).
  bool get isPlaying => _isPlaying;

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
    final input = TTSInvocationInput.fromJson(invocation.input!);
    final output = TTSInvocationOutput.fromJson(invocation.output!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Text Synthesized:',
            style: Theme.of(context).textTheme.labelLarge),
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
        Text('Was this voice appropriate?',
            style: Theme.of(context).textTheme.labelLarge),
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
  Future<void> trainFromFeedback(
      Invocation invocation, core_feedback.Feedback feedback) async {
    // TODO: Implement training algorithm
    // 1. Parse typed feedback: TTSFeedback.fromJson(feedback.correctedData)
    // 2. Get current AdaptationState for feedback.implementer
    // 3. Update voice preference based on feedback
    // 4. Save updated AdaptationState
  }

  // ============ Trainable Interface Implementation ============

  @override
  String get componentType => 'tts';

  @override
  TTSAdaptationData createDefaultData() => TTSAdaptationData.defaults();

  @override
  TTSAdaptationData deserializeData(String json) =>
      TTSAdaptationData.fromJson(jsonDecode(json) as Map<String, dynamic>);
}
