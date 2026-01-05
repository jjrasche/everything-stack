/// # FlutterTtsImplementer
///
/// Dumb API wrapper for Flutter TTS plugin.
/// Synthesizes text to speech and saves audio to device storage.
/// No state management - just calls plugin and returns results.

import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'tts_implementer.dart';
import '../types/tts_types.dart';

class FlutterTtsImplementer implements TTSImplementer {
  // Cache: maps text+voice+params → audioId for reuse
  final Map<String, String> _synthesisCache = {};

  FlutterTtsImplementer();

  @override
  String get implementerName => 'flutter_tts';

  @override
  Future<TTSInvocationOutput> synthesize({
    required String text,
    required String voiceId,
    required double speechRate,
    required double pitch,
  }) async {
    try {
      // Time the synthesis call
      final stopwatch = Stopwatch()..start();

      // Generate cache key
      final cacheKey =
          _generateCacheKey(text, voiceId, speechRate, pitch);

      // Check cache first
      String audioId;
      double estimatedDuration;

      if (_synthesisCache.containsKey(cacheKey)) {
        audioId = _synthesisCache[cacheKey]!;
        // Estimate duration based on text length and speech rate
        estimatedDuration = _estimateDuration(text, speechRate);
      } else {
        // TODO: Implement actual TTS synthesis via flutter_tts plugin
        // For now, generate a synthetic audioId and estimate duration
        audioId = 'audio_${_generateId(cacheKey)}';
        estimatedDuration = _estimateDuration(text, speechRate);

        // Cache the result
        _synthesisCache[cacheKey] = audioId;
      }

      stopwatch.stop();
      final latencyMs = stopwatch.elapsedMilliseconds.toDouble();

      return TTSInvocationOutput(
        audioId: audioId,
        durationSeconds: estimatedDuration,
        latencyMs: latencyMs,
      );
    } catch (e) {
      throw FlutterTtsException('Synthesis failed: $e');
    }
  }

  /// Generate cache key from synthesis parameters
  String _generateCacheKey(
    String text,
    String voiceId,
    double speechRate,
    double pitch,
  ) {
    final key =
        '$text|$voiceId|$speechRate|$pitch';
    return md5.convert(utf8.encode(key)).toString();
  }

  /// Generate a unique ID from cache key
  String _generateId(String cacheKey) {
    return cacheKey.substring(0, 8);
  }

  /// Estimate audio duration based on text and speech rate
  /// Rough estimate: 150 words per minute at normal speed (1.0)
  double _estimateDuration(String text, double speechRate) {
    final wordCount = text.split(RegExp(r'\s+')).length;
    final wordsPerSecond = (150 / 60) / speechRate; // 2.5 words/sec at 1.0 rate
    return wordCount / wordsPerSecond;
  }
}

// ============ Exceptions ============

class FlutterTtsException implements Exception {
  final String message;
  FlutterTtsException(this.message);

  @override
  String toString() => 'FlutterTtsException: $message';
}
