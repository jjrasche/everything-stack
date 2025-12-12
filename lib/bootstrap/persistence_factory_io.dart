/// Native (mobile/desktop) implementation of PersistenceFactory.
/// Uses ObjectBox with native HNSW vector search.
library;

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'persistence_factory.dart';
import '../objectbox.g.dart';
import '../persistence/objectbox/note_objectbox_adapter.dart';
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
  final noteAdapter = NoteObjectBoxAdapter(store);
  final edgeAdapter = EdgeObjectBoxAdapter(store);
  final versionAdapter = EntityVersionObjectBoxAdapter(store);

  return PersistenceFactory(
    noteAdapter: noteAdapter,
    edgeAdapter: edgeAdapter,
    versionAdapter: versionAdapter,
    handle: store,
  );
}
