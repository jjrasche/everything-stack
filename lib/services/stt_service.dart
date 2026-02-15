import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../core/invocation.dart';
import '../core/invocation_repository.dart';
import '../core/adaptation_state_repository.dart';
import '../core/adaptation_state.dart';
import '../core/feedback.dart' as core_feedback;
import '../core/feedback_repository.dart';
import '../core/trainable.dart';
import '../core/component_types.dart';
import '../core/event.dart';
import './implementations/stt_implementer.dart';
import './types/stt_types.dart';
import './event_bus.dart';
import './audio_storage.dart';

class STTService with Trainable<STTAdaptationData> {
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

  /// Start live recognition by streaming audio chunks as they arrive.
  ///
  /// This is for real-time streaming mode where audio is sent to the STT service
  /// as it's being recorded, not after recording completes.
  ///
  /// IMPORTANT: Audio is buffered and persisted for training/debugging purposes.
  ///
  /// NOTE: Only DeepgramFluxImplementer currently supports live streaming.
  /// Other implementers will throw UnsupportedError.
  Future<String> startLiveRecognition({
    required Stream<Uint8List> audioStream,
    required String eventId,
    String? implementerName,
    String? userId,
  }) async {
    final implementer = _implementers[implementerName ?? _defaultImplementer]!;
    final state =
        await _getAdaptationState(implementer.implementerName, userId);

    final audioBuffer = <int>[];
    final startTime = DateTime.now();
    final StreamController<Uint8List> bufferedController = StreamController();

    audioStream.listen(
      (chunk) {
        bufferedController.add(chunk); // Forward to implementer
        audioBuffer.addAll(chunk);     // Buffer for persistence
      },
      onDone: bufferedController.close,
      onError: (error) => bufferedController.addError(error),
      cancelOnError: true,
    );

    final output = await implementer.startLiveRecognition(
      audioStream: bufferedController.stream,
      eventId: eventId,
      eotThreshold: state.eotThreshold,
      eagerEotThreshold: state.eagerEotThreshold,
      eotTimeoutMs: state.eotTimeoutMs,
      enablePartialTranscripts: state.enablePartialTranscripts,
      enableEagerProcessing: state.enableEagerProcessing,
    );

    final audioBytes = Uint8List.fromList(audioBuffer);
    final duration = DateTime.now().difference(startTime).inSeconds.toDouble();

    final audioStorage = GetIt.instance.get<AudioStorage>();
    final audioId = await audioStorage.saveAudio(
      audioBytes: audioBytes,
      durationSeconds: duration,
      eventId: eventId,
    );
    debugPrint('   💾 Saved audio: $audioId (${audioBytes.length} bytes, ${duration}s)');

    await recordInvocation(
      eventId,
      Invocation(
        eventId: eventId,
        componentType: ComponentType.stt,
        implementer: implementer.implementerName,
        success: output.confidence >= state.confidenceThreshold,
        confidence: output.confidence,
        input: STTInvocationInput(
          audioId: audioId,           // ✅ Audio persisted and referenced
          durationSeconds: duration,
        ).toJson(),
        output: output.toJson(),
      ),
    );

    final eventBus = GetIt.instance<EventBus>();
    await eventBus.publish(Event(
      eventType: 'transcription_complete',
      correlationId: eventId,
      source: 'stt',
      payloadJson: jsonEncode({'transcript': output.transcription}),
    ));
    debugPrint('   📡 Published transcription_complete event');

    return output.transcription;
  }

  /// Recognize audio using adaptation-aware parameters (batch mode).
  Future<String> recognize({
    required String eventId,
    required String audioId,
    required double durationSeconds,
    String? implementerName,
    String? userId,
  }) async {
    final implementer = _implementers[implementerName ?? _defaultImplementer]!;

    final state =
        await _getAdaptationState(implementer.implementerName, userId);

    final output = await implementer.recognize(
      audioId: audioId,
      durationSeconds: durationSeconds,
      eventId: eventId,
      eotThreshold: state.eotThreshold,
      eagerEotThreshold: state.eagerEotThreshold,
      eotTimeoutMs: state.eotTimeoutMs,
      enablePartialTranscripts: state.enablePartialTranscripts,
      enableEagerProcessing: state.enableEagerProcessing,
    );

    await recordInvocation(
      eventId,
      Invocation(
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
      ),
    );

    final eventBus = GetIt.instance<EventBus>();
    await eventBus.publish(Event(
      eventType: 'transcription_complete',
      correlationId: eventId,
      source: 'stt',
      payloadJson: jsonEncode({'transcript': output.transcription}),
    ));
    debugPrint('   📡 Published transcription_complete event');

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
        ? STTAdaptationData.fromJson(
            jsonDecode(state.dataJson ?? '{}') as Map<String, dynamic>)
        : STTAdaptationData.defaults();
  }

  // ============ Trainable Implementation ============

  @override
  Widget buildFeedbackUI(BuildContext context, Invocation invocation) {
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
        Text('Was this transcription correct?',
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
  Future<void> trainFromFeedback(
      Invocation invocation, core_feedback.Feedback feedback) async {
    // TODO: Implement training algorithm
    // 1. Parse typed feedback: STTFeedback.fromJson(feedback.correctedData)
    // 2. Get current AdaptationState for feedback.implementer
    // 3. Update confidence threshold based on feedback
    // 4. Save updated AdaptationState
  }

  // ============ Trainable Interface Implementation ============

  @override
  String get componentType => 'stt';

  @override
  STTAdaptationData createDefaultData() => STTAdaptationData.defaults();

  @override
  STTAdaptationData deserializeData(String json) =>
      STTAdaptationData.fromJson(jsonDecode(json) as Map<String, dynamic>);
}
