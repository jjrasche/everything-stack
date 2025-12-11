/// Native (mobile/desktop) implementation of BlobStore factory.
/// Uses FileSystemBlobStore with path_provider.
library;

import '../services/blob_store.dart';
import '../services/blob_store_io.dart';

/// Creates FileSystemBlobStore for native platforms.
BlobStore createPlatformBlobStore() {
  return FileSystemBlobStore();
}
