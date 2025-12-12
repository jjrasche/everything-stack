/// # Persistence Exceptions
///
/// ## What it does
/// Platform-agnostic exception hierarchy for persistence layer errors.
/// Adapters translate platform-specific errors (ObjectBox, IndexedDB) to these typed exceptions.
///
/// ## What it enables
/// - Repositories catch typed exceptions, not platform-specific errors
/// - UI can handle errors without knowing the persistence backend
/// - Same error handling code works with ObjectBox and IndexedDB
///
/// ## Usage
/// ```dart
/// // In adapter:
/// try {
///   return box.get(id);
/// } catch (e) {
///   throw EntityNotFoundException('Task', id: id, cause: e);
/// }
///
/// // In repository or UI:
/// try {
///   await repository.findById(id);
/// } catch (e) {
///   if (e is EntityNotFoundException) {
///     // Handle not found
///   } else if (e is PersistenceException) {
///     // Handle general persistence error
///   }
/// }
/// ```

/// Base exception for all persistence layer errors.
///
/// Platform-specific adapters translate their errors to PersistenceException
/// or its subclasses. Application code catches these typed exceptions,
/// never platform-specific errors like UniqueViolationException (ObjectBox)
/// or DOMException (IndexedDB).
class PersistenceException implements Exception {
  /// Human-readable error message
  final String message;

  /// Optional underlying cause (platform-specific exception)
  final Object? cause;

  /// Optional stack trace from underlying error
  final StackTrace? stackTrace;

  PersistenceException(
    this.message, {
    this.cause,
    this.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer('PersistenceException: $message');
    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }
    return buffer.toString();
  }
}

/// Entity not found in database.
///
/// Thrown by strict lookup methods when entity MUST exist:
/// - `adapter.getById(id)` - throws if not found
/// - `adapter.getByUuid(uuid)` - throws if not found
///
/// NOT thrown by optional methods:
/// - `adapter.findById(id)` - returns null if not found
/// - `adapter.findByUuid(uuid)` - returns null if not found
///
/// Usage:
/// ```dart
/// // Optional lookup - returns null
/// final task = await adapter.findById(123);
/// if (task == null) { /* handle not found */ }
///
/// // Required lookup - throws exception
/// try {
///   final task = await adapter.getById(123);  // Must exist
///   task.status = TaskStatus.completed;
///   await adapter.save(task);
/// } on EntityNotFoundException catch (e) {
///   // Task was deleted by another process
/// }
/// ```
class EntityNotFoundException extends PersistenceException {
  /// Type of entity that wasn't found (e.g., 'Note', 'Task')
  final String entityType;

  /// Database ID that wasn't found (if lookup was by ID)
  final int? id;

  /// UUID that wasn't found (if lookup was by UUID)
  final String? uuid;

  EntityNotFoundException(
    this.entityType, {
    this.id,
    this.uuid,
    Object? cause,
    StackTrace? stackTrace,
  }) : super(
          _buildMessage(entityType, id: id, uuid: uuid),
          cause: cause,
          stackTrace: stackTrace,
        );

  static String _buildMessage(String entityType, {int? id, String? uuid}) {
    if (id != null) {
      return '$entityType not found with id=$id';
    }
    if (uuid != null) {
      return '$entityType not found with uuid=$uuid';
    }
    return '$entityType not found';
  }

  @override
  String toString() => 'EntityNotFoundException: $message';
}

/// Duplicate entity detected (unique constraint violation).
///
/// Thrown when:
/// - Saving entity with duplicate unique field (e.g., composite key on Edge)
/// - UUID collision (extremely rare, but possible)
/// - Platform-specific unique constraints violated
class DuplicateEntityException extends PersistenceException {
  /// Type of entity with duplicate (e.g., 'Edge', 'Note')
  final String entityType;

  /// Field or fields that are duplicated
  final String fieldName;

  /// Value of the duplicate field
  final Object? fieldValue;

  DuplicateEntityException(
    this.entityType,
    this.fieldName, {
    this.fieldValue,
    Object? cause,
    StackTrace? stackTrace,
  }) : super(
          'Duplicate $entityType: $fieldName=${fieldValue ?? 'unknown'}',
          cause: cause,
          stackTrace: stackTrace,
        );

  @override
  String toString() => 'DuplicateEntityException: $message';
}

/// Transaction operation failed.
///
/// Thrown when:
/// - Transaction aborted due to exception in work callback
/// - Transaction rolled back by platform
/// - Nested transaction attempted (not supported)
/// - Deadlock detected
class TransactionException extends PersistenceException {
  /// Whether the transaction was rolled back
  final bool rolledBack;

  TransactionException(
    String message, {
    this.rolledBack = true,
    Object? cause,
    StackTrace? stackTrace,
  }) : super(
          message,
          cause: cause,
          stackTrace: stackTrace,
        );

  @override
  String toString() {
    final status = rolledBack ? '(rolled back)' : '(unknown state)';
    return 'TransactionException $status: $message';
  }
}

/// Concurrency conflict detected.
///
/// Thrown when:
/// - Optimistic locking version mismatch
/// - Entity modified by another process between read and write
/// - IndexedDB transaction auto-committed before completion
///
/// Not currently used (no optimistic locking yet), but reserved for future use.
class ConcurrencyException extends PersistenceException {
  /// Type of entity with conflict
  final String entityType;

  /// UUID of conflicting entity
  final String? uuid;

  ConcurrencyException(
    this.entityType, {
    this.uuid,
    Object? cause,
    StackTrace? stackTrace,
  }) : super(
          'Concurrency conflict on $entityType${uuid != null ? ' (uuid=$uuid)' : ''}',
          cause: cause,
          stackTrace: stackTrace,
        );

  @override
  String toString() => 'ConcurrencyException: $message';
}

/// Query operation failed.
///
/// Thrown when:
/// - Malformed query condition
/// - Index missing for query
/// - Query timeout
/// - Platform-specific query errors
class QueryException extends PersistenceException {
  /// Query that failed (if available)
  final String? query;

  QueryException(
    String message, {
    this.query,
    Object? cause,
    StackTrace? stackTrace,
  }) : super(
          message,
          cause: cause,
          stackTrace: stackTrace,
        );

  @override
  String toString() {
    if (query != null) {
      return 'QueryException: $message (query: $query)';
    }
    return 'QueryException: $message';
  }
}

/// Database storage limit exceeded.
///
/// Thrown when:
/// - Disk space exhausted (ObjectBox)
/// - IndexedDB quota exceeded (web)
/// - Entity size exceeds platform limits
class StorageLimitException extends PersistenceException {
  /// Size attempted (if known)
  final int? requestedSize;

  /// Available space (if known)
  final int? availableSpace;

  StorageLimitException(
    String message, {
    this.requestedSize,
    this.availableSpace,
    Object? cause,
    StackTrace? stackTrace,
  }) : super(
          message,
          cause: cause,
          stackTrace: stackTrace,
        );

  @override
  String toString() {
    final buffer = StringBuffer('StorageLimitException: $message');
    if (requestedSize != null && availableSpace != null) {
      buffer.write(' (requested: $requestedSize, available: $availableSpace)');
    }
    return buffer.toString();
  }
}
