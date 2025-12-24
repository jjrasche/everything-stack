/// # ChannelIndexedDBAdapter
///
/// ## What it does
/// IndexedDB implementation of PersistenceAdapter for Channel entities.
/// Provides basic CRUD operations for managing YouTube channel subscriptions.
///
/// ## Usage
/// ```dart
/// final db = await idbFactory.open('my_database');
/// final adapter = ChannelIndexedDBAdapter(db);
///
/// // Save a channel
/// final channel = Channel(
///   name: 'Crash Course',
///   youtubeChannelId: 'UCwRH80CmYojIUVYyHMkZkVg',
///   youtubeUrl: 'https://youtube.com/@crashcourse',
/// );
/// await adapter.save(channel);
/// ```

import 'package:idb_shim/idb.dart';
import 'base_indexeddb_adapter.dart';
import 'database_schema.dart';
import '../../tools/media/entities/channel.dart';

class ChannelIndexedDBAdapter extends BaseIndexedDBAdapter<Channel> {
  ChannelIndexedDBAdapter(Database db) : super(db);

  @override
  String get objectStoreName => ObjectStores.channels;

  @override
  Channel fromJson(Map<String, dynamic> json) => Channel.fromJson(json);
}
