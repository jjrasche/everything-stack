/// # ChannelObjectBoxAdapter
///
/// ## What it does
/// ObjectBox implementation of PersistenceAdapter for Channel entities.
///
/// NOTE: Not yet implemented. Channel entities need ObjectBox decorators (@Entity, @Property)
/// which have been removed to support web platform (IndexedDB).
///
/// ## Status
/// - Channel uses IndexedDB on web (fully functional)
/// - ObjectBox adapters pending: requires re-adding ObjectBox decorators to Channel
/// - Available on web via ChannelIndexedDBAdapter

import 'package:objectbox/objectbox.dart';
import 'base_objectbox_adapter.dart';
import '../../tools/media/entities/channel.dart';

/// Stub adapter - Channel persistence not yet available on native platforms.
/// Use web platform for full functionality.
class ChannelObjectBoxAdapter extends BaseObjectBoxAdapter<Channel, dynamic> {
  ChannelObjectBoxAdapter(Store store) : super(store);

  @override
  dynamic toOB(Channel entity) => throw UnimplementedError(
        'Channel persistence not yet available on native platforms. Use web (IndexedDB) instead.',
      );

  @override
  Channel fromOB(dynamic ob) => throw UnimplementedError(
        'Channel persistence not yet available on native platforms. Use web (IndexedDB) instead.',
      );

  @override
  Condition<dynamic> uuidEqualsCondition(String uuid) =>
      throw UnimplementedError(
        'Channel persistence not yet available on native platforms. Use web (IndexedDB) instead.',
      );

  @override
  Condition<dynamic> syncStatusLocalCondition() => throw UnimplementedError(
        'Channel persistence not yet available on native platforms. Use web (IndexedDB) instead.',
      );
}
