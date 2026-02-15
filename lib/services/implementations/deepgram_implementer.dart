import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:get_it/get_it.dart';

import 'stt_implementer.dart';
import '../types/stt_types.dart';
import '../types/word.dart';
import '../audio_storage.dart';

class DeepgramImplementer implements STTImplementer {
  final String apiKey;
  final String model;
  final String baseUrl;
  final Duration timeout;

  DeepgramImplementer({
    required this.apiKey,
    this.model = 'nova-2',
    this.baseUrl = 'https://api.deepgram.com/v1',
    this.timeout = const Duration(seconds: 30),
  });

  @override
  String get implementerName => 'deepgram';

  @override
  Set<String> get supportedPlatforms => {
        'android',
        'ios',
        'macos',
        'windows',
        'linux',
        'web',
        // Pure Dart HTTP - works everywhere
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
      // Time the API call
      final stopwatch = Stopwatch()..start();

      // Build request with audio data
      // audioId should be a file path or data URL
      final audioData = await _loadAudioData(audioId);

      final response = await http
          .post(
            Uri.parse('$baseUrl/listen?'
                'model=$model&'
                'encoding=linear16&'
                'sample_rate=16000&'
                'punctuate=true&' // Better punctuation for conversations
                'utterances=true&' // Detect natural speech utterances
                'smart_format=true' // Auto-format numbers, dates, etc
                ),
            headers: {
              'Authorization': 'Token $apiKey',
              'Content-Type': 'application/octet-stream',
            },
            body: audioData,
          )
          .timeout(timeout);

      stopwatch.stop();
      final latencyMs = stopwatch.elapsedMilliseconds.toDouble();

      // Handle response
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // Extract transcription and confidence
        final results = data['results'] as Map<String, dynamic>?;
        final channels = results?['channels'] as List?;

        if (channels != null && channels.isNotEmpty) {
          final firstChannel = channels.first as Map<String, dynamic>;
          final alternatives = firstChannel['alternatives'] as List?;

          if (alternatives != null && alternatives.isNotEmpty) {
            final firstAlt = alternatives.first as Map<String, dynamic>;
            final transcript = firstAlt['transcript'] as String? ?? '';
            final confidence =
                (firstAlt['confidence'] as num?)?.toDouble() ?? 0.5;
            final words = _extractWords(firstAlt);

            return STTInvocationOutput(
              transcription: transcript,
              confidence: confidence,
              words: words,
              latencyMs: latencyMs,
            );
          }
        }

        throw DeepgramException('No transcription in API response');
      } else if (response.statusCode == 401) {
        throw DeepgramException('Unauthorized: Invalid API key');
      } else if (response.statusCode >= 500 && response.statusCode < 600) {
        throw DeepgramException(
          'Server error ${response.statusCode}: ${response.body}',
        );
      } else {
        throw DeepgramException(
          'API error ${response.statusCode}: ${response.body}',
        );
      }
    } on TimeoutException {
      throw DeepgramException('Request timeout after ${timeout.inSeconds}s');
    } on DeepgramException {
      rethrow;
    } catch (e) {
      throw DeepgramException('Unexpected error: $e');
    }
  }

  @override
  Future<STTInvocationOutput> startLiveRecognition({
    required Stream<Uint8List> audioStream,
    required String eventId,
    double? eotThreshold,
    double? eagerEotThreshold,
    int? eotTimeoutMs,
    bool? enablePartialTranscripts,
    bool? enableEagerProcessing,
  }) {
    throw UnsupportedError(
        '$implementerName does not support live streaming. Use DeepgramFluxImplementer instead.');
  }

  /// Load audio data from audioId.
  /// Retrieves audio bytes from AudioStorage service.
  Future<List<int>> _loadAudioData(String audioId) async {
    try {
      final audioStorage = GetIt.instance<AudioStorage>();
      final audioBytes = await audioStorage.loadAudio(audioId);
      return audioBytes.toList();
    } catch (e) {
      throw DeepgramException(
          'Failed to load audio data for audioId=$audioId: $e');
    }
  }

  /// Extract Word objects from Deepgram response
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
}

// ============ Exceptions ============

class DeepgramException implements Exception {
  final String message;
  DeepgramException(this.message);

  @override
  String toString() => 'DeepgramException: $message';
}
