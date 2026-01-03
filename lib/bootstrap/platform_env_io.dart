/// Native (io) implementation for Platform.environment access
///
/// Uses dart:io Platform.environment to read OS environment variables.
library;

import 'dart:io' show Platform;

/// Get environment variable by key from OS environment
String? getPlatformEnvironmentVariable(String key) {
  final value = Platform.environment[key];
  return (value != null && value.isNotEmpty) ? value : null;
}
