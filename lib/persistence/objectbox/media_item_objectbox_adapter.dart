/// # MediaItemObjectBoxAdapter
///
/// ## What it does
/// ObjectBox implementation of PersistenceAdapter for MediaItem entities.
/// Provides HNSW semantic search support using ObjectBox's native vector indexing.
///
/// NOTE: Not yet implemented. MediaItem entities need ObjectBox decorators (@Entity, @Property)
/// which have been removed to support web platform (IndexedDB).
///
/// ## Status
/// - MediaItem uses IndexedDB on web (fully functional)
/// - ObjectBox adapters pending: requires re-adding ObjectBox decorators to MediaItem
/// - Semantic search available on web via MediaItemIndexedDBAdapter

import 'package:objectbox/objectbox.dart';
import 'base_objectbox_adapter.dart';
import '../../tools/media/entities/media_item.dart';

/// Stub adapter - MediaItem persistence not yet available on native platforms.
/// Use web platform for semantic search.
class MediaItemObjectBoxAdapter extends BaseObjectBoxAdapter<MediaItem, dynamic> {
  MediaItemObjectBoxAdapter(Store store) : super(store);

  @override
  dynamic toOB(MediaItem entity) => throw UnimplementedError(
    'MediaItem persistence not yet available on native platforms. Use web (IndexedDB) instead.',
  );

  @override
  MediaItem fromOB(dynamic ob) => throw UnimplementedError(
    'MediaItem persistence not yet available on native platforms. Use web (IndexedDB) instead.',
  );

  @override
  Condition<dynamic> uuidEqualsCondition(String uuid) => throw UnimplementedError(
    'MediaItem persistence not yet available on native platforms. Use web (IndexedDB) instead.',
  );

  @override
  Condition<dynamic> syncStatusLocalCondition() => throw UnimplementedError(
    'MediaItem persistence not yet available on native platforms. Use web (IndexedDB) instead.',
  );
}
