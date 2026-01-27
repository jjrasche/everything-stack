/// # Deepgram Flux WebSocket Integration Test
///
/// Tests ONLY the Deepgram Flux WebSocket connection and transcription.
/// Minimal setup: ObjectBox + AudioStorage + Deepgram implementer.
/// No full app bootstrap to keep test focused and fast.

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';

import 'package:everything_stack_template/services/implementations/deepgram_flux_implementer.dart';
import 'package:everything_stack_template/services/audio_storage.dart';
import 'package:everything_stack_template/persistence/objectbox/audio_file_objectbox_adapter.dart';
import 'package:everything_stack_template/core/entity_repository.dart';
import 'package:everything_stack_template/domain/audio_file.dart';
import 'package:everything_stack_template/bootstrap/objectbox_store_factory.dart';
import 'package:everything_stack_template/services/embedding_service.dart';

/// Mock embedding service for this focused test (AudioFile doesn't use embeddings)
class _MockEmbeddingService extends EmbeddingService {
  _MockEmbeddingService() : super(implementer: null);

  @override
  Future<List<double>> embed(String text) async {
    return List.filled(768, 0.0); // Dummy embedding, never called
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late DeepgramFluxImplementer implementer;
  late AudioStorage audioStorage;
  final getIt = GetIt.instance;

  setUpAll(() async {
    // Load .env for API key
    try {
      await dotenv.load(fileName: '.env');
    } catch (e) {
      await dotenv.load(fileName: '.env.example');
    }

    final apiKey = dotenv.env['DEEPGRAM_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('DEEPGRAM_API_KEY not found in .env');
    }

    // Initialize minimal persistence (just ObjectBox, no full bootstrap)
    final store = await openObjectBoxStore();

    // Setup minimal services
    final audioFileAdapter = AudioFileObjectBoxAdapter(store);
    final audioFileRepo = EntityRepository<AudioFile>(
      adapter: audioFileAdapter,
      embeddingService: _MockEmbeddingService(),
    );

    audioStorage = AudioStorage(audioFileRepo);
    getIt.registerSingleton<AudioStorage>(audioStorage);

    // Create implementer
    implementer = DeepgramFluxImplementer(
      apiKey: apiKey,
      model: 'flux-general-en',
    );

    print('✅ Test setup complete - Deepgram API key loaded');
  });

  tearDownAll(() async {
    implementer.dispose();
    await getIt.reset();
  });

  test('Flux WebSocket connects and transcribes', () async {
    print('\n🧪 Testing Deepgram Flux WebSocket connection...\n');

    // Create test audio data (2 seconds of PCM16, 16kHz, mono)
    // Generate a simple sine wave at 440Hz (A4 note)
    final sampleRate = 16000;
    final duration = 2.0;
    final frequency = 440.0; // Hz
    final samples = (sampleRate * duration).toInt();

    final audioBytes = Uint8List(samples * 2); // 16-bit samples
    for (int i = 0; i < samples; i++) {
      final t = i / sampleRate;
      final value =
          (0.3 * 32767 * _Math.sin(2 * _Math.pi * frequency * t)).toInt();
      // Little-endian 16-bit
      audioBytes[i * 2] = value & 0xFF;
      audioBytes[i * 2 + 1] = (value >> 8) & 0xFF;
    }

    print(
        '📊 Generated ${audioBytes.length} bytes of test audio (${duration}s sine wave)');

    // Save audio
    final audioId = await audioStorage.saveAudio(
      audioBytes: audioBytes,
      durationSeconds: duration,
      eventId: 'test_flux_websocket',
    );
    print('💾 Audio saved with ID: $audioId');

    // Test WebSocket connection and transcription
    print('🔗 Connecting to Deepgram Flux WebSocket...');

    final output = await implementer.recognize(
      audioId: audioId,
      durationSeconds: duration,
      eventId: 'test_flux_websocket',
    );

    print('\n✅ WebSocket connection successful!');
    print('📝 Transcription: "${output.transcription}"');
    print('🎯 Confidence: ${output.confidence.toStringAsFixed(2)}');
    print('⏱️  Latency: ${output.latencyMs.toStringAsFixed(0)}ms');
    print('📊 Words: ${output.words.length}');

    // Assertions
    expect(output.transcription, isNotEmpty,
        reason: 'Transcription should not be empty');
    expect(output.confidence, greaterThan(0.0),
        reason: 'Confidence should be > 0');
    expect(output.latencyMs, greaterThan(0.0), reason: 'Latency should be > 0');

    print('\n✅ All assertions passed - Flux WebSocket working!\n');
  });
}

// Simple Math class for sine wave generation
class _Math {
  static const double pi = 3.14159265359;

  static double sin(double x) {
    // Taylor series approximation (good enough for test audio)
    double result = x;
    double term = x;
    for (int n = 1; n < 10; n++) {
      term *= -x * x / ((2 * n) * (2 * n + 1));
      result += term;
    }
    return result;
  }
}
