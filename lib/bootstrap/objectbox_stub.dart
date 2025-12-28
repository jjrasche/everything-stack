/// # ObjectBox Stub for Web Platform
///
/// This file is a stub that provides no-op implementations of ObjectBox classes
/// for platforms where ObjectBox is not available (Web, etc).
///
/// On native platforms (Android, iOS, macOS, Windows, Linux), the real ObjectBox
/// library is imported and used.

library;

/// Stub Store class that does nothing on Web
/// Real implementation uses ObjectBox native library on native platforms
class Store {
  /// Close the store (no-op on Web)
  void close() {}
}
