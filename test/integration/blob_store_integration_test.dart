/// # BlobStore Integration Tests
///
/// Tests how FileService, BlobStore, and FileStorable work together.
/// Validates the complete flow: pick file → save to blob store → retrieve → stream.
///
/// Layer 2 testing: Cross-service workflows on Dart VM using mocks.

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/blob_store.dart';
import 'package:everything_stack_template/services/file_service.dart';
import 'package:everything_stack_template/patterns/file_storable.dart';

void main() {
  group('FileService + BlobStore Integration', () {
    late MockFileService fileService;
    late MockBlobStore blobStore;

    setUp(() {
      fileService = MockFileService();
      blobStore = MockBlobStore();
    });

    group('Photo picking and storing', () {
      test('pickPhoto returns metadata with UUID suitable for blob storage',
          () async {
        // Given: File service ready
        await fileService.initialize();
        await blobStore.initialize();

        // When: Pick a photo
        final metadata =
            await fileService.pickPhoto(source: PhotoSource.gallery);

        // Then: Metadata is suitable for storage
        expect(metadata, isNotNull);
        expect(metadata!.uuid, isNotEmpty);
        expect(metadata.filename, contains('.jpg'));
        expect(metadata.mimeType, 'image/jpeg');
        expect(metadata.sizeBytes, greaterThan(0));
        expect(metadata.thumbnailBase64, isNotNull);
      });

      test(
          'Complete workflow: pick photo → save to blob → verify contains → load → stream',
          () async {
        // Setup
        await fileService.initialize();
        await blobStore.initialize();

        // When: Pick photo
        final metadata =
            await fileService.pickPhoto(source: PhotoSource.gallery);
        expect(metadata, isNotNull);

        // Given: Generate some mock photo bytes
        final photoBytes = Uint8List.fromList(
          List<int>.filled(1024, 255), // Mock photo data
        );

        // When: Save to blob store
        await blobStore.save(metadata!.uuid, photoBytes);

        // Then: Blob is stored
        expect(blobStore.contains(metadata.uuid), isTrue);
        expect(blobStore.size(metadata.uuid), 1024);

        // When: Load from blob store
        final loaded = await blobStore.load(metadata.uuid);

        // Then: Loaded bytes match original
        expect(loaded, isNotNull);
        expect(loaded, equals(photoBytes));
      });

      test('Can stream large photo from blob store with chunks', () async {
        // Setup
        await fileService.initialize();
        await blobStore.initialize();

        // Create mock large photo (100KB)
        final photoBytes = Uint8List.fromList(
          List<int>.filled(100 * 1024, 128),
        );
        const testUuid = 'photo-uuid-123';

        // When: Save large photo
        await blobStore.save(testUuid, photoBytes);

        // When: Stream with small chunks
        final chunks = <Uint8List>[];
        const chunkSize = 8 * 1024; // 8KB chunks
        await for (final chunk
            in blobStore.streamRead(testUuid, chunkSize: chunkSize)) {
          chunks.add(chunk);
        }

        // Then: Got multiple chunks
        expect(chunks, isNotEmpty);
        expect(chunks.length,
            greaterThan(1)); // 100KB with 8KB chunks = 12-13 chunks

        // Then: Chunks reconstruct original
        final reconstructed = Uint8List.fromList(
          chunks.expand((c) => c).toList(),
        );
        expect(reconstructed, equals(photoBytes));
      });
    });

    group('Video picking and storing', () {
      test('pickVideo → save → stream workflow', () async {
        // Setup
        await fileService.initialize();
        await blobStore.initialize();

        // When: Pick video
        final metadata =
            await fileService.pickVideo(source: VideoSource.gallery);
        expect(metadata, isNotNull);

        // Given: Mock video bytes
        final videoBytes = Uint8List.fromList(
          List<int>.filled(5000, 200),
        );

        // When: Save to blob store
        await blobStore.save(metadata!.uuid, videoBytes);

        // When: Stream back
        final loaded = await blobStore.load(metadata.uuid);

        // Then: Bytes match
        expect(loaded, equals(videoBytes));
      });
    });

    group('Audio recording and storing', () {
      test('recordAudio → save → verify workflow', () async {
        // Setup
        await fileService.initialize();
        await blobStore.initialize();

        // When: Record audio
        final metadata = await fileService.recordAudio();
        expect(metadata, isNotNull);

        // Given: Audio should not have thumbnail
        expect(metadata!.thumbnailBase64, isNull);

        // Given: Mock audio bytes
        final audioBytes = Uint8List.fromList(
          List<int>.filled(2000, 100),
        );

        // When: Save to blob store
        await blobStore.save(metadata.uuid, audioBytes);

        // Then: Stored correctly
        expect(blobStore.contains(metadata.uuid), isTrue);

        // When: Load
        final loaded = await blobStore.load(metadata.uuid);

        // Then: Bytes match
        expect(loaded, equals(audioBytes));
      });
    });

    group('FileStorable integration', () {
      test('Entity with FileStorable can manage multiple attachments', () {
        // Create mock entity with file storage capability
        final attachments = <FileMetadata>[];

        // Simulate addAttachment via FileStorable mixin
        final photo = FileMetadata(
          uuid: 'photo-1',
          filename: 'photo.jpg',
          mimeType: 'image/jpeg',
          sizeBytes: 2048,
          thumbnailBase64: 'data:image/jpeg;base64,abc123==',
        );
        attachments.add(photo);

        final audio = FileMetadata(
          uuid: 'audio-1',
          filename: 'note.m4a',
          mimeType: 'audio/mp4',
          sizeBytes: 512,
        );
        attachments.add(audio);

        // Verify we can query attachments
        expect(attachments.length, 2);
        expect(
          attachments.where((m) => m.isImage).length,
          1,
        );
        expect(
          attachments.where((m) => m.isAudio).length,
          1,
        );

        // Verify total size calculation
        final totalSize =
            attachments.fold<int>(0, (sum, m) => sum + m.sizeBytes);
        expect(totalSize, 2560); // 2048 + 512
      });

      test('FileMetadata type detection works correctly', () {
        final imageMetadata = FileMetadata(
          uuid: 'img-1',
          filename: 'image.png',
          mimeType: 'image/png',
          sizeBytes: 1024,
        );
        expect(imageMetadata.isImage, isTrue);
        expect(imageMetadata.isAudio, isFalse);
        expect(imageMetadata.isVideo, isFalse);

        final audioMetadata = FileMetadata(
          uuid: 'aud-1',
          filename: 'sound.mp3',
          mimeType: 'audio/mpeg',
          sizeBytes: 5000,
        );
        expect(audioMetadata.isAudio, isTrue);
        expect(audioMetadata.isImage, isFalse);
        expect(audioMetadata.isVideo, isFalse);

        final videoMetadata = FileMetadata(
          uuid: 'vid-1',
          filename: 'movie.mp4',
          mimeType: 'video/mp4',
          sizeBytes: 50000,
        );
        expect(videoMetadata.isVideo, isTrue);
        expect(videoMetadata.isImage, isFalse);
        expect(videoMetadata.isAudio, isFalse);
      });
    });

    group('Error handling and edge cases', () {
      test('Cannot load non-existent blob', () async {
        await blobStore.initialize();

        final result = await blobStore.load('non-existent-uuid');

        expect(result, isNull);
      });

      test('Cannot delete non-existent blob', () async {
        await blobStore.initialize();

        final deleted = await blobStore.delete('non-existent-uuid');

        expect(deleted, isFalse);
      });

      test('Can delete and then verify not contains', () async {
        await blobStore.initialize();

        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        const testUuid = 'temp-uuid';

        // Save
        await blobStore.save(testUuid, bytes);
        expect(blobStore.contains(testUuid), isTrue);

        // Delete
        final deleted = await blobStore.delete(testUuid);
        expect(deleted, isTrue);

        // Verify gone
        expect(blobStore.contains(testUuid), isFalse);
      });

      test('Cancelling photo pick returns null', () async {
        await fileService.initialize();

        // Trigger cancellation
        fileService.setCancelNextPick();

        final metadata =
            await fileService.pickPhoto(source: PhotoSource.gallery);

        expect(metadata, isNull);
      });

      test('File service dispose can be called', () async {
        await fileService.initialize();

        // dispose() is synchronous
        fileService.dispose();
      });

      test('Blob store dispose can be called', () async {
        await blobStore.initialize();

        // dispose() is synchronous
        blobStore.dispose();
      });
    });
  });

  group('FileService + FileStorable + BlobStore Full Workflow', () {
    late MockFileService fileService;
    late MockBlobStore blobStore;

    setUp(() {
      fileService = MockFileService();
      blobStore = MockBlobStore();
    });

    test('Complete user flow: create attachment, store, retrieve, delete',
        () async {
      // Initialize services
      await fileService.initialize();
      await blobStore.initialize();

      // User picks multiple files
      final photo = await fileService.pickPhoto(source: PhotoSource.gallery);
      final video = await fileService.pickVideo(source: VideoSource.gallery);
      final audio = await fileService.recordAudio();

      expect(photo, isNotNull);
      expect(video, isNotNull);
      expect(audio, isNotNull);

      // Simulate storing in blob store (FileService would return bytes separately)
      final mockPhotoBytes = Uint8List.fromList(List.filled(1024, 255));
      final mockVideoBytes = Uint8List.fromList(List.filled(5000, 200));
      final mockAudioBytes = Uint8List.fromList(List.filled(512, 100));

      await blobStore.save(photo!.uuid, mockPhotoBytes);
      await blobStore.save(video!.uuid, mockVideoBytes);
      await blobStore.save(audio!.uuid, mockAudioBytes);

      // Verify all stored
      expect(blobStore.contains(photo.uuid), isTrue);
      expect(blobStore.contains(video.uuid), isTrue);
      expect(blobStore.contains(audio.uuid), isTrue);

      // Entity has metadata and references blobs
      final attachments = [photo, video, audio];
      expect(attachments.length, 3);
      expect(attachments.where((m) => m.isImage).length, 1);
      expect(attachments.where((m) => m.isVideo).length, 1);
      expect(attachments.where((m) => m.isAudio).length, 1);

      // Calculate total size of attachments
      final totalSize = attachments.fold<int>(0, (sum, m) => sum + m.sizeBytes);
      expect(totalSize, greaterThan(0));

      // User deletes a file
      final deleted = await blobStore.delete(audio.uuid);
      expect(deleted, isTrue);

      // Attachment is gone
      expect(blobStore.contains(audio.uuid), isFalse);

      // Others remain
      expect(blobStore.contains(photo.uuid), isTrue);
      expect(blobStore.contains(video.uuid), isTrue);
    });
  });
}
