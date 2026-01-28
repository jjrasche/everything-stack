/// # Test Server Infrastructure
///
/// Manages lifecycle of test servers needed for integration tests.
/// Currently supports WebSocket echo server for transport tests.
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

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Global reference to echo server process
Process? _echoServerProcess;

/// Starts the WebSocket echo server for transport integration tests.
///
/// Server location: test/nerve/echo_server/server.js
/// Listens on: localhost:8080
/// Endpoints:
/// - /echo - Simple echo (text/binary)
/// - /fail-connect - Immediate rejection
/// - /disconnect-after/N - Disconnect after N messages
/// - /slow-echo/MS - Echo with MS millisecond delay
///
/// Automatically falls back gracefully if:
/// - Node.js not installed
/// - Server fails to start
/// - Already running on port 8080
///
/// Returns true if server started successfully, false if fallback needed.
Future<bool> startEchoServer() async {
  if (_echoServerProcess != null) {
    debugPrint('⚠️ Echo server already running');
    return true;
  }

  try {
    debugPrint('🚀 Starting echo server...');

    // Start Node.js echo server
    _echoServerProcess = await Process.start(
      'node',
      ['server.js'],
      workingDirectory: 'test/nerve/echo_server',
      environment: {'PORT': '8080'},
    );

    // Listen to stdout/stderr for debugging
    _echoServerProcess!.stdout.transform(utf8.decoder).listen((line) {
      debugPrint('[echo-server] $line');
    });

    _echoServerProcess!.stderr.transform(utf8.decoder).listen((line) {
      debugPrint('[echo-server] ERROR: $line');
    });

    // Wait for server startup
    await Future.delayed(const Duration(seconds: 2));

    // Verify process is still running
    if (_echoServerProcess!.kill(ProcessSignal.sigusr1)) {
      // Process is alive (signal sent successfully)
      debugPrint('✅ Echo server started successfully on port 8080');
      return true;
    } else {
      debugPrint('⚠️ Echo server process died during startup');
      _echoServerProcess = null;
      return false;
    }
  } catch (e) {
    debugPrint('⚠️ Could not start echo server: $e');
    debugPrint('   Tests will use fallback configuration');
    _echoServerProcess = null;
    return false;
  }
}

/// Stops the echo server if it's running.
///
/// Called in tearDownAll() to clean up resources.
Future<void> stopEchoServer() async {
  if (_echoServerProcess == null) {
    return;
  }

  try {
    debugPrint('🛑 Stopping echo server...');
    _echoServerProcess!.kill();
    await _echoServerProcess!.exitCode;
    debugPrint('✅ Echo server stopped');
  } catch (e) {
    debugPrint('⚠️ Error stopping echo server: $e');
  } finally {
    _echoServerProcess = null;
  }
}

/// Returns true if echo server is currently running.
bool isEchoServerRunning() {
  return _echoServerProcess != null;
}
