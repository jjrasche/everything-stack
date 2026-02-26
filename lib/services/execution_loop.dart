import 'dart:async';
import 'dart:convert';
import '../core/invocation.dart';
import '../core/event.dart';
import '../core/invocation_repository.dart';
import 'inference_service.dart';
import 'tts_service.dart';
import 'event_bus.dart';

class ExecutionLoop {
  final InferenceService inferenceService;
  final TTSService ttsService;
  final InvocationRepository<Invocation> invocationRepo;
  final EventBus eventBus;
  final String model;

  StreamSubscription<Event>? _eventSubscription;

  ExecutionLoop({
    required this.inferenceService,
    required this.ttsService,
    required this.invocationRepo,
    required this.eventBus,
    this.model = 'llama-3.1-8b-instant',
  });

  void initialize() {
    _eventSubscription = eventBus.subscribe().listen(_routeEvent);
  }

  void dispose() {
    _eventSubscription?.cancel();
  }

  Future<void> _routeEvent(Event event) async {
    switch (event.eventType) {
      case 'start_of_turn':
        if (ttsService.isPlaying) await ttsService.stop();
      case 'transcription_complete':
        await _handleTranscription(event);
    }
  }

  Future<void> _handleTranscription(Event event) async {
    final correlationId = event.correlationId;
    try {
      final response = await _generateResponse(event.toInputString());
      await _publishResult(correlationId, response: response);
      if (response.isNotEmpty) {
        await ttsService.synthesize(text: response, eventId: correlationId);
      }
    } catch (error) {
      await _publishResult(correlationId, errorMessage: '$error');
    }
  }

  Future<String> _generateResponse(String utterance) async {
    final recentTurns = await _fetchRecentTurns();
    final llmResponse = await inferenceService.chatWithTools(
      model: model,
      messages: _buildMessages(recentTurns, utterance),
    );
    return llmResponse.content ?? '';
  }

  Future<List<Invocation>> _fetchRecentTurns() async {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 30));
    final allInvocations = await invocationRepo.findAll();
    final recentTurns = allInvocations
        .where((inv) => inv.componentType == 'llm' && inv.updatedAt.isAfter(cutoff))
        .toList()
      ..sort((older, newer) => older.createdAt.compareTo(newer.createdAt));
    return recentTurns.length > 10
        ? recentTurns.sublist(recentTurns.length - 10)
        : recentTurns;
  }

  List<Map<String, dynamic>> _buildMessages(
    List<Invocation> recentTurns, String utterance,
  ) => [
    {'role': 'system', 'content':
      'You are a helpful voice assistant. Brief, conversational. '
      '1-2 sentences unless asked for more. No markdown — spoken aloud.'},
    for (final turn in recentTurns) ...[
      if (turn.input?['prompt'] case final String p when p.isNotEmpty)
        {'role': 'user', 'content': p},
      if (turn.output?['response'] case final String r when r.isNotEmpty)
        {'role': 'assistant', 'content': r},
    ],
    {'role': 'user', 'content': utterance},
  ];

  Future<void> _publishResult(String correlationId, {String? response, String? errorMessage}) async {
    final isSuccess = errorMessage == null;
    await eventBus.publish(Event(
      eventType: isSuccess ? 'orchestration_complete' : 'orchestration_error',
      correlationId: correlationId,
      source: 'execution_loop',
      payloadJson: jsonEncode({
        'success': isSuccess,
        'response': response ?? '',
        if (errorMessage != null) 'errorMessage': errorMessage,
      }),
    ));
  }
}
