/// # FileService Tests
///
/// Tests for file input, processing, and storage operations.
/// - File picking (photo, video, audio, documents)
/// - Image compression and thumbnail generation
/// - MIME type detection
/// - BlobStore integration (bytes auto-stored)
/// - Audio recording with start/stop pattern

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/blob_store.dart';
import 'package:everything_stack_template/services/file_service.dart';

void main() {
  group('FileService interface', () {
    test('FileService is abstract', () {
      expect(FileService, isA<Type>());
    });

    test('MockFileService is default instance', () {
      final blobStore = MockBlobStore();
      FileService.instance = MockFileService(blobStore: blobStore);
      expect(FileService.instance, isA<MockFileService>());
    });
  });

  group('MockFileService', () {
    late MockFileService service;
    late MockBlobStore blobStore;

    setUp(() async {
      blobStore = MockBlobStore();
      await blobStore.initialize();
      service = MockFileService(blobStore: blobStore);
      await service.initialize();
    });

    group('Photo picking', () {
      test('pickPhoto from gallery returns FileMetadata', () async {
        final result = await service.pickPhoto(source: PhotoSource.gallery);

        expect(result, isNotNull);
        expect(result!.filename, contains('.jpg'));
        expect(result.mimeType, 'image/jpeg');
        expect(result.sizeBytes, greaterThan(0));
      });

      test('pickPhoto from camera returns FileMetadata', () async {
        final result = await service.pickPhoto(source: PhotoSource.camera);

        expect(result, isNotNull);
        expect(result!.mimeType, 'image/jpeg');
      });

      test('pickPhoto returns null when cancelled', () async {
        service.setCancelNextPick();
        final result = await service.pickPhoto(source: PhotoSource.gallery);

        expect(result, isNull);
      });

      test('pickPhoto includes thumbnail for images', () async {
        final result = await service.pickPhoto(source: PhotoSource.gallery);

        expect(result!.thumbnailBase64, isNotNull);
        expect(result.thumbnailBase64, startsWith('data:image/'));
      });

      test('pickPhoto stores bytes to BlobStore', () async {
        final result = await service.pickPhoto(source: PhotoSource.gallery);

        expect(result, isNotNull);
        expect(blobStore.contains(result!.uuid), isTrue);

        final storedBytes = await blobStore.load(result.uuid);
        expect(storedBytes, isNotNull);
        expect(storedBytes!.length, result.sizeBytes);
      });
    });

    group('Video picking', () {
      test('pickVideo from gallery returns FileMetadata', () async {
        final result = await service.pickVideo(source: VideoSource.gallery);

        expect(result, isNotNull);
        expect(result!.filename, contains('.mp4'));
        expect(result.mimeType, 'video/mp4');
        expect(result.sizeBytes, greaterThan(0));
      });

      test('pickVideo from camera returns FileMetadata', () async {
        final result = await service.pickVideo(source: VideoSource.camera);

        expect(result, isNotNull);
        expect(result!.mimeType, 'video/mp4');
      });

      test('pickVideo returns null when cancelled', () async {
        service.setCancelNextPick();
        final result = await service.pickVideo(source: VideoSource.gallery);

        expect(result, isNull);
      });

      test('pickVideo stores bytes to BlobStore', () async {
        final result = await service.pickVideo(source: VideoSource.gallery);

        expect(result, isNotNull);
        expect(blobStore.contains(result!.uuid), isTrue);

        final storedBytes = await blobStore.load(result.uuid);
        expect(storedBytes, isNotNull);
        expect(storedBytes!.length, result.sizeBytes);
      });
    });

    group('Audio recording with duration', () {
      test('recordAudio with duration returns FileMetadata', () async {
        final result =
            await service.recordAudio(duration: const Duration(seconds: 5));

        expect(result, isNotNull);
        expect(result!.filename, contains('.m4a'));
        expect(result.mimeType, 'audio/mp4');
        expect(result.sizeBytes, greaterThan(0));
      });

      test('recordAudio returns null when cancelled', () async {
        service.setCancelNextPick();
        final result =
            await service.recordAudio(duration: const Duration(seconds: 1));

        expect(result, isNull);
      });

      test('recordAudio has no thumbnail', () async {
        final result =
            await service.recordAudio(duration: const Duration(seconds: 1));

        expect(result!.thumbnailBase64, isNull);
      });

      test('recordAudio stores bytes to BlobStore', () async {
        final result =
            await service.recordAudio(duration: const Duration(seconds: 5));

        expect(result, isNotNull);
        expect(blobStore.contains(result!.uuid), isTrue);

        final storedBytes = await blobStore.load(result.uuid);
        expect(storedBytes, isNotNull);
        expect(storedBytes!.length, result.sizeBytes);
      });
    });

    group('Audio recording with start/stop', () {
      test('startRecording returns true when idle', () async {
        final started = await service.startRecording();
        expect(started, isTrue);
        expect(service.recordingState, RecordingState.recording);

        // Clean up
        await service.stopRecording();
      });

      test('startRecording returns false when already recording', () async {
        await service.startRecording();
        final secondStart = await service.startRecording();

        expect(secondStart, isFalse);

        // Clean up
        await service.stopRecording();
      });

      test('stopRecording returns FileMetadata when recording', () async {
        await service.startRecording();

        // Small delay to simulate recording
        await Future.delayed(const Duration(milliseconds: 50));

        final result = await service.stopRecording();

        expect(result, isNotNull);
        expect(result!.filename, contains('.m4a'));
        expect(result.mimeType, 'audio/mp4');
        expect(service.recordingState, RecordingState.idle);
      });

      test('stopRecording returns null when not recording', () async {
        final result = await service.stopRecording();
        expect(result, isNull);
      });

      test('stopRecording stores bytes to BlobStore', () async {
        await service.startRecording();
        await Future.delayed(const Duration(milliseconds: 50));

        final result = await service.stopRecording();

        expect(result, isNotNull);
        expect(blobStore.contains(result!.uuid), isTrue);
      });
    });

    group('File picking', () {
      test('pickFile returns FileMetadata for documents', () async {
        final result = await service.pickFile();

        expect(result, isNotNull);
        expect(result!.mimeType, isNotEmpty);
        expect(result.sizeBytes, greaterThan(0));
      });

      test('pickFile returns null when cancelled', () async {
        service.setCancelNextPick();
        final result = await service.pickFile();

        expect(result, isNull);
      });

      test('pickFile can pick specific file types', () async {
        final result = await service.pickFile(allowedTypes: ['pdf', 'doc']);

        expect(result, isNotNull);
        expect(result!.filename, contains('.pdf'));
      });

      test('pickFile stores bytes to BlobStore', () async {
        final result = await service.pickFile();

        expect(result, isNotNull);
        expect(blobStore.contains(result!.uuid), isTrue);

        final storedBytes = await blobStore.load(result.uuid);
        expect(storedBytes, isNotNull);
        expect(storedBytes!.length, result.sizeBytes);
      });
    });

    group('Image compression', () {
      test('compress reduces image bytes', () async {
        final originalBytes = Uint8List.fromList([
          137, 80, 78, 71, 13, 10, 26, 10, // PNG header
          ...List<int>.filled(1000, 255), // Mock image data
        ]);

        final compressed = await service.compress(originalBytes, quality: 80);

        expect(compressed, isNotNull);
        expect(compressed!.length, lessThanOrEqualTo(originalBytes.length));
      });

      test('compress with lower quality produces smaller output', () async {
        final bytes = Uint8List.fromList(List<int>.filled(2000, 128));

        final high = await service.compress(bytes, quality: 90);
        final low = await service.compress(bytes, quality: 40);

        expect(low!.length, lessThanOrEqualTo(high!.length));
      });

      test('compress returns null for invalid input', () async {
        final result = await service.compress(Uint8List(0), quality: 80);

        expect(result, isNull);
      });
    });

    group('Thumbnail generation', () {
      test('generateThumbnail returns base64 encoded data URI', () async {
        final bytes = Uint8List.fromList([
          137, 80, 78, 71, 13, 10, 26, 10, // PNG header
          ...List<int>.filled(500, 255),
        ]);

        final thumbnail = await service.generateThumbnail(bytes, width: 200);

        expect(thumbnail, isNotNull);
        expect(thumbnail, startsWith('data:image/'));
        expect(thumbnail, contains(';base64,'));
      });

      test('generateThumbnail returns null for invalid input', () async {
        final result =
            await service.generateThumbnail(Uint8List(0), width: 200);

        expect(result, isNull);
      });

      test('generateThumbnail respects width parameter', () async {
        final bytes = Uint8List.fromList(List<int>.filled(1000, 200));

        final thumb200 = await service.generateThumbnail(bytes, width: 200);
        final thumb100 = await service.generateThumbnail(bytes, width: 100);

        expect(thumb200, startsWith('data:image/'));
        expect(thumb100, startsWith('data:image/'));
      });
    });

    group('MIME type detection', () {
      test('detectMimeType recognizes common image formats', () {
        expect(service.detectMimeType('photo.jpg'), 'image/jpeg');
        expect(service.detectMimeType('image.png'), 'image/png');
        expect(service.detectMimeType('pic.gif'), 'image/gif');
        expect(service.detectMimeType('pic.webp'), 'image/webp');
      });

      test('detectMimeType recognizes audio formats', () {
        expect(service.detectMimeType('song.mp3'), 'audio/mpeg');
        expect(service.detectMimeType('audio.wav'), 'audio/wav');
        expect(service.detectMimeType('sound.m4a'), 'audio/mp4');
      });

      test('detectMimeType recognizes video formats', () {
        expect(service.detectMimeType('video.mp4'), 'video/mp4');
        expect(service.detectMimeType('clip.mov'), 'video/quicktime');
        expect(service.detectMimeType('movie.avi'), 'video/x-msvideo');
      });

      test('detectMimeType recognizes document formats', () {
        expect(service.detectMimeType('document.pdf'), 'application/pdf');
        expect(service.detectMimeType('sheet.xlsx'),
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        expect(service.detectMimeType('doc.docx'),
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
      });

      test('detectMimeType is case insensitive', () {
        expect(service.detectMimeType('photo.JPG'), 'image/jpeg');
        expect(service.detectMimeType('SONG.MP3'), 'audio/mpeg');
      });

      test('detectMimeType returns default for unknown', () {
        final result = service.detectMimeType('unknown.xyz');
        expect(result, 'application/octet-stream');
      });
    });

    group('Lifecycle', () {
      test('initialize completes', () async {
        final newService = MockFileService(blobStore: MockBlobStore());
        await expectLater(newService.initialize(), completes);
      });

      test('dispose completes', () async {
        await expectLater(service.dispose(), completes);
      });

      test('blobStore is accessible', () {
        expect(service.blobStore, isNotNull);
        expect(service.blobStore, same(blobStore));
      });
    });
  });

  group('BlobStore integration', () {
    late MockFileService service;
    late MockBlobStore blobStore;

    setUp(() async {
      blobStore = MockBlobStore();
      await blobStore.initialize();
      service = MockFileService(blobStore: blobStore);
      await service.initialize();
    });

    test('multiple files are stored with unique UUIDs', () async {
      final photo1 = await service.pickPhoto();
      final photo2 = await service.pickPhoto();
      final video = await service.pickVideo();

      expect(photo1!.uuid, isNot(photo2!.uuid));
      expect(photo2.uuid, isNot(video!.uuid));

      expect(blobStore.contains(photo1.uuid), isTrue);
      expect(blobStore.contains(photo2.uuid), isTrue);
      expect(blobStore.contains(video.uuid), isTrue);
    });

    test('stored bytes can be retrieved and streamed', () async {
      final photo = await service.pickPhoto();

      // Load full bytes
      final bytes = await blobStore.load(photo!.uuid);
      expect(bytes, isNotNull);
      expect(bytes!.length, photo.sizeBytes);

      // Stream bytes
      final chunks = <Uint8List>[];
      await for (final chunk
          in blobStore.streamRead(photo.uuid, chunkSize: 512)) {
        chunks.add(chunk);
      }

      final reassembled = Uint8List.fromList(chunks.expand((c) => c).toList());
      expect(reassembled.length, photo.sizeBytes);
    });

    test('deleting from BlobStore removes file bytes', () async {
      final file = await service.pickFile();

      expect(blobStore.contains(file!.uuid), isTrue);

      await blobStore.delete(file.uuid);

      expect(blobStore.contains(file.uuid), isFalse);
      expect(await blobStore.load(file.uuid), isNull);
    });
  });
}
