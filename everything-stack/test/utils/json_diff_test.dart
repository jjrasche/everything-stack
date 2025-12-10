import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/utils/json_diff.dart';

void main() {
  group('JsonDiff', () {
    group('add operation', () {
      test('detects added field', () {
        final oldState = {'name': 'John'};
        final newState = {'name': 'John', 'age': 30};

        final patch = JsonDiff.diff(oldState, newState);

        expect(patch, hasLength(1));
        expect(patch[0]['op'], 'add');
        expect(patch[0]['path'], '/age');
        expect(patch[0]['value'], 30);
      });

      test('detects multiple added fields', () {
        final oldState = {'name': 'John'};
        final newState = {'name': 'John', 'age': 30, 'city': 'NYC'};

        final patch = JsonDiff.diff(oldState, newState);

        expect(patch, hasLength(2));
        expect(patch.where((op) => op['op'] == 'add'), hasLength(2));
      });
    });

    group('remove operation', () {
      test('detects removed field', () {
        final oldState = {'name': 'John', 'age': 30};
        final newState = {'name': 'John'};

        final patch = JsonDiff.diff(oldState, newState);

        expect(patch, hasLength(1));
        expect(patch[0]['op'], 'remove');
        expect(patch[0]['path'], '/age');
      });
    });

    group('replace operation', () {
      test('detects changed value', () {
        final oldState = {'name': 'John', 'age': 30};
        final newState = {'name': 'John', 'age': 31};

        final patch = JsonDiff.diff(oldState, newState);

        expect(patch, hasLength(1));
        expect(patch[0]['op'], 'replace');
        expect(patch[0]['path'], '/age');
        expect(patch[0]['value'], 31);
      });

      test('detects type change', () {
        final oldState = {'value': 'text'};
        final newState = {'value': 123};

        final patch = JsonDiff.diff(oldState, newState);

        expect(patch, hasLength(1));
        expect(patch[0]['op'], 'replace');
        expect(patch[0]['value'], 123);
      });
    });

    group('no change', () {
      test('returns empty patch for identical objects', () {
        final state = {'name': 'John', 'age': 30};

        final patch = JsonDiff.diff(state, state);

        expect(patch, isEmpty);
      });

      test('returns empty patch for deep-equal objects', () {
        final oldState = {'name': 'John', 'age': 30};
        final newState = {'name': 'John', 'age': 30};

        final patch = JsonDiff.diff(oldState, newState);

        expect(patch, isEmpty);
      });
    });

    group('nested objects', () {
      test('detects change in nested object', () {
        final oldState = {
          'user': {'name': 'John', 'age': 30}
        };
        final newState = {
          'user': {'name': 'Jane', 'age': 30}
        };

        final patch = JsonDiff.diff(oldState, newState);

        expect(patch, hasLength(1));
        expect(patch[0]['op'], 'replace');
        expect(patch[0]['path'], '/user/name');
        expect(patch[0]['value'], 'Jane');
      });

      test('detects added field in nested object', () {
        final oldState = {
          'user': {'name': 'John'}
        };
        final newState = {
          'user': {'name': 'John', 'age': 30}
        };

        final patch = JsonDiff.diff(oldState, newState);

        expect(patch, hasLength(1));
        expect(patch[0]['op'], 'add');
        expect(patch[0]['path'], '/user/age');
      });
    });

    group('arrays', () {
      test('detects changed array', () {
        final oldState = {
          'tags': ['a', 'b']
        };
        final newState = {
          'tags': ['a', 'c']
        };

        final patch = JsonDiff.diff(oldState, newState);

        expect(patch, hasLength(1));
        expect(patch[0]['op'], 'replace');
        expect(patch[0]['path'], '/tags/1');
        expect(patch[0]['value'], 'c');
      });

      test('detects added array element', () {
        final oldState = {
          'tags': ['a']
        };
        final newState = {
          'tags': ['a', 'b']
        };

        final patch = JsonDiff.diff(oldState, newState);

        expect(patch, hasLength(1));
        expect(patch[0]['op'], 'add');
        expect(patch[0]['path'], '/tags/1');
        expect(patch[0]['value'], 'b');
      });

      test('detects removed array element', () {
        final oldState = {
          'tags': ['a', 'b']
        };
        final newState = {
          'tags': ['a']
        };

        final patch = JsonDiff.diff(oldState, newState);

        expect(patch, hasLength(1));
        expect(patch[0]['op'], 'remove');
        expect(patch[0]['path'], '/tags/1');
      });
    });

    group('null values', () {
      test('detects null to value change', () {
        final oldState = {'name': null};
        final newState = {'name': 'John'};

        final patch = JsonDiff.diff(oldState, newState);

        expect(patch, hasLength(1));
        expect(patch[0]['op'], 'replace');
        expect(patch[0]['value'], 'John');
      });

      test('detects value to null change', () {
        final oldState = {'name': 'John'};
        final newState = {'name': null};

        final patch = JsonDiff.diff(oldState, newState);

        expect(patch, hasLength(1));
        expect(patch[0]['op'], 'replace');
        expect(patch[0]['value'], null);
      });
    });

    group('changedFields extraction', () {
      test('extracts top-level changed fields', () {
        final oldState = {'name': 'John', 'age': 30};
        final newState = {'name': 'Jane', 'age': 31};

        final fields = JsonDiff.extractChangedFields(oldState, newState);

        expect(fields, containsAll(['name', 'age']));
        expect(fields, hasLength(2));
      });

      test('extracts added fields', () {
        final oldState = {'name': 'John'};
        final newState = {'name': 'John', 'age': 30};

        final fields = JsonDiff.extractChangedFields(oldState, newState);

        expect(fields, contains('age'));
      });

      test('extracts removed fields', () {
        final oldState = {'name': 'John', 'age': 30};
        final newState = {'name': 'John'};

        final fields = JsonDiff.extractChangedFields(oldState, newState);

        expect(fields, contains('age'));
      });

      test('extracts nested field as root field', () {
        final oldState = {
          'user': {'name': 'John', 'age': 30}
        };
        final newState = {
          'user': {'name': 'Jane', 'age': 30}
        };

        final fields = JsonDiff.extractChangedFields(oldState, newState);

        // We track the root field that contains changes, not deep paths
        expect(fields, contains('user'));
      });

      test('returns empty list for identical objects', () {
        final state = {'name': 'John', 'age': 30};

        final fields = JsonDiff.extractChangedFields(state, state);

        expect(fields, isEmpty);
      });
    });
  });
}
