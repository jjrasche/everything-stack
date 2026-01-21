import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

/// Audio playback service contract.
abstract class AudioPlaybackService {
  static AudioPlaybackService instance = AudioPlayersPlaybackService();

  Future<void> initialize();
  Future<void> playAudio(Uint8List audioBytes);
  Future<void> stop();
  void dispose();
}

/// Production implementation using `audioplayers` package (supports all 6 platforms)
class AudioPlayersPlaybackService implements AudioPlaybackService {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> initialize() async {
    print('AudioPlaybackService initialized (audioplayers)');
  }

  @override
  Future<void> playAudio(Uint8List audioBytes) async {
    try {
      // audioplayers can play directly from bytes
      await _player.play(BytesSource(audioBytes));
    } catch (e) {
      print('Playback error: $e');
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
  }

  @override
  void dispose() {
    _player.dispose();
  }
}

/// Null implementation (fallback)
class NullAudioPlaybackService implements AudioPlaybackService {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> playAudio(Uint8List audioBytes) async {}

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}
}
