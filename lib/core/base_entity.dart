/// Foundation for all domain entities. Provides common fields and lifecycle.
///
/// Conditional imports select the correct platform implementation automatically.
/// Default is web (pure Dart); native uses ObjectBox decorators.

export 'platform/base_entity_web.dart'
    if (dart.library.io) 'platform/base_entity_io.dart';
