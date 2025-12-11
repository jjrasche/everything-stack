/// # BlobStore Platform Verification Tests
///
/// Tests platform-specific implementations on actual platforms.
/// NOT BDD - technical validation only.
///
/// Layer 4 testing: Platform verification on Android, iOS, web, desktop.
///
/// Platform implementations tested:
/// - Android/iOS/Desktop: FileSystemBlobStore using path_provider
/// - Web: IndexedDBBlobStore using browser IndexedDB
library;

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:everything_stack_template/services/blob_store.dart';
import 'package:everything_stack_template/bootstrap/blob_store_factory_stub.dart'
    if (dart.library.io) 'package:everything_stack_template/bootstrap/blob_store_factory_io.dart'
    if (dart.library.html) 'package:everything_stack_template/bootstrap/blob_store_factory_web.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('BlobStore Platform Implementation', () {
    late BlobStore blobStore;

    setUp(() async {
      // Use REAL platform implementation via conditional import
      blobStore = createPlatformBlobStore();
      await blobStore.initialize();
    });

    tearDown(() {
      blobStore.dispose();
    });

    testWidgets('BlobStore initializes without error',
        (WidgetTester tester) async {
      // If we got here, initialization succeeded in setUp
      expect(blobStore, isNotNull);
    });

    testWidgets('BlobStore can save and load bytes',
        (WidgetTester tester) async {
      final testBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      const testId = 'platform-test-blob';

      // Save
      await blobStore.save(testId, testBytes);

      // Load
      final loaded = await blobStore.load(testId);

      // Verify
      expect(loaded, isNotNull);
      expect(loaded, equals(testBytes));

      // Cleanup
      await blobStore.delete(testId);
    });

    testWidgets('BlobStore can delete blobs', (WidgetTester tester) async {
      const testId = 'platform-test-delete';
      final testBytes = Uint8List.fromList([10, 20, 30]);

      // Save
      await blobStore.save(testId, testBytes);
      expect(blobStore.contains(testId), isTrue);

      // Delete
      final deleted = await blobStore.delete(testId);
      expect(deleted, isTrue);

      // Verify gone
      expect(blobStore.contains(testId), isFalse);

      // Load returns null
      final loaded = await blobStore.load(testId);
      expect(loaded, isNull);
    });

    testWidgets('BlobStore reports size correctly',
        (WidgetTester tester) async {
      const testId = 'platform-test-size';
      final testBytes = Uint8List.fromList(
        List<int>.filled(1024, 255),
      );

      // Save
      await blobStore.save(testId, testBytes);

      // Check size
      final size = blobStore.size(testId);
      expect(size, 1024);

      // Cleanup
      await blobStore.delete(testId);
    });

    testWidgets('BlobStore can stream large blobs',
        (WidgetTester tester) async {
      const testId = 'platform-test-stream';
      const testSize = 100 * 1024; // 100KB
      final testBytes = Uint8List.fromList(
        List<int>.filled(testSize, 128),
      );

      // Save
      await blobStore.save(testId, testBytes);

      // Stream with chunks
      int bytesRead = 0;
      await for (final chunk
          in blobStore.streamRead(testId, chunkSize: 8 * 1024)) {
        bytesRead += chunk.length;
      }

      // Verify all bytes were streamed
      expect(bytesRead, testSize);

      // Cleanup
      await blobStore.delete(testId);
    });

    testWidgets('BlobStore handles non-existent blobs gracefully',
        (WidgetTester tester) async {
      // Load non-existent
      final loaded = await blobStore.load('non-existent-uuid');
      expect(loaded, isNull);

      // Delete non-existent
      final deleted = await blobStore.delete('non-existent-uuid');
      expect(deleted, isFalse);

      // Size of non-existent
      final size = blobStore.size('non-existent-uuid');
      expect(size, -1);

      // Contains non-existent
      expect(blobStore.contains('non-existent-uuid'), isFalse);
    });

    testWidgets('Multiple sequential saves and loads work correctly',
        (WidgetTester tester) async {
      final testData = {
        'file-1': Uint8List.fromList([1, 2, 3]),
        'file-2': Uint8List.fromList([4, 5, 6]),
        'file-3': Uint8List.fromList([7, 8, 9]),
      };

      // Save all
      for (final entry in testData.entries) {
        await blobStore.save(entry.key, entry.value);
      }

      // Load all and verify
      for (final entry in testData.entries) {
        final loaded = await blobStore.load(entry.key);
        expect(loaded, equals(entry.value), reason: 'Failed for ${entry.key}');
      }

      // Cleanup
      for (final key in testData.keys) {
        await blobStore.delete(key);
      }
    });

    testWidgets('BlobStore persists data across instances',
        (WidgetTester tester) async {
      const testId = 'platform-test-persist';
      final testBytes = Uint8List.fromList([42, 43, 44, 45]);

      // Save with first instance
      await blobStore.save(testId, testBytes);

      // Dispose first instance
      blobStore.dispose();

      // Create new instance
      final secondBlobStore = createPlatformBlobStore();
      await secondBlobStore.initialize();

      // Load from second instance - this proves REAL persistence
      final loaded = await secondBlobStore.load(testId);
      expect(loaded, isNotNull, reason: 'Data should persist across instances');
      expect(loaded, equals(testBytes));

      // Cleanup
      await secondBlobStore.delete(testId);
      secondBlobStore.dispose();

      // Restore original for tearDown
      blobStore = createPlatformBlobStore();
      await blobStore.initialize();
    });

    testWidgets('BlobStore can handle medium binary data (1MB)',
        (WidgetTester tester) async {
      const testId = 'platform-test-medium';
      // 1MB of data - reasonable for integration test
      final testBytes = Uint8List.fromList(
        List.generate(
          1 * 1024 * 1024,
          (i) => (i * 7) % 256, // Pseudo-random pattern
        ),
      );

      // Save
      await blobStore.save(testId, testBytes);

      // Load and verify size
      final loaded = await blobStore.load(testId);
      expect(loaded?.length, testBytes.length);

      // Spot check some bytes
      expect(loaded?[0], testBytes[0]);
      expect(loaded?[1000], testBytes[1000]);
      expect(loaded?[testBytes.length - 1], testBytes[testBytes.length - 1]);

      // Cleanup
      await blobStore.delete(testId);
    });
  });
}
