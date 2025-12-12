/// # BaseEntity
///
/// ## What it does
/// Foundation for all domain entities. Provides common fields and lifecycle.
///
/// ## Platform-specific implementations
/// - Native (iOS/Android/Desktop): Uses ObjectBox annotations (@Id, @Property)
/// - Web: Plain Dart class without ObjectBox (uses IndexedDB)
///
/// Conditional imports select the correct implementation automatically.

export 'platform/base_entity_stub.dart'
    if (dart.library.io) 'platform/base_entity_io.dart'
    if (dart.library.html) 'platform/base_entity_web.dart';
