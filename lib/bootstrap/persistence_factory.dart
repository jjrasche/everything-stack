/// Container for all persistence adapters needed by the application.
/// Abstracts platform differences (ObjectBox vs IndexedDB).
///
/// Uses dynamic types to avoid ObjectBox imports on web.
/// Platform-specific factories (_io.dart, _web.dart) create concrete adapters.
/// Repositories cast to the correct type at usage site.
class PersistenceFactory {
  /// Note adapter - cast to PersistenceAdapter<Note> at usage
  final dynamic noteAdapter;

  /// Edge adapter - cast to EdgePersistenceAdapter at usage
  final dynamic edgeAdapter;

  /// Version adapter - cast to VersionPersistenceAdapter at usage
  final dynamic versionAdapter;

  /// Platform-specific close handle (Store for ObjectBox, Database for IndexedDB).
  /// Kept for potential future use (diagnostic access, forced cleanup).
  // ignore: unused_field
  final dynamic _handle;

  PersistenceFactory({
    required this.noteAdapter,
    required this.edgeAdapter,
    required this.versionAdapter,
    required dynamic handle,
  }) : _handle = handle;

  /// Close all adapters and underlying database.
  Future<void> close() async {
    await (noteAdapter as dynamic).close();
    await (edgeAdapter as dynamic).close();
    await (versionAdapter as dynamic).close();

    // Platform-specific cleanup happens in adapter.close()
    // The handle is kept for future use if needed
  }
}
