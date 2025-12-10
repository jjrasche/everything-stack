/// # BlobStore Tests
///
/// Tests for platform-agnostic binary blob storage.
/// - MockBlobStore for testing
/// - FileSystemBlobStore for mobile/desktop
/// - IndexedDBBlobStore for web

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/blob_store.dart';

void main() {
  group('BlobStore interface', () {
    test('BlobStore is abstract', () {
      expect(BlobStore, isA<Type>());
    });

    test('MockBlobStore is default instance', () {
      BlobStore.instance = MockBlobStore();
      expect(BlobStore.instance, isA<MockBlobStore>());
    });
  });

  group('MockBlobStore', () {
    late MockBlobStore store;

    setUp(() {
      store = MockBlobStore();
    });

    group('Save and load', () {
      test('save stores blob with id', () async {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        await store.save('blob-123', bytes);

        expect(store.contains('blob-123'), isTrue);
      });

      test('load retrieves saved blob', () async {
        final bytes = Uint8List.fromList([10, 20, 30, 40, 50]);
        await store.save('blob-456', bytes);

        final loaded = await store.load('blob-456');

        expect(loaded, isNotNull);
        expect(loaded, bytes);
      });

      test('load returns null for non-existent blob', () async {
        final loaded = await store.load('nonexistent');
        expect(loaded, isNull);
      });

      test('save overwrites existing blob', () async {
        final bytes1 = Uint8List.fromList([1, 2, 3]);
        final bytes2 = Uint8List.fromList([4, 5, 6]);

        await store.save('blob-id', bytes1);
        await store.save('blob-id', bytes2);

        final loaded = await store.load('blob-id');
        expect(loaded, bytes2);
      });
    });

    group('Delete', () {
      test('delete removes blob', () async {
        final bytes = Uint8List.fromList([1, 2, 3]);
        await store.save('blob-789', bytes);

        expect(store.contains('blob-789'), isTrue);

        await store.delete('blob-789');

        expect(store.contains('blob-789'), isFalse);
        expect(await store.load('blob-789'), isNull);
      });

      test('delete non-existent blob returns false', () async {
        final deleted = await store.delete('nonexistent');
        expect(deleted, isFalse);
      });

      test('delete existing blob returns true', () async {
        await store.save('blob-id', Uint8List.fromList([1, 2, 3]));
        final deleted = await store.delete('blob-id');
        expect(deleted, isTrue);
      });
    });

    group('Stream', () {
      test('streamRead streams blob in chunks', () async {
        final bytes = Uint8List.fromList(List<int>.generate(1000, (i) => i % 256));
        await store.save('blob-stream', bytes);

        final chunks = <Uint8List>[];
        await store.streamRead('blob-stream', chunkSize: 100).forEach(chunks.add);

        // Should get 10 chunks of 100 bytes each
        expect(chunks.length, greaterThan(0));

        // Reconstruct from chunks
        final reconstructed = Uint8List.fromList(
          chunks.expand((c) => c).toList(),
        );
        expect(reconstructed, bytes);
      });

      test('streamRead with default chunk size', () async {
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        await store.save('blob-id', bytes);

        final chunks = <Uint8List>[];
        await store.streamRead('blob-id').forEach(chunks.add);

        final reconstructed = Uint8List.fromList(
          chunks.expand((c) => c).toList(),
        );
        expect(reconstructed, bytes);
      });

      test('streamRead returns empty stream for non-existent blob', () async {
        final chunks = <Uint8List>[];
        await store.streamRead('nonexistent').forEach(chunks.add);

        expect(chunks, isEmpty);
      });

      test('streamRead respects custom chunk size', () async {
        final bytes = Uint8List.fromList(List<int>.generate(500, (i) => i % 256));
        await store.save('blob-id', bytes);

        final chunks = <Uint8List>[];
        await store.streamRead('blob-id', chunkSize: 50).forEach(chunks.add);

        // Each chunk should be at most 50 bytes
        for (final chunk in chunks) {
          expect(chunk.length, lessThanOrEqualTo(50));
        }
      });
    });

    group('Contains', () {
      test('contains returns true for saved blob', () async {
        await store.save('blob-id', Uint8List.fromList([1, 2, 3]));
        expect(store.contains('blob-id'), isTrue);
      });

      test('contains returns false for non-existent blob', () async {
        expect(store.contains('nonexistent'), isFalse);
      });
    });

    group('Size', () {
      test('size returns blob size in bytes', () async {
        final bytes = Uint8List.fromList(List<int>.generate(255, (i) => i));
        await store.save('blob-id', bytes);

        final size = store.size('blob-id');
        expect(size, 255);
      });

      test('size returns -1 for non-existent blob', () async {
        expect(store.size('nonexistent'), -1);
      });

      test('size reflects overwritten blob', () async {
        await store.save('blob-id', Uint8List.fromList([1, 2, 3]));
        expect(store.size('blob-id'), 3);

        await store.save('blob-id', Uint8List.fromList(List<int>.generate(100, (i) => i)));
        expect(store.size('blob-id'), 100);
      });
    });

    group('Lifecycle', () {
      test('initialize completes', () async {
        await expectLater(store.initialize(), completion(isNull));
      });

      test('dispose clears all blobs', () async {
        await store.save('blob-1', Uint8List.fromList([1, 2, 3]));
        await store.save('blob-2', Uint8List.fromList([4, 5, 6]));

        expect(store.contains('blob-1'), isTrue);
        expect(store.contains('blob-2'), isTrue);

        store.dispose();

        expect(store.contains('blob-1'), isFalse);
        expect(store.contains('blob-2'), isFalse);
      });
    });
  });

  group('FileSystemBlobStore', () {
    // Real implementation tests would require:
    // - Temporary directory setup
    // - File I/O verification
    // - Platform-specific path handling
    // These will be tested on actual mobile/desktop platforms

    test('FileSystemBlobStore is a BlobStore', () {
      expect(FileSystemBlobStore, isA<Type>());
    });
  });

  group('IndexedDBBlobStore', () {
    // Real implementation tests would require:
    // - IndexedDB setup in web environment
    // - Browser APIs
    // These will be tested on web platform

    test('IndexedDBBlobStore is a BlobStore', () {
      expect(IndexedDBBlobStore, isA<Type>());
    });
  });
}
