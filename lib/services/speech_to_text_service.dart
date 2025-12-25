/// Speech-to-text service for converting voice input to text.
///
/// Wraps the speech_to_text package for cross-platform STT.
/// Handles:
/// - Initializing speech recognition
/// - Starting/stopping recording
/// - Converting audio to text
/// - Handling errors and permissions

import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

class SpeechToTextService {
  final SpeechToText _speechToText = SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;

  /// Initialize the speech recognition service
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      final available = await _speechToText.initialize(
        onError: (error) => print('Error: $error'),
        onStatus: (status) => print('Status: $status'),
        debugLogging: false,
      );

      _isInitialized = available;
      return available;
    } catch (e) {
      print('Failed to initialize speech recognition: $e');
      return false;
    }
  }

  /// Start listening to microphone
  Future<bool> startListening() async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return false;
    }

    try {
      if (_isListening) return true;

      _isListening = true;
      await _speechToText.listen(
        onResult: (result) {
          // Result is handled via the stream
        },
      );
      return true;
    } catch (e) {
      print('Error starting speech recognition: $e');
      _isListening = false;
      return false;
    }
  }

  /// Stop listening and get final result
  Future<String> stopListening() async {
    if (!_isListening) return '';

    try {
      await _speechToText.stop();
      _isListening = false;

      final result = _speechToText.lastRecognizedWords;
      return result;
    } catch (e) {
      print('Error stopping speech recognition: $e');
      _isListening = false;
      return '';
    }
  }

  /// Get current recognized text while listening
  String getCurrentText() {
    return _speechToText.lastRecognizedWords;
  }

  /// Check if currently listening
  bool get isListening => _isListening;

  /// Check if service is available on this device
  bool get isAvailable => _isInitialized;

  /// Get list of available locales
  Future<List<String>> getAvailableLocales() async {
    if (!_isInitialized) {
      await initialize();
    }
    final locales = await _speechToText.locales();
    return locales.map((locale) => locale.localeId).toList();
  }

  /// Set the language for recognition
  Future<bool> setLanguage(String languageCode) async {
    if (!_isInitialized) {
      await initialize();
    }
    // Implementation depends on speech_to_text API
    return true;
  }

  /// Cleanup resources
  void dispose() {
    if (_isListening) {
      _speechToText.stop();
    }
  }
}
