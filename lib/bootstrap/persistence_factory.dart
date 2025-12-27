/// Container for all persistence adapters needed by the application.
/// Abstracts platform differences (ObjectBox vs IndexedDB).
///
/// Uses dynamic types to avoid ObjectBox imports on web.
/// Platform-specific factories (_io.dart, _web.dart) create concrete adapters.
/// Repositories cast to the correct type at usage site.
class PersistenceFactory {
  /// Note adapter - deprecated, use mediaItemAdapter instead (null on new instances)
  final dynamic noteAdapter;

  /// MediaItem adapter - cast to PersistenceAdapter<MediaItem> at usage
  final dynamic mediaItemAdapter;

  /// Channel adapter - cast to PersistenceAdapter<Channel> at usage
  final dynamic channelAdapter;

  /// Edge adapter - cast to EdgePersistenceAdapter at usage
  final dynamic edgeAdapter;

  /// Version adapter - cast to VersionPersistenceAdapter at usage
  final dynamic versionAdapter;

  /// Invocation adapter - cast to PersistenceAdapter<Invocation> at usage
  final dynamic invocationAdapter;

  /// Event adapter - cast to PersistenceAdapter<Event> at usage
  final dynamic eventAdapter;

  /// Platform-specific close handle (Store for ObjectBox, Database for IndexedDB).
  /// Used by background services (e.g., EmbeddingQueueService) that need direct access.
  final dynamic _handle;

  /// Get the underlying store (ObjectBox Store on native, Database on web).
  /// Required by services that need direct Box access (e.g., EmbeddingQueueService).
  dynamic get store => _handle;

  PersistenceFactory({
    this.noteAdapter, // Optional - Notes removed from system
    required this.mediaItemAdapter,
    required this.channelAdapter,
    required this.edgeAdapter,
    required this.versionAdapter,
    required this.invocationAdapter,
    required this.eventAdapter,
    required dynamic handle,
  }) : _handle = handle;

  /// Close all adapters and underlying database.
  Future<void> close() async {
    if (noteAdapter != null) {
      await (noteAdapter as dynamic).close();
    }
    await (mediaItemAdapter as dynamic).close();
    await (channelAdapter as dynamic).close();
    await (edgeAdapter as dynamic).close();
    await (versionAdapter as dynamic).close();
    await (invocationAdapter as dynamic).close();
    await (eventAdapter as dynamic).close();

    // Platform-specific cleanup happens in adapter.close()
    // The handle is kept for future use if needed
  }
}
