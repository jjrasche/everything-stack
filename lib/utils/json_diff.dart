/// # JsonDiff
///
/// ## What it does
/// In-house implementation of RFC 6902 JSON Patch diff generation.
/// Compares two JSON objects and produces a list of patch operations.
///
/// ## What it enables
/// - Version history: compute delta between entity states
/// - Sync: transmit only changes, not full entities
/// - Audit: understand exactly what changed field-by-field
///
/// ## Usage
/// ```dart
/// final oldState = {'name': 'John', 'age': 30};
/// final newState = {'name': 'Jane', 'age': 31};
///
/// final patch = JsonDiff.diff(oldState, newState);
/// // [
/// //   {'op': 'replace', 'path': '/name', 'value': 'Jane'},
/// //   {'op': 'replace', 'path': '/age', 'value': 31}
/// // ]
///
/// final fields = JsonDiff.extractChangedFields(oldState, newState);
/// // ['name', 'age']
/// ```
///
/// ## RFC 6902 Operations
/// - add: new field added
/// - remove: field deleted
/// - replace: field value changed
///
/// ## Limitations
/// - No move/copy operations (not needed for entity versioning)
/// - No test operations (not needed for diff generation)
/// - Designed for flat-ish entity objects, not arbitrary JSON

class JsonDiff {
  /// Generate RFC 6902 JSON Patch operations to transform oldState into newState.
  ///
  /// Returns list of operations: {'op': 'add|remove|replace', 'path': '/field', 'value': ...}
  static List<Map<String, dynamic>> diff(
    Map<String, dynamic> oldState,
    Map<String, dynamic> newState,
  ) {
    final operations = <Map<String, dynamic>>[];
    _diffRecursive(oldState, newState, '', operations);
    return operations;
  }

  /// Extract top-level field names that changed between states.
  ///
  /// Used for EntityVersion.changedFields - queryable list without parsing delta.
  static List<String> extractChangedFields(
    Map<String, dynamic> oldState,
    Map<String, dynamic> newState,
  ) {
    final fields = <String>{};

    // Check for changed/removed fields
    for (final key in oldState.keys) {
      if (!newState.containsKey(key) || !_deepEqual(oldState[key], newState[key])) {
        fields.add(key);
      }
    }

    // Check for added fields
    for (final key in newState.keys) {
      if (!oldState.containsKey(key)) {
        fields.add(key);
      }
    }

    return fields.toList();
  }

  static void _diffRecursive(
    dynamic oldValue,
    dynamic newValue,
    String path,
    List<Map<String, dynamic>> operations,
  ) {
    // Both are maps - recurse into nested structure
    if (oldValue is Map<String, dynamic> && newValue is Map<String, dynamic>) {
      _diffMaps(oldValue, newValue, path, operations);
      return;
    }

    // Both are lists - recurse into array
    if (oldValue is List && newValue is List) {
      _diffLists(oldValue, newValue, path, operations);
      return;
    }

    // Values differ - replace operation
    if (!_deepEqual(oldValue, newValue)) {
      operations.add({
        'op': 'replace',
        'path': path,
        'value': newValue,
      });
    }
  }

  static void _diffMaps(
    Map<String, dynamic> oldMap,
    Map<String, dynamic> newMap,
    String path,
    List<Map<String, dynamic>> operations,
  ) {
    // Check for changed or removed keys
    for (final key in oldMap.keys) {
      final fieldPath = '$path/$key';

      if (!newMap.containsKey(key)) {
        // Key removed
        operations.add({
          'op': 'remove',
          'path': fieldPath,
        });
      } else {
        // Key exists in both - recurse to check value
        _diffRecursive(oldMap[key], newMap[key], fieldPath, operations);
      }
    }

    // Check for added keys
    for (final key in newMap.keys) {
      if (!oldMap.containsKey(key)) {
        final fieldPath = '$path/$key';
        operations.add({
          'op': 'add',
          'path': fieldPath,
          'value': newMap[key],
        });
      }
    }
  }

  static void _diffLists(
    List oldList,
    List newList,
    String path,
    List<Map<String, dynamic>> operations,
  ) {
    final minLength = oldList.length < newList.length ? oldList.length : newList.length;

    // Check existing indices for changes
    for (int i = 0; i < minLength; i++) {
      _diffRecursive(oldList[i], newList[i], '$path/$i', operations);
    }

    // Handle removed elements (old list is longer)
    for (int i = newList.length; i < oldList.length; i++) {
      operations.add({
        'op': 'remove',
        'path': '$path/$i',
      });
    }

    // Handle added elements (new list is longer)
    for (int i = oldList.length; i < newList.length; i++) {
      operations.add({
        'op': 'add',
        'path': '$path/$i',
        'value': newList[i],
      });
    }
  }

  /// Deep equality check for JSON values.
  static bool _deepEqual(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;

    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_deepEqual(a[key], b[key])) {
          return false;
        }
      }
      return true;
    }

    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (!_deepEqual(a[i], b[i])) return false;
      }
      return true;
    }

    return a == b;
  }
}
