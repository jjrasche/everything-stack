/// Web implementation of BlobStore factory.
/// Uses IndexedDBBlobStore with idb_shim.
library;

import '../services/blob_store.dart';
import '../services/blob_store_web.dart';

/// Creates IndexedDBBlobStore for web platforms.
BlobStore createPlatformBlobStore() {
  return IndexedDBBlobStore();
}
