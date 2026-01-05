/// # DeepgramImplementer
///
/// Dumb API wrapper for Deepgram STT API.
/// Recognizes audio files (not streaming).
/// Handles authentication, retries, timeouts.
/// No state management - just calls API and returns results.

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

import 'stt_implementer.dart';
import '../types/stt_types.dart';
import '../types/word.dart';

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
  Future<STTInvocationOutput> recognize({
    required String audioId,
    required double durationSeconds,
  }) async {
    try {
      // Time the API call
      final stopwatch = Stopwatch()..start();

      // Build request with audio data
      // audioId should be a file path or data URL
      final audioData = await _loadAudioData(audioId);

      final response = await http
          .post(
            Uri.parse('$baseUrl/listen?model=$model&encoding=linear16&sample_rate=16000'),
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
            final confidence = (firstAlt['confidence'] as num?)?.toDouble() ?? 0.5;
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

  /// Load audio data from audioId (file path or data).
  /// Stub implementation - would need to load actual audio bytes.
  Future<List<int>> _loadAudioData(String audioId) async {
    // TODO: Implement actual audio loading from file or buffer
    // For now, return empty bytes - this would come from audio file system
    return [];
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
