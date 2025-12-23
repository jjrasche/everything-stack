import 'dart:async';
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';

/// Audio playback service contract.
abstract class AudioPlaybackService {
  static AudioPlaybackService instance = JustAudioPlaybackService();

  Future<void> initialize();
  Future<void> playAudio(Uint8List audioBytes);
  Future<void> stop();
  void dispose();
}

/// Production implementation using `just_audio` package
class JustAudioPlaybackService implements AudioPlaybackService {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> initialize() async {
    print('AudioPlaybackService initialized');
  }

  @override
  Future<void> playAudio(Uint8List audioBytes) async {
    try {
      final audioSource = ByteArrayAudioSource(audioBytes);
      await _player.setAudioSource(audioSource);
      await _player.play();
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
    _isReady = false;
  }
}

/// Custom audio source for just_audio that plays from byte array
class ByteArrayAudioSource extends StreamAudioSource {
  final Uint8List bytes;

  ByteArrayAudioSource(this.bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final startByte = start ?? 0;
    final endByte = end ?? bytes.length;

    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: endByte - startByte,
      offset: startByte,
      stream: Stream.value(bytes.sublist(startByte, endByte)),
      contentType: 'audio/wav',
    );
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
