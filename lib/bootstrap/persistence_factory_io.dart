/// Native (mobile/desktop) implementation of PersistenceFactory.
/// Uses ObjectBox with native HNSW vector search.
library;

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'persistence_factory.dart';
import '../objectbox.g.dart';
import '../persistence/objectbox/media_item_objectbox_adapter.dart';
import '../persistence/objectbox/channel_objectbox_adapter.dart';
import '../persistence/objectbox/edge_objectbox_adapter.dart';
import '../persistence/objectbox/entity_version_objectbox_adapter.dart';

/// Initialize ObjectBox persistence layer for native platforms.
///
/// Opens ObjectBox store in application documents directory and creates
/// adapters for all entity types.
Future<PersistenceFactory> initializePersistence() async {
  // Get application documents directory
  final appDir = await getApplicationDocumentsDirectory();
  final storeDir = Directory('${appDir.path}/objectbox');

  // Open ObjectBox store
  final store = await openStore(directory: storeDir.path);

  // Create adapters
  final mediaItemAdapter = MediaItemObjectBoxAdapter(store);
  final channelAdapter = ChannelObjectBoxAdapter(store);
  final edgeAdapter = EdgeObjectBoxAdapter(store);
  final versionAdapter = EntityVersionObjectBoxAdapter(store);

  return PersistenceFactory(
    noteAdapter: null, // Notes removed - use media search on web
    mediaItemAdapter: mediaItemAdapter,
    channelAdapter: channelAdapter,
    edgeAdapter: edgeAdapter,
    versionAdapter: versionAdapter,
    handle: store,
  );
}
