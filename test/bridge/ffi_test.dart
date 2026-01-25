/// # FFI Bridge Test
///
/// Tests Rust FFI bridge to verify it's working before using for WebSocket.

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/bridge/native.dart/api.dart';
import 'package:everything_stack_template/bridge/native.dart/frb_generated.dart';

void main() {
  setUpAll(() async {
    // Initialize Rust FFI bridge
    await RustLib.init();
    print('🦀 Rust FFI bridge initialized');
  });

  test('hello from rust works', () async {
    final message = await helloFromRust();
    expect(message, contains('Rust'));
    print('✅ FFI Bridge working: $message');
  });
}
