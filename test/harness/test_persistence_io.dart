/// Native (mobile/desktop) test persistence implementation.
/// Uses temporary directory for ObjectBox store.
library;

import 'dart:io';
// import 'package:everything_stack_template/bootstrap/persistence_factory.dart'; // Deleted in Phase 1
import 'package:everything_stack_template/objectbox.g.dart';
import 'package:everything_stack_template/persistence/objectbox/media_item_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/channel_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/edge_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/entity_version_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/invocation_objectbox_adapter.dart';

Directory? _testDir;
Store? _store;

/// Platform detection - returns false for native (IO) platforms
bool detectWebPlatform() => false;

/// Initialize ObjectBox test persistence in temporary directory.
Future<PersistenceFactory> initializeTestPersistence() async {
  // Create temporary directory for ObjectBox store
  _testDir = await Directory.systemTemp.createTemp('objectbox_test_');

  // Open ObjectBox store
  _store = await openStore(directory: _testDir!.path);

  // Create adapters
  final mediaItemAdapter = MediaItemObjectBoxAdapter(_store!);
  final channelAdapter = ChannelObjectBoxAdapter(_store!);
  final edgeAdapter = EdgeObjectBoxAdapter(_store!);
  final versionAdapter = EntityVersionObjectBoxAdapter(_store!);
  final invocationAdapter = InvocationObjectBoxAdapter(_store!);

  return PersistenceFactory(
    noteAdapter: null,
    mediaItemAdapter: mediaItemAdapter,
    channelAdapter: channelAdapter,
    edgeAdapter: edgeAdapter,
    versionAdapter: versionAdapter,
    invocationAdapter: invocationAdapter,
    handle: _store,
  );
}

/// Cleanup test persistence (close store, delete temp directory).
Future<void> cleanupTestPersistence() async {
  _store?.close();
  _store = null;

  if (_testDir != null && await _testDir!.exists()) {
    await _testDir!.delete(recursive: true);
    _testDir = null;
  }
}
