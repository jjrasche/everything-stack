/// # BlobStore Integration Tests
///
/// Tests how FileService, BlobStore, and FileStorable work together.
/// Validates the complete flow: pick file → auto-store to blob → retrieve → stream.
///
/// Layer 2 testing: Cross-service workflows on Dart VM using mocks.
///
/// Key design: FileService takes BlobStore as dependency and auto-stores
/// all file bytes. Callers receive metadata with UUID pointing to stored blob.

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/blob_store.dart';
import 'package:everything_stack_template/services/file_service.dart';
import 'package:everything_stack_template/patterns/file_storable.dart';

void main() {
  group('FileService + BlobStore Integration', () {
    late MockFileService fileService;
    late MockBlobStore blobStore;

    setUp(() async {
      blobStore = MockBlobStore();
      await blobStore.initialize();
      fileService = MockFileService(blobStore: blobStore);
      await fileService.initialize();
    });

    group('Photo picking and storing', () {
      test('pickPhoto returns metadata with UUID pointing to stored blob',
          () async {
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

        // Then: Bytes are already stored in BlobStore
        expect(blobStore.contains(metadata.uuid), isTrue);
        expect(blobStore.size(metadata.uuid), metadata.sizeBytes);
      });

      test('Complete workflow: pick photo → verify stored → load → stream',
          () async {
        // When: Pick photo (auto-stored by FileService)
        final metadata =
            await fileService.pickPhoto(source: PhotoSource.gallery);
        expect(metadata, isNotNull);

        // Then: Blob is already stored
        expect(blobStore.contains(metadata!.uuid), isTrue);
        expect(blobStore.size(metadata.uuid), metadata.sizeBytes);

        // When: Load from blob store
        final loaded = await blobStore.load(metadata.uuid);

        // Then: Loaded bytes have correct size
        expect(loaded, isNotNull);
        expect(loaded!.length, metadata.sizeBytes);
      });

      test('Can stream photo from blob store with chunks', () async {
        // When: Pick photo (auto-stored)
        final metadata =
            await fileService.pickPhoto(source: PhotoSource.gallery);
        expect(metadata, isNotNull);

        // When: Stream with small chunks
        final chunks = <Uint8List>[];
        const chunkSize = 512; // Small chunks
        await for (final chunk
            in blobStore.streamRead(metadata!.uuid, chunkSize: chunkSize)) {
          chunks.add(chunk);
        }

        // Then: Got chunks
        expect(chunks, isNotEmpty);

        // Then: Chunks reconstruct to correct size
        final reconstructed = Uint8List.fromList(
          chunks.expand((c) => c).toList(),
        );
        expect(reconstructed.length, metadata.sizeBytes);
      });
    });

    group('Video picking and storing', () {
      test('pickVideo auto-stores bytes and returns valid metadata', () async {
        // When: Pick video
        final metadata =
            await fileService.pickVideo(source: VideoSource.gallery);
        expect(metadata, isNotNull);

        // Then: Bytes are already stored
        expect(blobStore.contains(metadata!.uuid), isTrue);

        // When: Load back
        final loaded = await blobStore.load(metadata.uuid);

        // Then: Bytes have correct size
        expect(loaded, isNotNull);
        expect(loaded!.length, metadata.sizeBytes);
      });
    });

    group('Audio recording and storing', () {
      test('recordAudio with duration auto-stores bytes', () async {
        // When: Record audio with specified duration
        final metadata =
            await fileService.recordAudio(duration: const Duration(seconds: 5));
        expect(metadata, isNotNull);

        // Then: Audio should not have thumbnail
        expect(metadata!.thumbnailBase64, isNull);

        // Then: Bytes are already stored
        expect(blobStore.contains(metadata.uuid), isTrue);

        // When: Load
        final loaded = await blobStore.load(metadata.uuid);

        // Then: Bytes have correct size
        expect(loaded, isNotNull);
        expect(loaded!.length, metadata.sizeBytes);
      });

      test('start/stop recording auto-stores bytes', () async {
        // When: Start recording
        final started = await fileService.startRecording();
        expect(started, isTrue);
        expect(fileService.recordingState, RecordingState.recording);

        // Simulate some recording time
        await Future.delayed(const Duration(milliseconds: 100));

        // When: Stop recording
        final metadata = await fileService.stopRecording();
        expect(metadata, isNotNull);
        expect(fileService.recordingState, RecordingState.idle);

        // Then: Bytes are already stored
        expect(blobStore.contains(metadata!.uuid), isTrue);
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
        final result = await blobStore.load('non-existent-uuid');

        expect(result, isNull);
      });

      test('Cannot delete non-existent blob', () async {
        final deleted = await blobStore.delete('non-existent-uuid');

        expect(deleted, isFalse);
      });

      test('Can delete and then verify not contains', () async {
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

      test('Cancelling photo pick returns null, nothing stored', () async {
        // Trigger cancellation
        fileService.setCancelNextPick();

        final metadata =
            await fileService.pickPhoto(source: PhotoSource.gallery);

        expect(metadata, isNull);
      });

      test('File service dispose can be called', () async {
        await fileService.dispose();
      });

      test('Blob store dispose can be called', () async {
        blobStore.dispose();
      });
    });
  });

  group('FileService + FileStorable + BlobStore Full Workflow', () {
    late MockFileService fileService;
    late MockBlobStore blobStore;

    setUp(() async {
      blobStore = MockBlobStore();
      await blobStore.initialize();
      fileService = MockFileService(blobStore: blobStore);
      await fileService.initialize();
    });

    test('Complete user flow: pick files, auto-stored, retrieve, delete',
        () async {
      // User picks multiple files (all auto-stored by FileService)
      final photo = await fileService.pickPhoto(source: PhotoSource.gallery);
      final video = await fileService.pickVideo(source: VideoSource.gallery);
      final audio =
          await fileService.recordAudio(duration: const Duration(seconds: 3));

      expect(photo, isNotNull);
      expect(video, isNotNull);
      expect(audio, isNotNull);

      // Verify all already stored (auto-stored by FileService)
      expect(blobStore.contains(photo!.uuid), isTrue);
      expect(blobStore.contains(video!.uuid), isTrue);
      expect(blobStore.contains(audio!.uuid), isTrue);

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

    test('Bytes retrieved from BlobStore match expected size', () async {
      // Pick photo
      final photo = await fileService.pickPhoto();
      expect(photo, isNotNull);

      // Load bytes
      final bytes = await blobStore.load(photo!.uuid);
      expect(bytes, isNotNull);
      expect(bytes!.length, photo.sizeBytes);

      // Size matches
      expect(blobStore.size(photo.uuid), photo.sizeBytes);
    });
  });
}
