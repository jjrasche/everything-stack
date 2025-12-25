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

  @override
  void dispose() {
    _flutterTts.stop();
    _isReady = false;
    print('FlutterTtsService disposed');
  }

  @override
  bool get isReady => _isReady;

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
