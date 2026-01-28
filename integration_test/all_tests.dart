/// # Consolidated Integration Test Runner
///
/// Single entry point for ALL integration tests (standalone + test harness).
/// Solves Flutter bug #135673 where multiple test files fail sequentially on desktop.
///
/// Run all tests:
/// ```bash
/// flutter test integration_test/all_tests.dart -d windows
/// ```
///
/// ## Architecture
///
/// This file imports and runs:
/// - Test harness tests (via shared/generic_test.dart)
/// - Standalone nerve tests (channel, deepgram, protocol, transport, websocket)
/// - Standalone service tests (barge_in)
///
/// ## Why This Exists
///
/// Flutter bug #135673: Running multiple test files sequentially on desktop platforms
/// causes "Unable to start the app on the device" after the first test completes.
///
/// Workaround: Import all test files into a single entry point with one main().

import 'shared/generic_test.dart' as generic;
import 'nerve/channel_integration_test.dart' as channel;
import 'nerve/deepgram_integration_test.dart' as deepgram;
import 'nerve/protocol_integration_test.dart' as protocol;
import 'nerve/transport_integration_test.dart' as transport;
import 'nerve/websocket_subprotocol_test.dart' as websocket;
import 'services/barge_in_test.dart' as barge_in;

void main() {
  // Test harness tests (timer, regulation, audio, etc.)
  generic.main();

  // Nerve layer tests
  channel.main();
  deepgram.main();
  protocol.main();
  transport.main();
  websocket.main();

  // Service tests
  barge_in.main();
}
