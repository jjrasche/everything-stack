/// ## Why IO layer for Windows?
/// dart:io WebSocket has a known bug on Windows. IO layer works around it
/// by using browser WebSocket internally on that platform.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:get_it/get_it.dart';

import 'stt_implementer.dart';
import '../types/stt_types.dart';
import '../types/word.dart';
import '../audio_storage.dart';
import '../event_bus.dart';
import '../../core/event.dart';
import '../../io/io.dart';

class DeepgramFluxImplementer implements STTImplementer {
  final String apiKey;
  final String model;
  final String baseUrl;
  final Duration timeout;

  // Nerve components (reused across recognitions if possible)
  Transport? _transport;
  Protocol? _protocol;
  Channel? _channel;
  Timer? _keepAliveTimer;
  StreamSubscription<Message>? _messageSubscription;

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

  /// Start live recognition by streaming audio chunks as they arrive.
  ///
  /// This is for real-time streaming mode where audio is sent to Deepgram
  /// as it's being recorded, not after recording completes.
  ///
  /// Flow:
  /// 1. Connect to Deepgram immediately
  /// 2. Listen to audioStream and forward each chunk to Deepgram
  /// 3. Receive partial transcripts in real-time
  /// 4. When Deepgram sends EndOfTurn → publish end_of_turn event → auto-stop
  /// 5. Return final transcription
  ///
  /// The key difference from batch recognize():
  /// - Batch: record → save → connect → send all → wait
  /// - Live: connect → record + send each chunk → EndOfTurn → auto-stop
  Future<STTInvocationOutput> startLiveRecognition({
    required Stream<Uint8List> audioStream,
    required String eventId,
    double? eotThreshold,
    double? eagerEotThreshold,
    int? eotTimeoutMs,
    bool? enablePartialTranscripts,
    bool? enableEagerProcessing,
  }) async {
    try {
      _currentEventId = eventId;
      _enablePartialTranscripts = enablePartialTranscripts ?? true;
      _enableEagerProcessing = enableEagerProcessing ?? false;

      _partialTranscripts.clear();
      _partialConfidences.clear();
      _allWords.clear();
      _firstByteTime = null;
      _recognitionCompleter = Completer<STTInvocationOutput>();

      // Connect BEFORE streaming starts so no audio is lost
      await _ensureWebSocketConnected(
        eotThreshold: eotThreshold ?? 0.7,
        eagerEotThreshold: eagerEotThreshold,
        eotTimeoutMs: eotTimeoutMs,
      );

      _firstByteTime = DateTime.now();
      _streamLiveAudioChunks(audioStream);

      // Wait for EndOfTurn event (handled in _setupMessageHandler)
      if (_recognitionCompleter == null) {
        throw DeepgramException(
            'Recognition completer not initialized (WebSocket connection may have failed)');
      }

      final result =
          await _recognitionCompleter!.future.timeout(timeout, onTimeout: () {
        throw DeepgramException(
            'Recognition timeout after ${timeout.inSeconds}s');
      });

      return result;
    } on DeepgramException {
      rethrow;
    } catch (e) {
      throw DeepgramException('Unexpected error: $e');
    }
  }

  @override
  String get implementerName => 'deepgram_flux';

  @override
  Set<String> get supportedPlatforms => {
        'android',
        'ios',
        'macos',
        'windows',
        'linux',
        'web',
        // Pure Dart WebSocket via universal_io - works everywhere
      };

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
      _currentEventId = eventId;
      _enablePartialTranscripts = enablePartialTranscripts ?? true;
      _enableEagerProcessing = enableEagerProcessing ?? false;

      _partialTranscripts.clear();
      _partialConfidences.clear();
      _allWords.clear();
      _firstByteTime = null;
      _recognitionCompleter = Completer<STTInvocationOutput>();

      final audioData = await _loadAudioData(audioId);

      await _ensureWebSocketConnected(
        eotThreshold: eotThreshold ?? 0.7,
        eagerEotThreshold: eagerEotThreshold,
        eotTimeoutMs: eotTimeoutMs,
      );

      _firstByteTime = DateTime.now();
      await _streamAudioChunks(audioData);

      // Wait for EndOfTurn event (handled in _setupMessageHandler)
      if (_recognitionCompleter == null) {
        throw DeepgramException(
            'Recognition completer not initialized (WebSocket connection may have failed)');
      }

      final result =
          await _recognitionCompleter!.future.timeout(timeout, onTimeout: () {
        throw DeepgramException(
            'Recognition timeout after ${timeout.inSeconds}s');
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
      throw DeepgramException(
          'Failed to load audio data for audioId=$audioId: $e');
    }
  }

  /// Ensure Nerve Channel connection is established.
  Future<void> _ensureWebSocketConnected({
    required double eotThreshold,
    double? eagerEotThreshold,
    int? eotTimeoutMs,
  }) async {
    if (_channel != null && _channel!.state == ChannelState.connected) {
      return;
    }

    try {
      // NOTE: Flux only supports model, encoding, sample_rate, eot_* params
      // DO NOT use punctuate/utterances/smart_format/interim_results (Nova params)
      final queryParams = {
        'model': model,
        'encoding': 'linear16',
        'sample_rate': '16000',
        'eot_threshold': eotThreshold.toString(),
      };

      if (eagerEotThreshold != null) {
        queryParams['eager_eot_threshold'] = eagerEotThreshold.toString();
      }
      if (eotTimeoutMs != null) {
        queryParams['eot_timeout_ms'] = eotTimeoutMs.toString();
      }

      // Deepgram authentication: protocols = ["token", "API_KEY"]
      // This sets Sec-WebSocket-Protocol header during handshake
      final transportConfig = TransportConfig(
        host: 'api.deepgram.com',
        port: 443,
        useTls: true,
        path: '/v2/listen', // v2 REQUIRED for flux model
        queryParams: queryParams,
        subprotocols: ['token', apiKey], // Deepgram auth: "token, API_KEY"
        connectTimeout: const Duration(seconds: 10),
      );

      print('🔗 [DeepgramFluxImplementer] Connecting via Nerve Channel...');
      print('   URL: ${transportConfig.url.replaceAll(apiKey, '***')}');

      final factory = createTransportFactory();
      _transport = factory.create(transportConfig);
      _protocol = WebSocketProtocol(transport: _transport!);
      _channel = ChannelImpl(
        config: ChannelConfig(
          endpoint: transportConfig.url,
          retryPolicy: RetryPolicy(
            maxAttempts: 3,
            initialDelay: const Duration(milliseconds: 500),
          ),
        ),
        protocol: _protocol!,
      );

      await _channel!.connect();

      _setupMessageHandler();

      _keepAliveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_channel?.state == ChannelState.connected) {
          _channel!.sendText(jsonEncode({'type': 'KeepAlive'}));
        }
      });

      print('✅ [DeepgramFluxImplementer] Connected via Nerve Channel');
    } catch (e) {
      throw DeepgramException('Failed to connect: $e');
    }
  }

  /// Setup message handler for Nerve Channel.
  void _setupMessageHandler() {
    _messageSubscription = _channel!.messages.listen(
      (message) {
        if (message is TextMessage) {
          _handleTextMessage(message.text);
        }
        // Binary messages from Deepgram are not expected
      },
      onError: (error) {
        print('❌ [DeepgramFluxImplementer] Channel error: $error');
        if (_recognitionCompleter != null &&
            !_recognitionCompleter!.isCompleted) {
          _recognitionCompleter!
              .completeError(DeepgramException('Channel error: $error'));
        }
      },
      onDone: () {
        print('🔌 [DeepgramFluxImplementer] Channel closed');
      },
    );
  }

  /// Handle incoming text message from Deepgram Flux v2 API.
  void _handleTextMessage(String text) {
    try {
      print(
          '📨 [DeepgramFluxImplementer] Received message: ${text.substring(0, text.length > 200 ? 200 : text.length)}...');

      final data = jsonDecode(text) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'Connected') {
        // Flux v2: Connection confirmation
        print(
            '✅ [DeepgramFluxImplementer] Deepgram connected: ${data['request_id']}');
      } else if (type == 'TurnInfo') {
        // Flux v2: Transcription update with event type
        print('📝 [DeepgramFluxImplementer] TurnInfo received (processing...)');
        _handleFluxTurnInfo(data);
      } else if (type == 'Error') {
        // Flux v2: Fatal error
        print(
            '❌ [DeepgramFluxImplementer] Deepgram error: ${data['description']}');
      } else {
        print('🔍 [DeepgramFluxImplementer] Unknown message type: $type');
      }
    } catch (e) {
      print('⚠️ [DeepgramFluxImplementer] Error parsing message: $e');
      print('   Raw message: $text');
    }
  }

  /// Handle Flux v2 TurnInfo message (transcription with event type).
  void _handleFluxTurnInfo(Map<String, dynamic> data) {
    final event = data['event'] as String?;
    final transcript = data['transcript'] as String? ?? '';
    final endOfTurnConfidence =
        (data['end_of_turn_confidence'] as num?)?.toDouble() ?? 0.0;

    // NOTE: Don't return early on empty transcript - EndOfTurn events may have
    // empty transcript when final text was sent in previous Update message.
    if (transcript.isNotEmpty) {
      _partialTranscripts.add(transcript);
      _partialConfidences.add(endOfTurnConfidence);
    }

    final wordsJson = data['words'] as List?;
    if (wordsJson != null) {
      final words = _extractFluxWords(wordsJson);
      _allWords.addAll(words);
    }

    if (event == 'EndOfTurn') {
      _handleEndOfTurn(); // Fire-and-forget (async, but we don't block here)
    } else if (event == 'EagerEndOfTurn' && _enableEagerProcessing) {
      print('⚡ [DeepgramFluxImplementer] EagerEndOfTurn: "$transcript"');
    } else if (event == 'StartOfTurn') {
      // Critical for barge-in detection
      final eventBus = GetIt.instance<EventBus>();
      eventBus.publish(Event(
        eventType: 'start_of_turn',
        correlationId: _currentEventId ?? 'unknown',
        source: 'stt',
        payloadJson: jsonEncode({
          'transcript': transcript,
          'confidence': endOfTurnConfidence,
        }),
      ));
      print(
          '🎙️ [DeepgramFluxImplementer] StartOfTurn detected (BARGE-IN signal)');

      if (_enablePartialTranscripts) {
        eventBus.publish(Event(
          eventType: 'transcription_partial',
          correlationId: _currentEventId ?? 'unknown',
          source: 'stt',
          payloadJson: jsonEncode({
            'transcript': transcript,
            'confidence': endOfTurnConfidence,
            'event': event,
          }),
        ));
      }
    } else if (event == 'Update' || event == 'TurnResumed') {
      if (_enablePartialTranscripts) {
        final eventBus = GetIt.instance<EventBus>();
        // Fire-and-forget for partial transcripts (don't block message handling)
        eventBus.publish(Event(
          eventType: 'transcription_partial',
          correlationId: _currentEventId ?? 'unknown',
          source: 'stt',
          payloadJson: jsonEncode({
            'transcript': transcript,
            'confidence': endOfTurnConfidence,
            'event': event,
          }),
        ));

        print(
            '📝 [DeepgramFluxImplementer] $event: "$transcript" (confidence: ${endOfTurnConfidence.toStringAsFixed(2)})');
      }
    }
  }

  /// Handle EndOfTurn event (final transcript).
  Future<void> _handleEndOfTurn() async {
    if (_recognitionCompleter == null || _recognitionCompleter!.isCompleted) {
      return;
    }

    final finalTranscript =
        _partialTranscripts.isNotEmpty ? _partialTranscripts.last : '';

    final avgConfidence = _partialConfidences.isNotEmpty
        ? _partialConfidences.reduce((a, b) => a + b) /
            _partialConfidences.length
        : 0.0;

    final latencyMs = _firstByteTime != null
        ? DateTime.now().difference(_firstByteTime!).inMilliseconds.toDouble()
        : 0.0;

    print(
        '✅ [DeepgramFluxImplementer] EndOfTurn: "$finalTranscript" (latency: ${latencyMs.toStringAsFixed(0)}ms)');

    // Voice screen auto-stops when it receives this event
    final eventBus = GetIt.instance<EventBus>();
    await eventBus.publish(Event(
      eventType: 'end_of_turn',
      correlationId: _currentEventId ?? 'unknown',
      source: 'stt',
      payloadJson: jsonEncode({
        'transcript': finalTranscript,
        'confidence': avgConfidence,
        'latency_ms': latencyMs,
      }),
    ));
    print('📡 [DeepgramFluxImplementer] Published end_of_turn event');

    _recognitionCompleter!.complete(STTInvocationOutput(
      transcription: finalTranscript,
      confidence: avgConfidence,
      words: _allWords,
      latencyMs: latencyMs,
    ));
  }

  /// Stream audio chunks via Nerve Channel (8KB chunks, 10ms throttle).
  /// Used for batch mode (saved audio from AudioStorage).
  Future<void> _streamAudioChunks(Uint8List audioData) async {
    const chunkSize = 8192; // 8KB chunks
    const throttleMs = 10; // 10ms between chunks

    for (int i = 0; i < audioData.length; i += chunkSize) {
      final end =
          (i + chunkSize < audioData.length) ? i + chunkSize : audioData.length;
      final chunk = Uint8List.sublistView(audioData, i, end);

      await _channel!.sendBinary(chunk);

      // Throttle to prevent overwhelming the WebSocket
      if (end < audioData.length) {
        await Future.delayed(const Duration(milliseconds: throttleMs));
      }
    }

    // Signal end of audio to Deepgram
    await _channel!.sendText(jsonEncode({'type': 'CloseStream'}));
    print(
        '📤 [DeepgramFluxImplementer] Finished streaming ${audioData.length} bytes');
  }

  /// Stream live audio chunks as they arrive from microphone.
  /// Used for live streaming mode (audio sent in real-time).
  ///
  /// NOTE: Does NOT send CloseStream - EndOfTurn will be detected by Deepgram
  /// based on silence/eot_threshold. Voice screen will auto-stop when EndOfTurn received.
  void _streamLiveAudioChunks(Stream<Uint8List> audioStream) {
    int totalBytes = 0;
    int chunkCount = 0;

    print(
        '🎙️ [DeepgramFluxImplementer] Starting to listen to audio stream...');

    audioStream.listen(
      (chunk) {
        _channel?.sendBinary(chunk);
        totalBytes += chunk.length;
        chunkCount++;

        if (chunkCount <= 3 || chunkCount % 50 == 0) {
          print(
              '📤 [DeepgramFluxImplementer] Sent chunk #$chunkCount: ${chunk.length} bytes (total: $totalBytes bytes)');
        }
      },
      onError: (error) {
        print('❌ [DeepgramFluxImplementer] Audio stream error: $error');
        if (_recognitionCompleter != null &&
            !_recognitionCompleter!.isCompleted) {
          _recognitionCompleter!
              .completeError(DeepgramException('Audio stream error: $error'));
        }
      },
      onDone: () {
        print(
            '📤 [DeepgramFluxImplementer] Audio stream ended: $totalBytes bytes streamed ($chunkCount chunks)');
        _channel?.sendText(jsonEncode({'type': 'CloseStream'}));
      },
      cancelOnError: true,
    );
  }

  /// Extract Word objects from Flux v2 TurnInfo response.
  /// Note: Flux v2 doesn't include start/end timestamps for individual words.
  List<Word> _extractFluxWords(List wordsJson) {
    final wordsList = <Word>[];

    for (final wordJson in wordsJson) {
      if (wordJson is Map<String, dynamic>) {
        final word = Word(
          text: wordJson['word'] as String? ?? '',
          confidence: (wordJson['confidence'] as num?)?.toDouble() ?? 0.0,
          startTime: 0.0, // Flux v2 doesn't provide word-level timestamps
          endTime: 0.0,
        );
        wordsList.add(word);
      }
    }

    return wordsList;
  }

  /// Dispose resources.
  void dispose() {
    _keepAliveTimer?.cancel();
    _messageSubscription?.cancel();
    _channel?.dispose();
    _protocol?.dispose();
    _transport?.dispose();
    _transport = null;
    _protocol = null;
    _channel = null;
  }
}

// ============ Exceptions ============

class DeepgramException implements Exception {
  final String message;
  DeepgramException(this.message);

  @override
  String toString() => 'DeepgramException: $message';
}
