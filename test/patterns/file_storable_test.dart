/// # FileStorable Pattern Tests
///
/// Tests for entities with file attachments.
/// - FileMetadata class
/// - FileStorable mixin
/// - Attachment management

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/patterns/file_storable.dart';

void main() {
  group('FileMetadata', () {
    test('FileMetadata stores all required fields', () {
      final uuid = 'file-uuid-123';
      final filename = 'document.pdf';
      final mimeType = 'application/pdf';
      final size = 1024;
      final thumbnailBase64 = 'data:image/jpeg;base64,abc123==';
      final now = DateTime.now();

      final metadata = FileMetadata(
        uuid: uuid,
        filename: filename,
        mimeType: mimeType,
        sizeBytes: size,
        thumbnailBase64: thumbnailBase64,
      );

      expect(metadata.uuid, uuid);
      expect(metadata.filename, filename);
      expect(metadata.mimeType, mimeType);
      expect(metadata.sizeBytes, size);
      expect(metadata.thumbnailBase64, thumbnailBase64);
      expect(metadata.createdAt, now);
    });

    test('FileMetadata thumbnailBase64 can be null', () {
      final metadata = FileMetadata(
        uuid: 'uuid',
        filename: 'file.bin',
        mimeType: 'application/octet-stream',
        sizeBytes: 500,
      );

      expect(metadata.thumbnailBase64, isNull);
    });

    test('FileMetadata isImage returns true for image MIME types', () {
      final jpegMetadata = FileMetadata(
        uuid: 'uuid',
        filename: 'photo.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: 2000,
      );

      final pngMetadata = FileMetadata(
        uuid: 'uuid',
        filename: 'image.png',
        mimeType: 'image/png',
        sizeBytes: 2000,
      );

      final pdfMetadata = FileMetadata(
        uuid: 'uuid',
        filename: 'doc.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 2000,
      );

      expect(jpegMetadata.isImage, isTrue);
      expect(pngMetadata.isImage, isTrue);
      expect(pdfMetadata.isImage, isFalse);
    });

    test('FileMetadata isAudio returns true for audio MIME types', () {
      final audioMetadata = FileMetadata(
        uuid: 'uuid',
        filename: 'recording.mp3',
        mimeType: 'audio/mpeg',
        sizeBytes: 5000,
      );

      final videoMetadata = FileMetadata(
        uuid: 'uuid',
        filename: 'video.mp4',
        mimeType: 'video/mp4',
        sizeBytes: 50000,
      );

      expect(audioMetadata.isAudio, isTrue);
      expect(videoMetadata.isAudio, isFalse);
    });

    test('FileMetadata isVideo returns true for video MIME types', () {
      final videoMetadata = FileMetadata(
        uuid: 'uuid',
        filename: 'clip.mp4',
        mimeType: 'video/mp4',
        sizeBytes: 50000,
      );

      final audioMetadata = FileMetadata(
        uuid: 'uuid',
        filename: 'sound.wav',
        mimeType: 'audio/wav',
        sizeBytes: 5000,
      );

      expect(videoMetadata.isVideo, isTrue);
      expect(audioMetadata.isVideo, isFalse);
    });
  });

  group('FileStorable mixin', () {
    late TestEntity entity;

    setUp(() {
      entity = TestEntity();
    });

    group('Attachment management', () {
      test('entity starts with empty attachments list', () {
        expect(entity.attachments, isEmpty);
      });

      test('addAttachment adds file metadata', () {
        final metadata = FileMetadata(
          uuid: 'uuid-1',
          filename: 'file.txt',
          mimeType: 'text/plain',
          sizeBytes: 100,
        );

        entity.addAttachment(metadata);

        expect(entity.attachments.length, 1);
        expect(entity.attachments.first.uuid, 'uuid-1');
      });

      test('addAttachment adds multiple attachments', () {
        final meta1 = FileMetadata(
          uuid: 'uuid-1',
          filename: 'file1.txt',
          mimeType: 'text/plain',
          sizeBytes: 100,
        );
        final meta2 = FileMetadata(
          uuid: 'uuid-2',
          filename: 'file2.txt',
          mimeType: 'text/plain',
          sizeBytes: 200,
        );

        entity.addAttachment(meta1);
        entity.addAttachment(meta2);

        expect(entity.attachments.length, 2);
        expect(entity.attachments.map((m) => m.uuid), ['uuid-1', 'uuid-2']);
      });

      test('removeAttachment by uuid removes matching attachment', () {
        final meta1 = FileMetadata(
          uuid: 'uuid-1',
          filename: 'file1.txt',
          mimeType: 'text/plain',
          sizeBytes: 100,
        );
        final meta2 = FileMetadata(
          uuid: 'uuid-2',
          filename: 'file2.txt',
          mimeType: 'text/plain',
          sizeBytes: 200,
        );

        entity.addAttachment(meta1);
        entity.addAttachment(meta2);
        expect(entity.attachments.length, 2);

        entity.removeAttachment('uuid-1');

        expect(entity.attachments.length, 1);
        expect(entity.attachments.first.uuid, 'uuid-2');
      });

      test('removeAttachment returns true if found', () {
        final meta = FileMetadata(
          uuid: 'uuid-1',
          filename: 'file.txt',
          mimeType: 'text/plain',
          sizeBytes: 100,
        );

        entity.addAttachment(meta);
        final removed = entity.removeAttachment('uuid-1');

        expect(removed, isTrue);
      });

      test('removeAttachment returns false if not found', () {
        final removed = entity.removeAttachment('nonexistent');
        expect(removed, isFalse);
      });

      test('getAttachment returns matching attachment', () {
        final meta = FileMetadata(
          uuid: 'uuid-1',
          filename: 'file.txt',
          mimeType: 'text/plain',
          sizeBytes: 100,
        );

        entity.addAttachment(meta);
        final retrieved = entity.getAttachment('uuid-1');

        expect(retrieved, isNotNull);
        expect(retrieved!.filename, 'file.txt');
      });

      test('getAttachment returns null if not found', () {
        final retrieved = entity.getAttachment('nonexistent');
        expect(retrieved, isNull);
      });
    });

    group('Attachment queries', () {
      test('hasAttachments returns true when attachments exist', () {
        expect(entity.hasAttachments, isFalse);

        entity.addAttachment(
          FileMetadata(
            uuid: 'uuid-1',
            filename: 'file.jpg',
            mimeType: 'image/jpeg',
            sizeBytes: 1000,
          ),
        );

        expect(entity.hasAttachments, isTrue);
      });

      test('hasAttachments returns false when empty', () {
        entity.addAttachment(
          FileMetadata(
            uuid: 'uuid-1',
            filename: 'file.jpg',
            mimeType: 'image/jpeg',
            sizeBytes: 1000,
          ),
        );

        entity.removeAttachment('uuid-1');
        expect(entity.hasAttachments, isFalse);
      });

      test('imageAttachments returns only image files', () {
        entity.addAttachment(
          FileMetadata(
            uuid: 'uuid-1',
            filename: 'photo.jpg',
            mimeType: 'image/jpeg',
            sizeBytes: 2000,
          ),
        );
        entity.addAttachment(
          FileMetadata(
            uuid: 'uuid-2',
            filename: 'audio.mp3',
            mimeType: 'audio/mpeg',
            sizeBytes: 5000,
          ),
        );

        final images = entity.imageAttachments;

        expect(images.length, 1);
        expect(images.first.filename, 'photo.jpg');
      });

      test('audioAttachments returns only audio files', () {
        entity.addAttachment(
          FileMetadata(
            uuid: 'uuid-1',
            filename: 'recording.wav',
            mimeType: 'audio/wav',
            sizeBytes: 5000,
          ),
        );
        entity.addAttachment(
          FileMetadata(
            uuid: 'uuid-2',
            filename: 'video.mp4',
            mimeType: 'video/mp4',
            sizeBytes: 50000,
          ),
        );

        final audio = entity.audioAttachments;

        expect(audio.length, 1);
        expect(audio.first.filename, 'recording.wav');
      });

      test('videoAttachments returns only video files', () {
        entity.addAttachment(
          FileMetadata(
            uuid: 'uuid-1',
            filename: 'clip.mp4',
            mimeType: 'video/mp4',
            sizeBytes: 50000,
          ),
        );
        entity.addAttachment(
          FileMetadata(
            uuid: 'uuid-2',
            filename: 'image.png',
            mimeType: 'image/png',
            sizeBytes: 2000,
          ),
        );

        final videos = entity.videoAttachments;

        expect(videos.length, 1);
        expect(videos.first.filename, 'clip.mp4');
      });

      test('totalAttachmentSize returns sum of all sizes', () {
        entity.addAttachment(
          FileMetadata(
            uuid: 'uuid-1',
            filename: 'file1.txt',
            mimeType: 'text/plain',
            sizeBytes: 1000,
          ),
        );
        entity.addAttachment(
          FileMetadata(
            uuid: 'uuid-2',
            filename: 'file2.txt',
            mimeType: 'text/plain',
            sizeBytes: 2000,
          ),
        );

        expect(entity.totalAttachmentSize, 3000);
      });

      test('totalAttachmentSize returns 0 when empty', () {
        expect(entity.totalAttachmentSize, 0);
      });
    });
  });
}

/// Test entity with FileStorable
class TestEntity with FileStorable {
  String name = 'test';
}
