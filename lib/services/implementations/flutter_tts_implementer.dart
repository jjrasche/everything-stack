import 'dart:convert';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'tts_implementer.dart';
import '../types/tts_types.dart';

class FlutterTtsImplementer implements TTSImplementer {
  // Cache: maps text+voice+params → audioId for reuse
  final Map<String, String> _synthesisCache = {};

  late final FlutterTts _flutterTts;
  bool _isInitialized = false;

  FlutterTtsImplementer() {
    _flutterTts = FlutterTts();
  }

  /// Initialize the flutter_tts plugin
  Future<void> initialize() async {
    if (_isInitialized) {
      print('   ℹ️ FlutterTtsImplementer already initialized');
      return;
    }

    try {
      print('🔊 [FlutterTtsImplementer] Initializing...');
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      _isInitialized = true;
      print('   ✅ FlutterTTS initialized: en-US, volume=1.0');
    } catch (e, stackTrace) {
      print('   ❌ FlutterTTS initialization failed: $e');
      print('   Stack: $stackTrace');
      throw FlutterTtsException('Failed to initialize: $e');
    }
  }

  /// Wait for flutter_tts to complete speaking
  Future<void> _waitForCompletion() async {
    final completer = Completer<void>();

    // Set completion handler
    _flutterTts.setCompletionHandler(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    // Set error handler
    _flutterTts.setErrorHandler((message) {
      if (!completer.isCompleted) {
        completer.completeError(
          FlutterTtsException('TTS Error: $message'),
        );
      }
    });

    // Wait with timeout
    return completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        throw FlutterTtsException('TTS operation timed out');
      },
    );
  }

  @override
  String get implementerName => 'flutter_tts';

  @override
  Set<String> get supportedPlatforms => {
        'android',
        'ios',
        'macos',
        'windows',
        'web',
        // NOT linux - flutter_tts doesn't support Linux (verified pub.dev 2026-01-21)
      };

  @override
  Future<TTSInvocationOutput> synthesize({
    required String text,
    required String voiceId,
    required double speechRate,
    required double pitch,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      print('🔊 [FlutterTtsImplementer] Synthesizing: "$text"');
      print('   Voice: $voiceId, Rate: $speechRate, Pitch: $pitch');

      // Time the synthesis call
      final stopwatch = Stopwatch()..start();

      // Generate cache key
      final cacheKey = _generateCacheKey(text, voiceId, speechRate, pitch);

      // Check cache first
      String audioId;
      double estimatedDuration;

      if (_synthesisCache.containsKey(cacheKey)) {
        audioId = _synthesisCache[cacheKey]!;
        // Estimate duration based on text length and speech rate
        estimatedDuration = _estimateDuration(text, speechRate);
        print('   📦 Using cached audio: $audioId');
      } else {
        print('   🎤 Calling flutter_tts.speak()...');
        // Set voice and parameters
        await _flutterTts.setSpeechRate(speechRate);
        await _flutterTts.setPitch(pitch);
        if (voiceId != 'default') {
          await _flutterTts.setVoice({'name': voiceId});
        }

        // Speak and wait for completion
        await _flutterTts.speak(text);
        print('   ⏳ Waiting for TTS completion...');
        await _waitForCompletion();
        print('   ✅ TTS playback completed');

        // Generate audioId and estimate duration
        audioId = 'audio_${_generateId(cacheKey)}';
        estimatedDuration = _estimateDuration(text, speechRate);

        // Cache the result
        _synthesisCache[cacheKey] = audioId;
      }

      stopwatch.stop();
      final latencyMs = stopwatch.elapsedMilliseconds.toDouble();

      print('   ✅ Synthesis complete: ${latencyMs}ms');
      return TTSInvocationOutput(
        audioId: audioId,
        durationSeconds: estimatedDuration,
        latencyMs: latencyMs,
      );
    } catch (e, stackTrace) {
      print('   ❌ TTS Error: $e');
      print('   Stack: $stackTrace');
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
    final key = '$text|$voiceId|$speechRate|$pitch';
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

  /// Stop TTS playback immediately (for barge-in).
  Future<void> stop() async {
    if (!_isInitialized) {
      print('   ℹ️ FlutterTtsImplementer not initialized, nothing to stop');
      return;
    }

    try {
      print('🛑 [FlutterTtsImplementer] Stopping TTS playback');
      await _flutterTts.stop();
      print('   ✅ TTS stopped');
    } catch (e) {
      print('   ⚠️ Error stopping TTS: $e');
      // Don't throw - barge-in should be best-effort
    }
  }
}

// ============ Exceptions ============

class FlutterTtsException implements Exception {
  final String message;
  FlutterTtsException(this.message);

  @override
  String toString() => 'FlutterTtsException: $message';
}
