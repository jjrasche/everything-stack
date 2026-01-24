/// # DeepgramNerveImplementer
///
/// Real-time WebSocket STT using Deepgram Flux model via Nerve Channel.
/// This is the migration of DeepgramFluxImplementer to use the Nerve system
/// for cross-platform WebSocket support.
///
/// ## Platform Support
/// - Web: Browser WebSocket (works)
/// - macOS/iOS/Android/Linux: dart:io WebSocket (works)
/// - Windows: dart:io WebSocket (BROKEN - use web platform)
///
/// ## Flow:
/// 1. Connect via Nerve Channel (Transport → Protocol → Channel)
/// 2. Load audio from AudioStorage
/// 3. Stream chunks (8KB each, 10ms throttle)
/// 4. Receive transcripts → publish transcription_partial events
/// 5. Wait for EndOfTurn → return final STTInvocationOutput
///
/// ## Events Published:
/// - transcription_partial: Interim transcripts while processing

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
import '../../nerve/nerve.dart';

class DeepgramNerveImplementer implements STTImplementer {
  final String apiKey;
  final String model;
  final String baseUrl;
  final Duration timeout;

  // Nerve components
  Transport? _transport;
  Protocol? _protocol;
  Channel? _channel;
  Timer? _keepAliveTimer;

  // Current recognition state
  Completer<STTInvocationOutput>? _recognitionCompleter;
  final List<String> _partialTranscripts = [];
  final List<double> _partialConfidences = [];
  final List<Word> _allWords = [];
  DateTime? _firstByteTime;
  String? _currentEventId;
  bool _enablePartialTranscripts = true;
  bool _enableEagerProcessing = false;

  StreamSubscription<Message>? _messageSubscription;

  DeepgramNerveImplementer({
    required this.apiKey,
    this.model = 'flux-general-en',
    this.baseUrl = 'wss://api.deepgram.com',
    this.timeout = const Duration(seconds: 30),
  });

  @override
  String get implementerName => 'deepgram_nerve';

  @override
  Set<String> get supportedPlatforms => {
        'android',
        'ios',
        'macos',
        'linux',
        'web',
        // Windows is technically supported but dart:io WebSocket is broken.
        // Web platform works on Windows via browser WebSocket.
        // Native Windows support requires Rust FFI (Phase 2).
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

      // Connect via Nerve Channel
      await _ensureConnected(
        eotThreshold: eotThreshold ?? 0.7,
        eagerEotThreshold: eagerEotThreshold,
        eotTimeoutMs: eotTimeoutMs,
      );

      // Start streaming audio chunks
      _firstByteTime = DateTime.now();
      await _streamAudioChunks(audioData);

      // Wait for EndOfTurn event
      if (_recognitionCompleter == null) {
        throw DeepgramNerveException(
          'Recognition completer not initialized (connection may have failed)',
        );
      }

      final result = await _recognitionCompleter!.future
          .timeout(timeout, onTimeout: () {
        throw DeepgramNerveException(
          'Recognition timeout after ${timeout.inSeconds}s',
        );
      });

      return result;
    } on DeepgramNerveException {
      rethrow;
    } catch (e) {
      throw DeepgramNerveException('Unexpected error: $e');
    }
  }

  /// Load audio data from AudioStorage service.
  Future<Uint8List> _loadAudioData(String audioId) async {
    try {
      final audioStorage = GetIt.instance<AudioStorage>();
      final audioBytes = await audioStorage.loadAudio(audioId);
      return audioBytes;
    } catch (e) {
      throw DeepgramNerveException(
        'Failed to load audio data for audioId=$audioId: $e',
      );
    }
  }

  /// Ensure Nerve Channel connection is established.
  Future<void> _ensureConnected({
    required double eotThreshold,
    double? eagerEotThreshold,
    int? eotTimeoutMs,
  }) async {
    if (_channel != null && _channel!.state == ChannelState.connected) {
      return; // Reuse existing connection
    }

    try {
      // Build query parameters
      final queryParams = {
        'model': model,
        'encoding': 'linear16',
        'sample_rate': '16000',
        'punctuate': 'true',
        'utterances': 'true',
        'smart_format': 'true',
        'interim_results': 'true',
        'eot_threshold': eotThreshold.toString(),
        'token': apiKey, // Deepgram accepts token in URL
      };

      if (eagerEotThreshold != null) {
        queryParams['eager_eot_threshold'] = eagerEotThreshold.toString();
      }
      if (eotTimeoutMs != null) {
        queryParams['eot_timeout_ms'] = eotTimeoutMs.toString();
      }

      // Create Transport config
      final transportConfig = TransportConfig(
        host: 'api.deepgram.com',
        port: 443,
        useTls: true,
        path: '/v2/listen',
        queryParams: queryParams,
        connectTimeout: const Duration(seconds: 10),
      );

      print('🔗 [DeepgramNerveImplementer] Connecting via Nerve Channel...');
      print('   URL: ${transportConfig.url.replaceAll(apiKey, '***')}');

      // Create Nerve stack
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

      // Connect
      await _channel!.connect();

      // Setup message handler
      _setupMessageHandler();

      // Start keep-alive ping (every 5 seconds)
      // Keepalive is application-specific, not handled by Channel layer
      _keepAliveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_channel?.state == ChannelState.connected) {
          _channel!.sendText(jsonEncode({'type': 'KeepAlive'}));
        }
      });

      print('✅ [DeepgramNerveImplementer] Connected via Nerve Channel');
    } catch (e) {
      throw DeepgramNerveException('Failed to connect: $e');
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
        print('❌ [DeepgramNerveImplementer] Channel error: $error');
        if (_recognitionCompleter != null &&
            !_recognitionCompleter!.isCompleted) {
          _recognitionCompleter!
              .completeError(DeepgramNerveException('Channel error: $error'));
        }
      },
      onDone: () {
        print('🔌 [DeepgramNerveImplementer] Channel closed');
      },
    );
  }

  /// Handle incoming text message from Deepgram.
  void _handleTextMessage(String text) {
    try {
      final data = jsonDecode(text) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'Results') {
        _handleListenV2TurnInfo(data);
      } else if (type == 'Metadata') {
        // Ignore metadata for now
      } else if (type == 'UtteranceEnd') {
        // This is EndOfTurn - finalize recognition
        _handleEndOfTurn();
      } else {
        print('🔍 [DeepgramNerveImplementer] Unknown message type: $type');
      }
    } catch (e) {
      print('⚠️ [DeepgramNerveImplementer] Error parsing message: $e');
    }
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

      print(
        '📝 [DeepgramNerveImplementer] Partial: "$transcript" '
        '(confidence: ${confidence.toStringAsFixed(2)})',
      );
    }
  }

  /// Handle EndOfTurn event (final transcript).
  void _handleEndOfTurn() {
    if (_recognitionCompleter == null || _recognitionCompleter!.isCompleted) {
      return;
    }

    // Calculate final transcript (last partial is usually the most complete)
    final finalTranscript =
        _partialTranscripts.isNotEmpty ? _partialTranscripts.last : '';

    // Calculate average confidence
    final avgConfidence = _partialConfidences.isNotEmpty
        ? _partialConfidences.reduce((a, b) => a + b) / _partialConfidences.length
        : 0.0;

    // Calculate latency
    final latencyMs = _firstByteTime != null
        ? DateTime.now().difference(_firstByteTime!).inMilliseconds.toDouble()
        : 0.0;

    print(
      '✅ [DeepgramNerveImplementer] EndOfTurn: "$finalTranscript" '
      '(latency: ${latencyMs.toStringAsFixed(0)}ms)',
    );

    _recognitionCompleter!.complete(STTInvocationOutput(
      transcription: finalTranscript,
      confidence: avgConfidence,
      words: _allWords,
      latencyMs: latencyMs,
    ));
  }

  /// Stream audio chunks via Nerve Channel (8KB chunks, 10ms throttle).
  Future<void> _streamAudioChunks(Uint8List audioData) async {
    const chunkSize = 8192; // 8KB chunks
    const throttleMs = 10; // 10ms between chunks

    for (int i = 0; i < audioData.length; i += chunkSize) {
      final end =
          (i + chunkSize < audioData.length) ? i + chunkSize : audioData.length;
      final chunk = Uint8List.sublistView(audioData, i, end);

      // Send binary chunk via Channel
      await _channel!.sendBinary(chunk);

      // Throttle to prevent overwhelming
      if (end < audioData.length) {
        await Future.delayed(const Duration(milliseconds: throttleMs));
      }
    }

    // Send CloseStream message to signal end of audio
    await _channel!.sendText(jsonEncode({'type': 'CloseStream'}));
    print(
      '📤 [DeepgramNerveImplementer] Finished streaming ${audioData.length} bytes',
    );
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

class DeepgramNerveException implements Exception {
  final String message;
  DeepgramNerveException(this.message);

  @override
  String toString() => 'DeepgramNerveException: $message';
}
