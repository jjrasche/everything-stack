/// # Test Server Infrastructure
///
/// Manages lifecycle of test servers needed for integration tests.
/// Uses pure Dart WebSocket echo server - no Node.js dependency.
///
/// ## Usage
///
/// ```dart
/// import 'shared/test_server.dart';
///
/// void main() {
///   IntegrationTestWidgetsFlutterBinding.ensureInitialized();
///
///   setUpAll(() async {
///     await startEchoServer();
///   });
///
///   tearDownAll(() async {
///     await stopEchoServer();
///   });
///
///   // Your tests...
/// }
/// ```

import '../harness/dart_echo_server.dart';

/// Starts the WebSocket echo server for transport integration tests.
///
/// Uses pure Dart implementation - no external dependencies.
/// Listens on: localhost:8080
/// Endpoints:
/// - /echo - Simple echo (text/binary)
/// - /fail-connect - Immediate rejection
/// - /disconnect-after/N - Disconnect after N messages
/// - /slow-echo/MS - Echo with MS millisecond delay
///
/// Returns true if server started successfully, false if fallback needed.
Future<bool> startEchoServer() async {
  return await startDartEchoServer();
}

/// Stops the echo server if it's running.
///
/// Called in tearDownAll() to clean up resources.
Future<void> stopEchoServer() async {
  await stopDartEchoServer();
}

/// Returns true if echo server is currently running.
bool isEchoServerRunning() {
  return isDartEchoServerRunning();
}
