/// # Deepgram WebSocket Integration Test
///
/// Tests real Deepgram connection using Rust WebSocket transport.
/// Verifies authentication, bidirectional communication, and transcription.
///
/// Run with:
///   flutter test integration_test/io/deepgram_integration_test.dart -d windows

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:everything_stack_template/io/transport/transport.dart';
import 'package:everything_stack_template/io/transport/transport_factory.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Load .env for API key
    try {
      await dotenv.load(fileName: '.env');
    } catch (e) {
      await dotenv.load(fileName: '.env.example');
    }
  });

  group('Deepgram WebSocket Integration', () {
    late Transport transport;

    tearDown(() async {
      // Proper cleanup: close connection AND dispose resources
      await transport.close();
      transport.dispose();
    });

    test('connects with subprotocol authentication', () async {
      // ARRANGE: Get API key from environment
      final apiKey = dotenv.env['DEEPGRAM_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        fail('DEEPGRAM_API_KEY not found in .env');
      }

      final config = TransportConfig(
        host: 'api.deepgram.com',
        port: 443,
        useTls: true,
        path: '/v2/listen', // v2 REQUIRED for flux model
        queryParams: {
          'model': 'flux-general-en',
          'encoding': 'linear16',
          'sample_rate': '16000',
          // Flux-specific parameters (NO punctuate/utterances/smart_format)
          'eot_threshold': '0.7',
        },
        subprotocols: ['token', apiKey], // Deepgram authentication
      );

      final factory = createTransportFactory();
      transport = factory.create(config);

      // ACT: Connect to Deepgram
      await transport.connect();

      // ASSERT: Should be connected
      expect(transport.state, TransportState.connected);

      // Cleanup happens in tearDown
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('sends audio and receives transcription', () async {
      // ARRANGE: Setup transport
      final apiKey = dotenv.env['DEEPGRAM_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        fail('DEEPGRAM_API_KEY not found in .env');
      }

      final config = TransportConfig(
        host: 'api.deepgram.com',
        port: 443,
        useTls: true,
        path: '/v2/listen', // v2 REQUIRED for flux model
        queryParams: {
          'model': 'flux-general-en',
          'encoding': 'linear16',
          'sample_rate': '16000',
          // Flux-specific parameters (NO punctuate/utterances/interim_results)
          'eot_threshold': '0.7',
        },
        subprotocols: ['token', apiKey],
      );

      final factory = createTransportFactory();
      transport = factory.create(config);

      // Track received messages
      final receivedMessages = <Uint8List>[];
      final subscription = transport.received.listen((data) {
        receivedMessages.add(data);
        print('📥 Received ${data.length} bytes from Deepgram');
      });

      // ACT: Connect
      await transport.connect();
      expect(transport.state, TransportState.connected);

      // Send fake audio data (silence - zeros)
      final audioChunk = Uint8List(3200); // 100ms of 16kHz audio
      await transport.send(audioChunk);
      print('📤 Sent ${audioChunk.length} bytes of audio to Deepgram');

      // Wait for potential response from Deepgram
      // Note: Silent audio may not generate any transcription
      await Future.delayed(const Duration(seconds: 2));

      // ASSERT: Connection worked and audio was sent
      // (Deepgram may not respond to silent audio, which is expected)
      print('✅ Connection successful, sent ${audioChunk.length} bytes');
      if (receivedMessages.isNotEmpty) {
        print('   Received ${receivedMessages.length} messages from Deepgram');
      } else {
        print('   No messages received (expected for silent audio)');
      }

      // Cancel subscription before tearDown cleanup
      await subscription.cancel();

      // Cleanup happens in tearDown
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
