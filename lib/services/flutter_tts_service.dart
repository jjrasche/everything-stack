import 'dart:typed_data';
import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/material.dart';
import 'tts_service.dart';
import 'package:everything_stack_template/domain/invocation.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';

/// Cross-platform TTS service using flutter_tts package.
///
/// Works on:
/// - Web (browser SpeechSynthesis API)
/// - Android
/// - iOS
/// - Windows, macOS, Linux
class FlutterTtsService extends TTSService {
  final InvocationRepository<Invocation> _invocationRepository;
  late final FlutterTts _flutterTts;

  bool _isReady = false;

  FlutterTtsService({
    required InvocationRepository<Invocation> invocationRepository,
  }) : _invocationRepository = invocationRepository {
    _flutterTts = FlutterTts();
  }

  @override
  Future<void> initialize() async {
    try {
      // Set default parameters
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _isReady = true;
      print('FlutterTtsService initialized');
    } catch (e) {
      throw TTSException('Failed to initialize TTS', cause: e);
    }
  }

  @override
  Stream<Uint8List> synthesize(
    String text, {
    String? voice,
    String? languageCode,
  }) async* {
    if (!_isReady) {
      throw TTSException('FlutterTtsService not initialized');
    }

    if (text.isEmpty) {
      throw TTSException('Synthesis text cannot be empty');
    }

    try {
      // Set language if provided
      if (languageCode != null) {
        await _flutterTts.setLanguage(languageCode);
      }

      // Speak and wait for completion
      await _flutterTts.speak(text);
      await _waitForCompletion();

      // Return empty stream (flutter_tts handles audio playback directly)
      yield Uint8List(0);
    } catch (e) {
      if (e is TTSException) {
        rethrow;
      }
      throw TTSException('TTS synthesis failed', cause: e);
    }
  }

  /// Wait for TTS to complete speaking
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
          TTSException('TTS Error: $message'),
        );
      }
    });

    // Wait with timeout
    return completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        throw TTSException('TTS operation timed out');
      },
    );
  }

  /// Speak text and wait for audio to ACTUALLY finish playing.
  ///
  /// This is different from synthesize() which returns a stream.
  /// Use this when you need to block until TTS is truly done (for continuous listening).
  ///
  /// Returns: Completes when audio playback is finished
  /// Throws: TTSException if synthesis fails or times out
  Future<void> speakAndAwait(String text) async {
    if (!_isReady) {
      throw TTSException('FlutterTtsService not initialized');
    }

    if (text.isEmpty) {
      throw TTSException('Synthesis text cannot be empty');
    }

    try {
      print('🔊 [FlutterTtsService] Speaking: "$text"');
      await _flutterTts.speak(text);
      print('⏳ [FlutterTtsService] Waiting for audio to finish...');
      await _waitForCompletion();
      print('✅ [FlutterTtsService] Audio playback complete');
    } catch (e) {
      if (e is TTSException) {
        rethrow;
      }
      throw TTSException('TTS synthesis failed', cause: e);
    }
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _isReady = false;
    print('FlutterTtsService disposed');
  }

  @override
  bool get isReady => _isReady;

  @override
  Future<void> synthesizeAndLog({
    required String text,
    required String correlationId,
  }) async {
    print('🔊 [FlutterTtsService] Synthesizing: "$text" (correlationId=$correlationId)');

    final startTime = DateTime.now();

    try {
      if (!_isReady) {
        throw TTSException('FlutterTtsService not initialized');
      }

      if (text.isEmpty) {
        throw TTSException('Synthesis text cannot be empty');
      }

      // Speak and WAIT for audio to actually finish (CRITICAL for continuous listening)
      await speakAndAwait(text);

      final latencyMs = DateTime.now().difference(startTime).inMilliseconds;

      // Record successful invocation (NOW that audio is done)
      final invocation = Invocation(
        correlationId: correlationId,
        componentType: 'tts',
        success: true,
        confidence: 1.0,
        input: {'text': text},
        output: {'latencyMs': latencyMs},
      );

      await _invocationRepository.save(invocation);
      print('✅ [FlutterTtsService] TTS synthesis complete and logged (waited $latencyMs ms for audio)');
    } catch (e) {
      print('⚠️  [FlutterTtsService] TTS synthesis failed: $e');

      // Record failed invocation but don't rethrow - let orchestration continue
      try {
        final failureInvocation = Invocation(
          correlationId: correlationId,
          componentType: 'tts',
          success: false,
          confidence: 0.0,
          input: {'text': text},
          output: {'error': e.toString()},
        );
        await _invocationRepository.save(failureInvocation);
      } catch (logError) {
        print('⚠️  [FlutterTtsService] Failed to log TTS invocation: $logError');
      }

      // Don't rethrow - orchestration should continue even if TTS fails
    }
  }

  // ============================================================================
  // Trainable Implementation
  // ============================================================================

  @override
  Future<String> recordInvocation(dynamic invocation) async {
    if (invocation is! Invocation) {
      throw ArgumentError(
        'Expected Invocation, got ${invocation.runtimeType}',
      );
    }
    await _invocationRepository.save(invocation);
    return invocation.uuid;
  }

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {
    // TODO: Implement TTS learning from feedback
    print('FlutterTtsService.trainFromFeedback() - TODO');
  }

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async {
    // TODO: Implement returning current TTS adaptation state
    return {'status': 'baseline'};
  }

  @override
  Widget buildFeedbackUI(String invocationId) {
    // TODO: Implement TTS feedback UI
    return Center(child: Text('TTS Feedback UI (TODO)'));
  }
}
