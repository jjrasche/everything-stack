import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';

/// Audio recording service contract.
///
/// Captures audio from microphone and streams bytes.
abstract class AudioRecordingService {
  static AudioRecordingService instance = RecordAudioRecordingService();

  Future<void> initialize();
  Future<bool> requestPermission();

  /// Start recording and return audio stream (PCM/16kHz/mono)
  Stream<Uint8List> startRecording();

  /// Stop recording
  Future<void> stopRecording();

  bool get isRecording;
  void dispose();
}

/// Production implementation using `record` package
class RecordAudioRecordingService implements AudioRecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamController<Uint8List>? _audioStreamController;
  bool _isRecording = false;

  @override
  Future<void> initialize() async {
    print('AudioRecordingService initialized');
  }

  @override
  Future<bool> requestPermission() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw Exception('Microphone permission not granted');
    }
    return hasPermission;
  }

  @override
  Stream<Uint8List> startRecording() {
    _isRecording = true;
    _audioStreamController = StreamController<Uint8List>();

    final config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    );

    // Start recording and stream audio chunks
    _recorder.startStream(config).then((stream) {
      stream.listen(
        (chunk) {
          // Only add if controller is still open
          if (_audioStreamController != null && !_audioStreamController!.isClosed) {
            _audioStreamController?.add(Uint8List.fromList(chunk));
          }
        },
        onError: (error) {
          if (_audioStreamController != null && !_audioStreamController!.isClosed) {
            _audioStreamController?.addError(error);
          }
        },
        onDone: () {
          if (_audioStreamController != null && !_audioStreamController!.isClosed) {
            _audioStreamController?.close();
          }
        },
      );
    }).catchError((error) {
      if (_audioStreamController != null && !_audioStreamController!.isClosed) {
        _audioStreamController?.addError(error);
      }
    });

    return _audioStreamController!.stream;
  }

  @override
  Future<void> stopRecording() async {
    _isRecording = false;
    await _recorder.stop();
    // Don't close the controller here - let the stream listener close it
    // Closing here causes "Cannot add event after closing" errors
  }

  @override
  bool get isRecording => _isRecording;

  @override
  void dispose() {
    _recorder.dispose();
  }
}

/// Null implementation (fallback)
class NullAudioRecordingService implements AudioRecordingService {
  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Stream<Uint8List> startRecording() => Stream.empty();

  @override
  Future<void> stopRecording() async {}

  @override
  bool get isRecording => false;

  @override
  void dispose() {}
}
