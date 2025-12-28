/// # ObjectBox Store Factory Stub for Web Platform
///
/// This file is a stub for Web platform where ObjectBox is not available.
/// Real implementation uses ObjectBox on native platforms.

library;

import 'package:flutter/foundation.dart';
import 'objectbox_stub.dart';

/// Stub Store factory that returns a no-op Store for Web platform.
Future<Store> openObjectBoxStore() async {
  debugPrint('ℹ️ ObjectBox not available on Web platform, using stub');
  return Store();
}
