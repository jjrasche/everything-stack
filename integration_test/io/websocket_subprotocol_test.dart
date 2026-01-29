import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:everything_stack_template/bridge/native.dart/api.dart' as rust;
import 'package:everything_stack_template/bridge/native.dart/frb_generated.dart';

/// Test WebSocket subprotocol support through Rust FFI.
///
/// This test verifies that passing subprotocols (like Deepgram's "token, API_KEY")
/// through the FFI bridge doesn't cause panics.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Initialize Rust FFI
    await RustLib.init();
  });

  test('Rust FFI handles subprotocols without panic', () async {
    // ARRANGE: Invalid WebSocket URL that will fail quickly
    const url = 'wss://invalid.example.com/socket';
    final headers = <(String, String)>[];
    final subprotocols = ['token', 'fake_api_key_for_testing'];

    // ACT: Call Rust FFI with subprotocols
    // This should return an error (connection will fail), but NOT panic
    try {
      await rust.websocketConnect(
        url: url,
        headers: headers,
        subprotocols: subprotocols,
      );
      fail('Expected connection to fail');
    } catch (e) {
      // ASSERT: Should get clean error, not panic
      expect(e.toString(), isNot(contains('panic')));
      expect(e.toString(), isNot(contains('assertion')));
      print('✅ Got expected error (not panic): $e');
    }
  });

  test('Rust FFI handles Deepgram-style auth without panic', () async {
    // ARRANGE: Deepgram URL with real format
    const url =
        'wss://api.deepgram.com:443/v2/listen?model=nova-2&encoding=linear16&sample_rate=16000';
    final headers = <(String, String)>[];
    // Use fake API key (will get 401, but shouldn't panic)
    final subprotocols = ['token', 'fake_test_key_abc123'];

    // ACT: Call Rust FFI
    try {
      final handle = await rust.websocketConnect(
        url: url,
        headers: headers,
        subprotocols: subprotocols,
      );

      // If it somehow connects, clean up
      await rust.websocketClose(handle: handle);
      print('⚠️  Unexpected: connection succeeded with fake key');
    } catch (e) {
      // ASSERT: Should fail gracefully, not panic
      final errorMsg = e.toString();
      expect(errorMsg, isNot(contains('panic')));
      expect(errorMsg, isNot(contains('assertion `left == right` failed')));

      // Should get HTTP error from Deepgram
      print('✅ Got expected auth failure: $errorMsg');
    }
  });
}
