/// # DeepgramFluxImplementer
///
/// Real-time WebSocket STT using Deepgram Flux model.
/// Streams audio chunks and publishes partial transcripts via EventBus.
/// Handles turn detection (EndOfTurn, EagerEndOfTurn, TurnResumed).
///
/// ## Flow:
/// 1. Connect to wss://api.deepgram.com/v2/listen
/// 2. Load audio from AudioStorage
/// 3. Stream chunks (8KB each, 10ms throttle)
/// 4. Receive ListenV2TurnInfo → publish transcription_partial events
/// 5. Wait for EndOfTurn → return final STTInvocationOutput
///
/// ## Events Published:
/// - transcription_partial: Interim transcripts while processing
/// - transcription_eager (optional): EagerEndOfTurn events if enabled

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:universal_io/io.dart';  // Pure Dart WebSocket (fixes Flutter Windows bug)
import 'package:get_it/get_it.dart';

import 'stt_implementer.dart';
import '../types/stt_types.dart';
import '../types/word.dart';
import '../audio_storage.dart';
import '../event_bus.dart';
import '../../core/event.dart';

class DeepgramFluxImplementer implements STTImplementer {
  final String apiKey;
  final String model;
  final String baseUrl;
  final Duration timeout;

  // WebSocket connection (reused across recognitions if possible)
  WebSocket? _wsChannel;
  Timer? _keepAliveTimer;
  StreamSubscription? _wsSubscription;

  // Current recognition state
  Completer<STTInvocationOutput>? _recognitionCompleter;
  final List<String> _partialTranscripts = [];
  final List<double> _partialConfidences = [];
  final List<Word> _allWords = [];
  DateTime? _firstByteTime;
  String? _currentEventId;
  bool _enablePartialTranscripts = true;
  bool _enableEagerProcessing = false;

  DeepgramFluxImplementer({
    required this.apiKey,
    this.model = 'flux-general-en',
    this.baseUrl = 'wss://api.deepgram.com',
    this.timeout = const Duration(seconds: 30),
  });

  @override
  String get implementerName => 'deepgram_flux';

  @override
  Future<STTInvocationOutput> recognize({
    required String audioId,
    required double durationSeconds,
    String? eventId,
    double? eotThreshold,
    double? eagerEotThreshold,
    int? eotTimeoutMs,
    bool? enablePartialTranscripts,
    bool? enableEagerProcessing,
  }) async {
    try {
      // Store eventId and flags for event publishing
      _currentEventId = eventId;
      _enablePartialTranscripts = enablePartialTranscripts ?? true;
      _enableEagerProcessing = enableEagerProcessing ?? false;

      // Reset state
      _partialTranscripts.clear();
      _partialConfidences.clear();
      _allWords.clear();
      _firstByteTime = null;
      _recognitionCompleter = Completer<STTInvocationOutput>();

      // Load audio data from AudioStorage
      final audioData = await _loadAudioData(audioId);

      // Connect WebSocket with adaptation parameters
      await _ensureWebSocketConnected(
        eotThreshold: eotThreshold ?? 0.7,
        eagerEotThreshold: eagerEotThreshold,
        eotTimeoutMs: eotTimeoutMs,
      );

      // Start streaming audio chunks
      _firstByteTime = DateTime.now();
      await _streamAudioChunks(audioData);

      // Wait for EndOfTurn event (handled in _setupMessageHandler)
      if (_recognitionCompleter == null) {
        throw DeepgramException('Recognition completer not initialized (WebSocket connection may have failed)');
      }

      final result = await _recognitionCompleter!.future
          .timeout(timeout, onTimeout: () {
        throw DeepgramException('Recognition timeout after ${timeout.inSeconds}s');
      });

      return result;
    } on DeepgramException {
      rethrow;
    } catch (e) {
      throw DeepgramException('Unexpected error: $e');
    }
  }

  /// Load audio data from AudioStorage service.
  Future<Uint8List> _loadAudioData(String audioId) async {
    try {
      final audioStorage = GetIt.instance<AudioStorage>();
      final audioBytes = await audioStorage.loadAudio(audioId);
      return audioBytes;
    } catch (e) {
      throw DeepgramException('Failed to load audio data for audioId=$audioId: $e');
    }
  }

  /// Ensure WebSocket connection is established.
  Future<void> _ensureWebSocketConnected({
    required double eotThreshold,
    double? eagerEotThreshold,
    int? eotTimeoutMs,
  }) async {
    if (_wsChannel != null) {
      // Reuse existing connection
      return;
    }

    try {
      // Build WebSocket URL with Flux parameters (NO token in query params)
      // Auth uses Sec-WebSocket-Protocol header instead (Flutter security requirement)
      final queryParts = [
        'model=$model',
        'encoding=linear16',
        'sample_rate=16000',
        'punctuate=true',
        'utterances=true',
        'smart_format=true',
        'interim_results=true',
        'eot_threshold=${eotThreshold.toString()}',
      ];

      // Optional parameters (only add if set)
      if (eagerEotThreshold != null) {
        queryParts.add('eager_eot_threshold=${eagerEotThreshold.toString()}');
      }
      if (eotTimeoutMs != null) {
        queryParts.add('eot_timeout_ms=${eotTimeoutMs.toString()}');
      }

      final queryString = queryParts.join('&');
      final wsUrl = '$baseUrl/v2/listen?$queryString';

      print('🔗 [DeepgramFluxImplementer] Connecting to: $wsUrl');

      // Use dart:io WebSocket with Authorization header
      _wsChannel = await WebSocket.connect(
        wsUrl,
        headers: {
          'Authorization': 'Token $apiKey',  // Deepgram token format
        },
      );

      // Setup message handler
      _setupMessageHandler();

      // Start keep-alive ping (every 5 seconds)
      _keepAliveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_wsChannel != null) {
          _wsChannel!.add(jsonEncode({'type': 'KeepAlive'}));
        }
      });

      print('✅ [DeepgramFluxImplementer] WebSocket connected: $model');
    } catch (e) {
      throw DeepgramException('Failed to connect WebSocket: $e');
    }
  }

  /// Setup WebSocket message handler.
  void _setupMessageHandler() {
    _wsSubscription = _wsChannel!.listen(
      (message) {
        try {
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          final type = data['type'] as String?;

          if (type == 'Results') {
            _handleListenV2TurnInfo(data);
          } else if (type == 'Metadata') {
            // Ignore metadata for now
          } else if (type == 'UtteranceEnd') {
            // This is EndOfTurn - finalize recognition
            _handleEndOfTurn();
          } else {
            print('🔍 [DeepgramFluxImplementer] Unknown message type: $type');
          }
        } catch (e) {
          print('⚠️ [DeepgramFluxImplementer] Error parsing message: $e');
        }
      },
      onError: (error) {
        print('❌ [DeepgramFluxImplementer] WebSocket error: $error');
        if (_recognitionCompleter != null && !_recognitionCompleter!.isCompleted) {
          _recognitionCompleter!.completeError(DeepgramException('WebSocket error: $error'));
        }
      },
      onDone: () {
        print('🔌 [DeepgramFluxImplementer] WebSocket closed');
        _wsChannel = null;
        _keepAliveTimer?.cancel();
      },
      cancelOnError: false,
    );
  }

  /// Handle ListenV2TurnInfo message (partial transcript).
  void _handleListenV2TurnInfo(Map<String, dynamic> data) {
    final channel = data['channel'] as Map<String, dynamic>?;
    if (channel == null) return;

    final alternatives = channel['alternatives'] as List?;
    if (alternatives == null || alternatives.isEmpty) return;

    final firstAlt = alternatives.first as Map<String, dynamic>;
    final transcript = firstAlt['transcript'] as String? ?? '';
    final confidence = (firstAlt['confidence'] as num?)?.toDouble() ?? 0.0;
    final isFinal = data['is_final'] as bool? ?? false;

    if (transcript.isEmpty) return;

    // Store partial results
    _partialTranscripts.add(transcript);
    _partialConfidences.add(confidence);

    // Extract words
    final words = _extractWords(firstAlt);
    _allWords.addAll(words);

    // Publish transcription_partial event for UI (if enabled)
    if (_enablePartialTranscripts) {
      final eventBus = GetIt.instance<EventBus>();
      eventBus.publish(Event(
        eventType: 'transcription_partial',
        correlationId: _currentEventId ?? 'unknown',
        source: 'stt',
        payloadJson: jsonEncode({
          'transcript': transcript,
          'confidence': confidence,
          'is_final': isFinal,
        }),
      ));

      print('📝 [DeepgramFluxImplementer] Partial: "$transcript" (confidence: ${confidence.toStringAsFixed(2)})');
    }
  }

  /// Handle EndOfTurn event (final transcript).
  void _handleEndOfTurn() {
    if (_recognitionCompleter == null || _recognitionCompleter!.isCompleted) {
      return;
    }

    // Calculate final transcript (last partial is usually the most complete)
    final finalTranscript = _partialTranscripts.isNotEmpty
        ? _partialTranscripts.last
        : '';

    // Calculate average confidence
    final avgConfidence = _partialConfidences.isNotEmpty
        ? _partialConfidences.reduce((a, b) => a + b) / _partialConfidences.length
        : 0.0;

    // Calculate latency
    final latencyMs = _firstByteTime != null
        ? DateTime.now().difference(_firstByteTime!).inMilliseconds.toDouble()
        : 0.0;

    print('✅ [DeepgramFluxImplementer] EndOfTurn: "$finalTranscript" (latency: ${latencyMs.toStringAsFixed(0)}ms)');

    _recognitionCompleter!.complete(STTInvocationOutput(
      transcription: finalTranscript,
      confidence: avgConfidence,
      words: _allWords,
      latencyMs: latencyMs,
    ));
  }

  /// Stream audio chunks to WebSocket (8KB chunks, 10ms throttle).
  Future<void> _streamAudioChunks(Uint8List audioData) async {
    const chunkSize = 8192; // 8KB chunks
    const throttleMs = 10;   // 10ms between chunks

    for (int i = 0; i < audioData.length; i += chunkSize) {
      final end = (i + chunkSize < audioData.length) ? i + chunkSize : audioData.length;
      final chunk = audioData.sublist(i, end);

      // Send chunk to WebSocket
      _wsChannel!.add(chunk);

      // Throttle to prevent overwhelming WebSocket
      if (end < audioData.length) {
        await Future.delayed(const Duration(milliseconds: throttleMs));
      }
    }

    // Send CloseStream message to signal end of audio
    _wsChannel!.add(jsonEncode({'type': 'CloseStream'}));
    print('📤 [DeepgramFluxImplementer] Finished streaming ${audioData.length} bytes');
  }

  /// Extract Word objects from Deepgram response.
  List<Word> _extractWords(Map<String, dynamic> alternative) {
    final wordsList = <Word>[];
    final words = alternative['words'] as List? ?? [];

    for (final wordJson in words) {
      if (wordJson is Map<String, dynamic>) {
        final word = Word(
          text: wordJson['word'] as String? ?? '',
          confidence: (wordJson['confidence'] as num?)?.toDouble() ?? 0.0,
          startTime: (wordJson['start'] as num?)?.toDouble() ?? 0.0,
          endTime: (wordJson['end'] as num?)?.toDouble() ?? 0.0,
        );
        wordsList.add(word);
      }
    }

    return wordsList;
  }

  /// Dispose resources.
  void dispose() {
    _keepAliveTimer?.cancel();
    _wsSubscription?.cancel();
    _wsChannel?.close();
    _wsChannel = null;
  }
}

// ============ Exceptions ============

class DeepgramException implements Exception {
  final String message;
  DeepgramException(this.message);

  @override
  String toString() => 'DeepgramException: $message';
}
