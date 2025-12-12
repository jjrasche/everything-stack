/// Central export for all exception types.
///
/// Import this file to access all platform-agnostic exceptions:
/// ```dart
/// import 'package:everything_stack/core/exceptions/exceptions.dart';
///
/// try {
///   await repository.save(entity);
/// } on DuplicateEntityException catch (e) {
///   // Handle duplicate
/// } on PersistenceException catch (e) {
///   // Handle other persistence errors
/// }
/// ```

export 'persistence_exceptions.dart';
