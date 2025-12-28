/// # Test Configuration
///
/// Mock services for integration testing.
/// These are registered when INTEGRATION_TEST=true.

library;

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:everything_stack_template/services/llm_service.dart';
import 'package:everything_stack_template/services/tts_service.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/stt_service.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/adaptation_state_repository.dart';
import 'package:everything_stack_template/core/feedback_repository.dart';
import 'package:everything_stack_template/core/turn_repository.dart';
import 'package:everything_stack_template/domain/invocation.dart' as domain_invocation;
import 'package:everything_stack_template/domain/adaptation_state.dart';
import 'package:everything_stack_template/domain/feedback_correction.dart';
import 'package:everything_stack_template/domain/turn.dart';

/// Mock LLM Service for testing
class MockLLMServiceForTests implements LLMService {
  @override
  Future<void> initialize() async {
    debugPrint('🤖 [TEST] MockLLMService initialized');
  }

  @override
  Stream<String> chat({
    required List<Message> history,
    required String userMessage,
    String? systemPrompt,
    int? maxTokens,
  }) async* {
    yield 'Test response from mock LLM';
  }

  @override
  Future<LLMResponse> chatWithTools({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<LLMTool>? tools,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    debugPrint('🤖 [TEST] MockLLMService.chatWithTools called');
    return LLMResponse(
      id: 'test-llm-${DateTime.now().millisecondsSinceEpoch}',
      content: 'This is a test response from the mock LLM service.',
      toolCalls: [],
      tokensUsed: 42,
    );
  }

  @override
  void dispose() {
    debugPrint('🤖 [TEST] MockLLMService disposed');
  }

  @override
  bool get isReady => true;

  @override
  Future<String> recordInvocation(dynamic invocation) async => 'test-inv-id';

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {}

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async => {};

  @override
  Widget buildFeedbackUI(String invocationId) => const SizedBox();
}

/// Mock TTS Service for testing
class MockTTSServiceForTests implements TTSService {
  final List<String> synthesizedTexts = [];

  @override
  Future<void> initialize() async {
    debugPrint('🔊 [TEST] MockTTSService initialized');
  }

  @override
  Stream<Uint8List> synthesize(
    String text, {
    String? voice,
    String? languageCode,
  }) async* {
    debugPrint('🔊 [TEST] MockTTSService.synthesize: "$text"');
    synthesizedTexts.add(text);
    // Yield dummy audio bytes (MP3 header)
    yield Uint8List.fromList([0xFF, 0xFB, 0x10, 0x00]);
  }

  @override
  void dispose() {
    debugPrint('🔊 [TEST] MockTTSService disposed');
  }

  @override
  bool get isReady => true;

  @override
  Future<String> recordInvocation(dynamic invocation) async => 'test-inv-id';

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {}

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async => {};

  @override
  Widget buildFeedbackUI(String invocationId) => const SizedBox();
}

/// Mock Embedding Service for testing
class MockEmbeddingServiceForTests implements EmbeddingService {
  @override
  Future<void> initialize() async {
    debugPrint('📊 [TEST] MockEmbeddingService initialized');
  }

  @override
  Future<List<double>> generate(String text) async {
    debugPrint('📊 [TEST] MockEmbeddingService.generate called');
    // Return dummy 384-dim embedding
    return List.filled(384, 0.1);
  }

  @override
  Future<List<List<double>>> generateBatch(List<String> texts) async {
    debugPrint('📊 [TEST] MockEmbeddingService.generateBatch called');
    // Return dummy embeddings for each text
    return List.generate(texts.length, (_) => List.filled(384, 0.1));
  }
}

/// Mock STT Service for testing
class MockSTTServiceForTests extends STTService {
  final List<String> transcripts = [];
  bool _isReady = false;

  @override
  Future<void> initialize() async {
    debugPrint('🎤 [TEST] MockSTTService initialized');
    _isReady = true;
  }

  @override
  StreamSubscription<String> stream({
    required Stream<Uint8List> input,
    required void Function(String) onData,
    void Function()? onUtteranceEnd,
    required void Function(Object) onError,
    void Function()? onDone,
  }) {
    debugPrint('🎤 [TEST] MockSTTService.stream called');

    // Track audio received
    int totalBytes = 0;

    // Listen to audio stream and count bytes
    input.listen(
      (audioBytes) {
        totalBytes += audioBytes.length;
        debugPrint('🎤 [TEST] Received ${audioBytes.length} audio bytes (total: $totalBytes)');
      },
      onError: (e) => onError(STTException('Test error: $e')),
      onDone: () {
        debugPrint('🎤 [TEST] Audio stream done ($totalBytes bytes total)');
        onDone?.call();
      },
    );

    // Return a stream that yields test transcript after a short delay
    final controller = StreamController<String>();

    Future.delayed(const Duration(milliseconds: 500), () async {
      try {
        // Yield interim transcript
        const testTranscript = 'hello this is a test message';
        debugPrint('🎤 [TEST] Yielding test transcript: "$testTranscript"');
        controller.add(testTranscript);
        transcripts.add(testTranscript);
        onData(testTranscript);

        // Signal utterance end
        await Future.delayed(const Duration(milliseconds: 300));
        debugPrint('🎤 [TEST] Signaling utterance_end');
        onUtteranceEnd?.call();

        // Close stream after utterance
        await Future.delayed(const Duration(milliseconds: 100));
        controller.close();
      } catch (e) {
        debugPrint('🎤 [TEST] Error in mock stream: $e');
        onError(STTException('Mock error: $e'));
        controller.close();
      }
    });

    return controller.stream.listen(
      (text) => onData(text),
      onError: onError,
      onDone: onDone,
    );
  }

  @override
  void dispose() {
    debugPrint('🎤 [TEST] MockSTTService disposed');
  }

  @override
  bool get isReady => _isReady;

  @override
  Future<String> recordInvocation(dynamic invocation) async => 'test-stt-id';

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {}

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async =>
      {'status': 'baseline'};

  @override
  Widget buildFeedbackUI(String invocationId) => const SizedBox();
}

/// In-memory Invocation Repository for testing
class InMemoryInvocationRepository<T extends domain_invocation.Invocation>
    implements InvocationRepository<T> {
  final Map<String, T> _store = {};

  @override
  Future<void> create(T entity) async => _store[entity.id] = entity;

  @override
  Future<T?> read(String id) async => _store[id];

  @override
  Future<void> update(T entity) async => _store[entity.id] = entity;

  @override
  Future<void> delete(String id) async => _store.remove(id);

  @override
  Future<List<T>> readAll() async => _store.values.toList();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Stream<T?> watchEntity(String id) => Stream.value(_store[id]);

  @override
  Stream<List<T>> watchAll() => Stream.value(_store.values.toList());
}

/// In-memory Adaptation State Repository for testing
class InMemoryAdaptationStateRepository
    implements AdaptationStateRepository {
  final Map<String, AdaptationState> _store = {};

  @override
  Future<void> create(AdaptationState entity) async =>
      _store[entity.id] = entity;

  @override
  Future<AdaptationState?> read(String id) async => _store[id];

  @override
  Future<void> update(AdaptationState entity) async =>
      _store[entity.id] = entity;

  @override
  Future<void> delete(String id) async => _store.remove(id);

  @override
  Future<List<AdaptationState>> readAll() async => _store.values.toList();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Stream<AdaptationState?> watchEntity(String id) =>
      Stream.value(_store[id]);

  @override
  Stream<List<AdaptationState>> watchAll() =>
      Stream.value(_store.values.toList());
}

/// In-memory Feedback Repository for testing
class InMemoryFeedbackRepository implements FeedbackRepository {
  final Map<String, FeedbackCorrection> _store = {};

  @override
  Future<void> create(FeedbackCorrection entity) async =>
      _store[entity.id] = entity;

  @override
  Future<FeedbackCorrection?> read(String id) async => _store[id];

  @override
  Future<void> update(FeedbackCorrection entity) async =>
      _store[entity.id] = entity;

  @override
  Future<void> delete(String id) async => _store.remove(id);

  @override
  Future<List<FeedbackCorrection>> readAll() async => _store.values.toList();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Stream<FeedbackCorrection?> watchEntity(String id) =>
      Stream.value(_store[id]);

  @override
  Stream<List<FeedbackCorrection>> watchAll() =>
      Stream.value(_store.values.toList());
}

/// In-memory Turn Repository for testing
class InMemoryTurnRepository implements TurnRepository {
  final Map<String, Turn> _store = {};

  @override
  Future<void> create(Turn entity) async => _store[entity.id] = entity;

  @override
  Future<Turn?> read(String id) async => _store[id];

  @override
  Future<void> update(Turn entity) async => _store[entity.id] = entity;

  @override
  Future<void> delete(String id) async => _store.remove(id);

  @override
  Future<List<Turn>> readAll() async => _store.values.toList();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Stream<Turn?> watchEntity(String id) => Stream.value(_store[id]);

  @override
  Stream<List<Turn>> watchAll() => Stream.value(_store.values.toList());
}
