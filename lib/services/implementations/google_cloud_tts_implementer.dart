library;

import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:get_it/get_it.dart';

import 'tts_implementer.dart';
import '../types/tts_types.dart';
import '../audio_storage.dart';

class GoogleCloudTTSImplementer implements TTSImplementer {
  final String apiKey;
  final String baseUrl;
  final Duration timeout;

  GoogleCloudTTSImplementer({
    required this.apiKey,
    this.baseUrl = 'https://texttospeech.googleapis.com/v1',
    this.timeout = const Duration(seconds: 30),
  });

  @override
  String get implementerName => 'google_cloud_tts';

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
  Future<TTSInvocationOutput> synthesize({
    required String text,
    required String voiceId,
    required double speechRate,
    required double pitch,
  }) async {
    try {
      debugPrint('🔊 [GoogleCloudTTS] Synthesizing: "$text"');
      debugPrint('   Voice: $voiceId, Rate: $speechRate, Pitch: $pitch');

      // Time the API call
      final stopwatch = Stopwatch()..start();

      // Map generic voiceId to Google Cloud voice name
      final googleVoice = _mapVoiceId(voiceId);

      // Build request body
      final body = jsonEncode({
        'input': {'text': text},
        'voice': {
          'languageCode': 'en-US',
          'name': googleVoice,
        },
        'audioConfig': {
          'audioEncoding': 'MP3',
          'speakingRate': speechRate,
          'pitch':
              (pitch - 1.0) * 20.0, // Convert 0.5-2.0 → -10 to +10 semitones
        },
      });

      // Call Google Cloud TTS API
      final response = await http
          .post(
            Uri.parse('$baseUrl/text:synthesize?key=$apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw GoogleCloudTTSException(
          'API error: ${response.statusCode} ${response.reasonPhrase}\n${response.body}',
        );
      }

      // Parse response
      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      final audioContentBase64 = responseData['audioContent'] as String;
      final audioBytes = base64Decode(audioContentBase64);

      stopwatch.stop();
      final latencyMs = stopwatch.elapsedMilliseconds.toDouble();

      // Estimate duration (Google doesn't return duration)
      final durationSeconds = _estimateDuration(text, speechRate);

      // Store audio in AudioStorage
      final audioStorage = GetIt.instance<AudioStorage>();
      final audioId = await audioStorage.saveAudio(
        audioBytes: Uint8List.fromList(audioBytes),
        durationSeconds: durationSeconds,
        format: 'mp3',
      );

      debugPrint(
          '   ✅ Synthesis complete: ${latencyMs}ms, ${audioBytes.length} bytes');
      return TTSInvocationOutput(
        audioId: audioId,
        durationSeconds: durationSeconds,
        latencyMs: latencyMs,
      );
    } catch (e, stackTrace) {
      debugPrint('   ❌ TTS Error: $e');
      debugPrint('   Stack: $stackTrace');
      throw GoogleCloudTTSException('Synthesis failed: $e');
    }
  }

  /// Map generic voice IDs to Google Cloud voice names.
  /// Falls back to Neural2-C (female) if unrecognized.
  String _mapVoiceId(String voiceId) {
    // If already a Google voice name, use it
    if (voiceId.startsWith('en-US-Neural2-')) {
      return voiceId;
    }

    // Map generic IDs
    switch (voiceId.toLowerCase()) {
      case 'default':
      case 'female':
        return 'en-US-Neural2-C'; // Female, neutral
      case 'male':
        return 'en-US-Neural2-A'; // Male, neutral
      case 'male_conversational':
        return 'en-US-Neural2-D'; // Male, conversational
      case 'female_conversational':
        return 'en-US-Neural2-F'; // Female, conversational
      default:
        return 'en-US-Neural2-C'; // Default female
    }
  }

  /// Estimate audio duration based on text and speech rate.
  /// Rough estimate: 150 words per minute at normal speed (1.0).
  double _estimateDuration(String text, double speechRate) {
    final wordCount = text.split(RegExp(r'\s+')).length;
    final wordsPerSecond = (150 / 60) / speechRate; // 2.5 words/sec at 1.0 rate
    return wordCount / wordsPerSecond;
  }
}

// ============ Exceptions ============

class GoogleCloudTTSException implements Exception {
  final String message;
  GoogleCloudTTSException(this.message);

  @override
  String toString() => 'GoogleCloudTTSException: $message';
}
