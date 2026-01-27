/// # FFI Bridge Smoke Test
///
/// Verifies Rust FFI bridge loads and basic function calls work.
/// Runs as integration test with native library available.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:everything_stack_template/bridge/native.dart/api.dart';
import 'package:everything_stack_template/bridge/native.dart/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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
