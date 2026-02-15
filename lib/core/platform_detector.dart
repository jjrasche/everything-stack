/// Cross-platform detection utility.

library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

/// Get the current platform identifier.
/// Returns one of: 'android', 'ios', 'macos', 'windows', 'linux', 'web'
String get currentPlatform {
  if (kIsWeb) return 'web';
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  throw UnsupportedError('Unknown platform');
}

/// All supported platform identifiers.
const allPlatforms = {'android', 'ios', 'macos', 'windows', 'linux', 'web'};

/// Check if implementer supports current platform.
bool isSupported(Set<String> supportedPlatforms) {
  return supportedPlatforms.contains(currentPlatform);
}
