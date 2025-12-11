/// Stub implementation for conditional import.
/// This file is never imported directly - it's replaced by platform-specific
/// implementations via conditional imports.
library;

import '../services/blob_store.dart';

/// Creates platform-specific BlobStore.
/// This stub throws - real implementations in _io.dart and _web.dart.
BlobStore createPlatformBlobStore() {
  throw UnsupportedError(
    'Cannot create BlobStore without dart:io or dart:html',
  );
}
