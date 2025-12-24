/// # Media Download Scenario Test
///
/// Feature: Extract YouTube Content Semantically
///
/// Gherkin Scenario:
/// ```gherkin
/// Scenario: User downloads a video from YouTube
///   When the user calls media.download with a YouTube URL
///   Then a download job is queued with:
///     | Field    | Value          |
///     | Format   | mp4            |
///     | Quality  | 720p           |
///     | Status   | queued         |
///   And the download is tracked for progress
///   And the user can check download status
/// ```
///
/// Implementation: Tests that media.download tool handler correctly creates
/// Download and MediaItem records, with proper status tracking.

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/core/persistence/persistence_adapter.dart';
import 'package:everything_stack_template/core/persistence/transaction_context.dart';
import 'package:everything_stack_template/tools/media/handlers/download_handler.dart';
import 'package:everything_stack_template/tools/media/repositories/download_repository.dart';
import 'package:everything_stack_template/tools/media/repositories/media_item_repository.dart';
import 'package:everything_stack_template/tools/media/repositories/channel_repository.dart';
import 'package:everything_stack_template/tools/media/entities/download.dart';
import 'package:everything_stack_template/tools/media/entities/media_item.dart';
import 'package:everything_stack_template/tools/media/entities/channel.dart';

void main() {
  group('Media Download Scenario', () {
    late DownloadHandler downloadHandler;
    late DownloadRepository downloadRepo;
    late MediaItemRepository mediaItemRepo;

    setUp(() {
      // Create in-memory test adapters
      downloadRepo = DownloadRepository(
        adapter: InMemoryAdapter<Download>(),
      );
      mediaItemRepo = MediaItemRepository(
        adapter: InMemoryAdapter<MediaItem>(),
      );

      // Create handler with repositories
      downloadHandler = DownloadHandler(
        mediaRepo: mediaItemRepo,
        downloadRepo: downloadRepo,
        channelRepo: ChannelRepository(
          adapter: InMemoryAdapter<Channel>(),
        ),
      );
    });

    test(
      'Scenario: User downloads a video from YouTube',
      () async {
        // WHEN: User calls media.download with a YouTube URL
        final result = await downloadHandler(
          {
            'youtubeUrl': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
            'format': 'mp4',
            'quality': '720p',
          },
        );

        // THEN: Download job is queued successfully
        expect(result['success'], true);
        expect(result['downloadId'], isNotNull);
        expect(result['mediaItemId'], isNotNull);

        // AND: The download exists with correct status
        final downloadId = result['downloadId'] as String;
        final download = await downloadRepo.findByUuid(downloadId);
        expect(download, isNotNull);
        expect(download!.status, 'queued');
        expect(download.format, 'mp4');
        expect(download.quality, '720p');

        // AND: The MediaItem exists with pending download status
        final mediaItemId = result['mediaItemId'] as String;
        final mediaItem = await mediaItemRepo.findByUuid(mediaItemId);
        expect(mediaItem, isNotNull);
        expect(mediaItem!.downloadStatus, 'pending');
        expect(mediaItem.youtubeUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');

        // AND: The download is tracked (download references mediaItem)
        expect(download.mediaItemId, mediaItemId);

        // AND: User can check download status
        final queuedDownloads = await downloadRepo.findQueued();
        expect(queuedDownloads.length, 1);
        expect(queuedDownloads.first.uuid, downloadId);
      },
    );

    // TODO: Implement remaining scenarios after YouTube DL integration
    // test(
    //   'Scenario: Downloaded video is organized by channel',
    //   () async {
    //     // GIVEN: A download completes for a video from a known channel
    //     // NOTE: This is a deferred scenario - requires YouTube DL integration
    //   },
    // );
  });
}

// In-memory adapter for testing - implements PersistenceAdapter
class InMemoryAdapter<T extends BaseEntity> implements PersistenceAdapter<T> {
  final Map<int, T> _byId = {};
  final Map<String, T> _byUuid = {};
  int _nextId = 1;

  @override
  Future<T?> findById(int id) async => _byId[id];

  @override
  Future<T> getById(int id) async {
    final entity = _byId[id];
    if (entity == null) throw Exception('Entity with id $id not found');
    return entity;
  }

  @override
  Future<T?> findByUuid(String uuid) async => _byUuid[uuid];

  @override
  Future<T> getByUuid(String uuid) async {
    final entity = _byUuid[uuid];
    if (entity == null) throw Exception('Entity with uuid $uuid not found');
    return entity;
  }

  @override
  Future<List<T>> findAll() async => _byId.values.toList();

  @override
  Future<T> save(T entity, {bool touch = true}) async {
    // Generate uuid if not present
    if (entity.uuid.isEmpty) {
      entity.uuid = Uuid().v4();
    }
    // Assign id if not present
    if (entity.id == null || entity.id == 0) {
      entity.id = _nextId++;
    }
    _byId[entity.id!] = entity;
    _byUuid[entity.uuid] = entity;
    return entity;
  }

  @override
  Future<List<T>> saveAll(List<T> entities) async {
    final result = <T>[];
    for (final entity in entities) {
      result.add(await save(entity));
    }
    return result;
  }

  @override
  Future<bool> delete(int id) async {
    final entity = _byId.remove(id);
    if (entity != null) {
      _byUuid.remove(entity.uuid);
      return true;
    }
    return false;
  }

  @override
  Future<bool> deleteByUuid(String uuid) async {
    final entity = _byUuid.remove(uuid);
    if (entity != null) {
      _byId.remove(entity.id);
      return true;
    }
    return false;
  }

  @override
  Future<void> deleteAll(List<int> ids) async {
    for (final id in ids) {
      await delete(id);
    }
  }

  @override
  Future<List<T>> findUnsynced() async {
    return _byId.values
        .where((entity) => entity.syncStatus.toString().contains('local'))
        .toList();
  }

  @override
  Future<int> count() async => _byId.length;

  @override
  Future<List<T>> semanticSearch(
    List<double> queryVector, {
    int limit = 10,
    double minSimilarity = 0.0,
  }) async {
    // Not implemented for mock
    return [];
  }

  @override
  int get indexSize => 0;

  @override
  Future<void> rebuildIndex(
    Future<List<double>?> Function(T entity) generateEmbedding,
  ) async {
    // Not implemented for mock
  }

  @override
  T? findByIdInTx(TransactionContext ctx, int id) => _byId[id];

  @override
  T? findByUuidInTx(TransactionContext ctx, String uuid) => _byUuid[uuid];

  @override
  List<T> findAllInTx(TransactionContext ctx) => _byId.values.toList();

  @override
  T saveInTx(TransactionContext ctx, T entity, {bool touch = true}) {
    if (entity.id == null) {
      entity.id = _nextId++;
    }
    _byId[entity.id!] = entity;
    _byUuid[entity.uuid] = entity;
    return entity;
  }

  @override
  List<T> saveAllInTx(TransactionContext ctx, List<T> entities) {
    final result = <T>[];
    for (final entity in entities) {
      result.add(saveInTx(ctx, entity));
    }
    return result;
  }

  @override
  bool deleteInTx(TransactionContext ctx, int id) {
    final entity = _byId.remove(id);
    if (entity != null) {
      _byUuid.remove(entity.uuid);
      return true;
    }
    return false;
  }

  @override
  bool deleteByUuidInTx(TransactionContext ctx, String uuid) {
    final entity = _byUuid.remove(uuid);
    if (entity != null) {
      _byId.remove(entity.id);
      return true;
    }
    return false;
  }

  @override
  void deleteAllInTx(TransactionContext ctx, List<int> ids) {
    for (final id in ids) {
      deleteInTx(ctx, id);
    }
  }

  @override
  Future<void> close() async {}
}
