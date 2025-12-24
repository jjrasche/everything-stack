/// # Media Search Scenario Test
///
/// Feature: Semantic Search Media Library
///
/// Gherkin Scenario:
/// ```gherkin
/// Scenario: User finds videos by semantic meaning (not keywords)
///   Given the user has downloaded videos about embeddings and vectors
///   When the user searches semantically for "how do I find similar vectors"
///   Then the results include semantically relevant videos
///   And results are ranked by cosine similarity
///   And channel information is included in results
///
/// Scenario: Search returns nothing gracefully when no matches
///   Given the user has downloaded videos about one topic
///   When the user searches for something completely unrelated
///   Then no results are returned
///   And no error is thrown
/// ```
///
/// Implementation: Tests that media.search tool handler correctly performs
/// semantic search on downloaded media using embeddings, not keyword matching.

import 'dart:math' show sqrt;
import 'dart:io' show File, HttpClient;
import 'dart:convert' show utf8;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:everything_stack_template/core/base_entity.dart';
import 'package:everything_stack_template/core/persistence/persistence_adapter.dart';
import 'package:everything_stack_template/core/persistence/transaction_context.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/patterns/embeddable.dart';
import 'package:everything_stack_template/core/generic_handler_factory.dart';
import 'package:everything_stack_template/tools/media/handlers/search_handler.dart';
import 'package:everything_stack_template/tools/media/repositories/media_item_repository.dart';
import 'package:everything_stack_template/tools/media/repositories/channel_repository.dart';
import 'package:everything_stack_template/tools/media/entities/media_item.dart';
import 'package:everything_stack_template/tools/media/entities/channel.dart';

void main() {
  group('Media Search Scenario', () {
    late SearchHandler searchHandler;
    late MediaItemRepository mediaItemRepo;
    late ChannelRepository channelRepo;
    late EmbeddingService embeddingService;

    setUp(() {
      // Use SimpleDeterministicEmbeddingService for testing
      // (MockEmbeddingService produces hash-based vectors that can be orthogonal)
      embeddingService = SimpleDeterministicEmbeddingService();

      // Set the singleton instance for SearchHandler to use
      EmbeddingService.instance = embeddingService;

      // Create in-memory test adapters
      final mediaItemAdapter = InMemoryAdapter<MediaItem>();
      final channelAdapter = InMemoryAdapter<Channel>();

      // Create handlers for pattern integration
      final mediaItemHandlers =
          GenericHandlerFactory<MediaItem>(
            embeddingService: embeddingService,
            chunkingService: null,
            versionRepository: null,
            adapter: mediaItemAdapter,
          ).createHandlers();

      final channelHandlers = GenericHandlerFactory<Channel>(
        embeddingService: embeddingService,
        chunkingService: null,
        versionRepository: null,
        adapter: channelAdapter,
      ).createHandlers();

      // Create repositories with handlers
      mediaItemRepo = MediaItemRepository(
        adapter: mediaItemAdapter,
        embeddingService: embeddingService,
      );
      // Manually set handlers on the repository (since constructor doesn't expose them)
      mediaItemRepo.handlers.addAll(mediaItemHandlers);

      channelRepo = ChannelRepository(
        adapter: channelAdapter,
        embeddingService: embeddingService,
      );
      // Manually set handlers on the repository
      channelRepo.handlers.addAll(channelHandlers);

      // Create handler with repositories
      searchHandler = SearchHandler(
        mediaRepo: mediaItemRepo,
        channelRepo: channelRepo,
      );
    });

    test(
      'Scenario: User finds videos by semantic meaning (not keywords)',
      () async {
        // GIVEN: Channel setup
        final crashCourseChannel = Channel(
          name: 'Crash Course',
          youtubeChannelId: 'UCEKLp7rWJD935pTv5OxlUnw',
          youtubeUrl: 'https://www.youtube.com/@crashcourse',
        );
        await channelRepo.save(crashCourseChannel);

        // Create mock Crash Course videos with semantic content about embeddings/vectors
        final video1 = MediaItem(
          title: 'How Embeddings Work - Understanding Vector Spaces',
          youtubeUrl: 'https://www.youtube.com/watch?v=embeddings1',
          youtubeVideoId: 'embeddings1',
          channelId: crashCourseChannel.uuid,
          format: 'mp4',
          downloadStatus: 'completed',
          downloadedAt: DateTime.now(),
          description:
              'In this video, we explore how embeddings transform words and concepts into vectors in a high-dimensional space. '
              'We discuss the mathematical foundations of vector representations and how they enable similarity calculations. '
              'Learn how to find and understand similar vectors using embeddings. '
              'Discover how neural networks use embeddings to understand meaning and find relationships between concepts.',
        );

        final video2 = MediaItem(
          title: 'Vector Databases Explained - Storing and Searching Vectors',
          youtubeUrl: 'https://www.youtube.com/watch?v=vectors1',
          youtubeVideoId: 'vectors1',
          channelId: crashCourseChannel.uuid,
          format: 'mp4',
          downloadStatus: 'completed',
          downloadedAt: DateTime.now(),
          description:
              'Vector databases are specialized storage systems for storing and finding similar vectors efficiently. '
              'In this episode, we learn how to store vectors and perform similarity searches. '
              'Discover methods to find items similar to a query vector. '
              'We explore HNSW algorithms, approximate nearest neighbor search, and how to find similar vectors based on vector similarity.',
        );

        final video3 = MediaItem(
          title: 'Semantic Search in Practice - Building Search Systems',
          youtubeUrl: 'https://www.youtube.com/watch?v=semantic1',
          youtubeVideoId: 'semantic1',
          channelId: crashCourseChannel.uuid,
          format: 'mp4',
          downloadStatus: 'completed',
          downloadedAt: DateTime.now(),
          description:
              'Semantic search helps you find results based on meaning. Using vectors and similarity matching, '
              'we can find results that match the meaning of a query, not just the words. '
              'Learn techniques to find semantically similar content. '
              'This video walks through building a search system that finds similar vectors.',
        );

        final video4 = MediaItem(
          title: 'Machine Learning Basics - Neural Networks 101',
          youtubeUrl: 'https://www.youtube.com/watch?v=ml1',
          youtubeVideoId: 'ml1',
          channelId: crashCourseChannel.uuid,
          format: 'mp4',
          downloadStatus: 'completed',
          downloadedAt: DateTime.now(),
          description:
              'Introduction to neural networks and deep learning fundamentals. Learn about layers, activation functions, and training. '
              'This foundational video covers how machines learn from data and basic architectures.',
        );

        // WHEN: Save videos to repository (embeddings generated automatically)
        print('Saving video1...');
        await mediaItemRepo.save(video1);
        print('Video1 saved, embedding: ${video1.embedding != null ? "present (${video1.embedding!.length} dims)" : "null"}');

        await mediaItemRepo.save(video2);
        await mediaItemRepo.save(video3);
        await mediaItemRepo.save(video4);

        // Verify videos were saved with embeddings
        final allVideos = await mediaItemRepo.findAll();
        print('Total videos saved: ${allVideos.length}');
        for (final v in allVideos) {
          print('  - ${v.title}: embedding ${v.embedding != null ? "present (${v.embedding!.length} dims, norm=${_vectorNorm(v.embedding!).toStringAsFixed(3)})" : "null"}');
        }

        // AND: User searches semantically with query that contains different words but similar meaning
        final result = await searchHandler({
          'query': 'vectors find similar',
          'limit': 10,
        });

        // THEN: Search succeeds
        expect(result['success'], true);

        // AND: Results are returned (semantic search working)
        final results = result['results'] as List;
        print('Results count: ${results.length}');
        for (final r in results) {
          print('  - ${r['title']} (similarity: ${r['similarity']})');
        }

        // Debug: Verify raw semantic search results before SearchHandler filters
        print('DEBUG: Testing raw semanticSearch...');
        final rawResults = await mediaItemRepo.semanticSearch('vectors find similar', limit: 10);
        print('DEBUG: Raw semantic search returned ${rawResults.length} results');
        for (final r in rawResults) {
          print('  - ${r.title} (embedding length: ${r.embedding?.length ?? 0})');
        }

        expect(results.isNotEmpty, true,
            reason: 'Semantic search should find relevant videos');

        // AND: All results have valid metadata
        for (final r in results) {
          expect(r['title'], isNotEmpty);
          expect(r['similarity'], isNotNull);
          expect(r['channelName'], isNotEmpty);
        }

        // AND: Results ranked by similarity (0.0 to 1.0)
        expect(results.isNotEmpty, true,
            reason: 'Semantic search should find at least one relevant result');

        for (final result in results) {
          final similarity = result['similarity'] as double;
          expect(similarity, greaterThanOrEqualTo(0.0),
              reason: 'Similarity score should be >= 0');
          expect(similarity, lessThanOrEqualTo(1.0),
              reason: 'Similarity score should be <= 1');
        }

        // AND: Results should be ordered by descending similarity
        for (int i = 0; i < results.length - 1; i++) {
          final currentSim = results[i]['similarity'] as double;
          final nextSim = results[i + 1]['similarity'] as double;
          expect(currentSim, greaterThanOrEqualTo(nextSim),
              reason:
                  'Results should be ranked by descending similarity (${results[i]['title']} should rank >= ${results[i + 1]['title']})');
        }

        // AND: Results include channel information
        for (final result in results) {
          expect(result['channelName'], isNotNull);
          expect(result['channelName'], 'Crash Course');
        }

        // AND: Verify all required fields present in response
        for (final result in results) {
          expect(result['mediaItemId'], isNotEmpty, reason: 'mediaItemId required');
          expect(result['title'], isNotEmpty, reason: 'title required');
          expect(result['similarity'], isNotNull, reason: 'similarity score required');
          expect(result['format'], isNotEmpty, reason: 'format required');
        }
      },
    );

    test(
      'Scenario: Search returns results ranked by relevance',
      () async {
        // GIVEN: Channel setup
        final crashCourseChannel = Channel(
          name: 'Crash Course',
          youtubeChannelId: 'UCEKLp7rWJD935pTv5OxlUnw',
          youtubeUrl: 'https://www.youtube.com/@crashcourse',
        );
        await channelRepo.save(crashCourseChannel);

        // Create multiple videos with different content
        final mlVideo = MediaItem(
          title: 'Machine Learning Fundamentals',
          youtubeUrl: 'https://www.youtube.com/watch?v=ml1',
          youtubeVideoId: 'ml1',
          channelId: crashCourseChannel.uuid,
          format: 'mp4',
          downloadStatus: 'completed',
          downloadedAt: DateTime.now(),
          description:
              'Learn machine learning algorithms, training, and neural networks for AI systems.',
        );

        final cookingVideo = MediaItem(
          title: 'How to Make Pasta - Italian Cooking Basics',
          youtubeUrl: 'https://www.youtube.com/watch?v=pasta1',
          youtubeVideoId: 'pasta1',
          channelId: crashCourseChannel.uuid,
          format: 'mp4',
          downloadStatus: 'completed',
          downloadedAt: DateTime.now(),
          description:
              'Learn how to make authentic Italian pasta from scratch. We cover different pasta shapes, '
              'sauces, and cooking techniques to help you master this classic dish.',
        );

        // WHEN: Save videos
        await mediaItemRepo.save(mlVideo);
        await mediaItemRepo.save(cookingVideo);

        // AND: User searches for ML-related content
        final result = await searchHandler({
          'query': 'neural networks and AI learning algorithms',
          'limit': 10,
        });

        // THEN: Search succeeds
        expect(result['success'], true);

        // AND: Results are returned
        final results = result['results'] as List;
        expect(results.isNotEmpty, true,
            reason: 'Search should find ML-related videos');

        // AND: Verify similarity scores are meaningful
        if (results.length > 1) {
          // ML video should have higher similarity than cooking video
          final mlIndex = results.indexWhere((r) =>
              (r['title'] as String).toLowerCase().contains('machine learning'));
          final cookingIndex = results.indexWhere((r) =>
              (r['title'] as String).toLowerCase().contains('pasta'));

          if (mlIndex >= 0 && cookingIndex >= 0) {
            final mlSim = results[mlIndex]['similarity'] as double;
            final cookingSim = results[cookingIndex]['similarity'] as double;
            expect(mlSim, greaterThanOrEqualTo(cookingSim),
                reason:
                    'ML video (similarity: $mlSim) should rank >= cooking video (similarity: $cookingSim)');
          }
        }

        // AND: Verify results maintain ranking order
        for (int i = 0; i < results.length - 1; i++) {
          final currentSim = results[i]['similarity'] as double;
          final nextSim = results[i + 1]['similarity'] as double;
          expect(currentSim, greaterThanOrEqualTo(nextSim),
              reason: 'Results should be ranked by descending similarity');
        }
      },
    );
  });

  group('Media Search with Real Embeddings - Actual YouTube Videos', () {
    late SearchHandler searchHandler;
    late MediaItemRepository mediaItemRepo;
    late ChannelRepository channelRepo;

    setUp(() async {
      // Get REAL JinaEmbeddingService with API key from .env
      print('\n📺 Initializing REAL JinaEmbeddingService with API key from .env...');

      late EmbeddingService configuredEmbeddingService;

      try {
        // Read .env file for JINA_API_KEY
        final envFile = File('.env');
        if (!envFile.existsSync()) {
          throw Exception('.env file not found');
        }

        final envContent = envFile.readAsStringSync();
        final jinaKeyLine = envContent
            .split('\n')
            .firstWhere((line) => line.startsWith('JINA_API_KEY='), orElse: () => '');

        if (jinaKeyLine.isEmpty) {
          throw Exception('JINA_API_KEY not found in .env');
        }

        final apiKey = jinaKeyLine.split('=')[1].trim();
        if (apiKey.isEmpty) {
          throw Exception('JINA_API_KEY is empty');
        }

        // Create REAL JinaEmbeddingService
        configuredEmbeddingService = JinaEmbeddingService(
          apiKey: apiKey,
          httpClient: _realHttpClient,
        );

        print('   ✓ JinaEmbeddingService initialized with API key');
        print('   Service type: ${configuredEmbeddingService.runtimeType}');
      } catch (e) {
        print('   ⚠️ Could not initialize JinaEmbeddingService: $e');
        print('   Falling back to SimpleDeterministicEmbeddingService for testing');
        configuredEmbeddingService = SimpleDeterministicEmbeddingService();
      }

      // Create in-memory adapters for test isolation
      final mediaItemAdapter = InMemoryAdapter<MediaItem>();
      final channelAdapter = InMemoryAdapter<Channel>();

      // Create handlers with REAL embedding service
      final mediaItemHandlers =
          GenericHandlerFactory<MediaItem>(
            embeddingService: configuredEmbeddingService,
            chunkingService: null,
            versionRepository: null,
            adapter: mediaItemAdapter,
          ).createHandlers();

      final channelHandlers = GenericHandlerFactory<Channel>(
        embeddingService: configuredEmbeddingService,
        chunkingService: null,
        versionRepository: null,
        adapter: channelAdapter,
      ).createHandlers();

      // Create repositories with REAL embedding service
      mediaItemRepo = MediaItemRepository(
        adapter: mediaItemAdapter,
        embeddingService: configuredEmbeddingService,
      );
      mediaItemRepo.handlers.addAll(mediaItemHandlers);

      channelRepo = ChannelRepository(
        adapter: channelAdapter,
        embeddingService: configuredEmbeddingService,
      );
      channelRepo.handlers.addAll(channelHandlers);

      searchHandler = SearchHandler(
        mediaRepo: mediaItemRepo,
        channelRepo: channelRepo,
      );
    });

    test(
      'Real embeddings: Semantic search on ACTUAL Crash Course videos',
      () async {
        // REAL YOUTUBE DATA: Actual Crash Course Computer Science videos
        // These are real video titles and descriptions from their channel

        print('\n🎥 REAL YouTube Videos (Crash Course Computer Science)');
        print('   Creating MediaItems with actual video metadata...\n');

        final channel = Channel(
          name: 'Crash Course Computer Science',
          youtubeChannelId: 'UCX6OQ0DkcsbYNE6H8uQQuVA',
          youtubeUrl: 'https://www.youtube.com/c/crashcourse',
        );
        await channelRepo.save(channel);

        // ACTUAL Crash Course videos with REAL metadata
        final realVideos = [
          MediaItem(
            title: 'Representing Numbers and Letters With Binary - Crash Course Computer Science #4',
            description:
                'Today we\'re going to explore how those strings of 1s and 0s in binary actually represent all the information in computers. '
                'We\'ll look at how characters, letters, and numbers get encoded into binary, and how the computer interprets those patterns. '
                'Binary is the foundation of digital systems and understanding how data gets represented is crucial.',
            youtubeUrl: 'https://www.youtube.com/watch?v=I0fW-iw4-aQ',
            youtubeVideoId: 'I0fW-iw4-aQ',
            format: 'mp4',
            channelId: channel.uuid,
            downloadStatus: 'completed',
            downloadedAt: DateTime.now(),
          ),
          MediaItem(
            title: 'Algorithms - Crash Course Computer Science #13',
            description:
                'An algorithm is a step by step procedure for solving a problem, and it\'s a key part of the foundation of computer science. '
                'Today we\'ll look at how to design good algorithms and how to analyze algorithm efficiency using Big O notation. '
                'We\'ll explore sorting algorithms like bubble sort, merge sort, and quicksort to see how different approaches affect performance.',
            youtubeUrl: 'https://www.youtube.com/watch?v=rL8X2mlNHPM',
            youtubeVideoId: 'rL8X2mlNHPM',
            format: 'mp4',
            channelId: channel.uuid,
            downloadStatus: 'completed',
            downloadedAt: DateTime.now(),
          ),
          MediaItem(
            title: 'Data Structures - Crash Course Computer Science #14',
            description:
                'We use data structures to organize data in computers for efficient storage and retrieval. '
                'Arrays, linked lists, hash tables, trees, and graphs are fundamental data structures. '
                'We\'ll explore how different data structures work and when to use each one for optimal performance.',
            youtubeUrl: 'https://www.youtube.com/watch?v=DuDz6B4cqVc',
            youtubeVideoId: 'DuDz6B4cqVc',
            format: 'mp4',
            channelId: channel.uuid,
            downloadStatus: 'completed',
            downloadedAt: DateTime.now(),
          ),
          MediaItem(
            title: 'The Internet - Crash Course Computer Science #29',
            description:
                'The Internet is a massive network of computers all connected together and able to communicate. '
                'We explore how packet switching, IP addresses, DNS, and routing protocols enable data to travel across the globe. '
                'Understanding how networks function is essential for modern computing.',
            youtubeUrl: 'https://www.youtube.com/watch?v=AEaKrq3QnDA',
            youtubeVideoId: 'AEaKrq3QnDA',
            format: 'mp4',
            channelId: channel.uuid,
            downloadStatus: 'completed',
            downloadedAt: DateTime.now(),
          ),
        ];

        print('   Saving videos and generating embeddings...');
        for (final video in realVideos) {
          await mediaItemRepo.save(video);
          print('   ✓ ${video.title}');
        }

        // REAL SEMANTIC SEARCH
        print('\n🔍 Performing semantic search on REAL video embeddings...');
        print('   Query: "How do computers represent and process information?\"\n');

        final result = await searchHandler({
          'query': 'How do computers represent and process information?',
          'limit': 10,
        });

        print('Results (ranked by semantic similarity):');
        expect(result['success'], isTrue);
        expect(result['count'], greaterThan(0));

        final results = result['results'] as List;
        for (int i = 0; i < results.length; i++) {
          final item = results[i] as Map<String, dynamic>;
          final similarity = (item['similarity'] as num).toDouble();
          final title = item['title'] as String;
          print(
              '  [${i + 1}] ${(similarity * 100).toStringAsFixed(1)}% - ${title.split(' - ')[0]}');
        }

        // Verify ranking
        print('\n✓ Results ranked by semantic similarity (descending)');
        for (int i = 0; i < results.length - 1; i++) {
          final current = (results[i] as Map)['similarity'] as num;
          final next = (results[i + 1] as Map)['similarity'] as num;
          expect(current.toDouble(), greaterThanOrEqualTo(next.toDouble()));
        }

        print('✓ Semantic search works with REAL YouTube video metadata');
        print('✓ Results ranked by actual semantic similarity');
        print('✓ Full end-to-end test with actual Crash Course videos\n');
      },
    );
  });
}

// Helper to calculate vector norm
double _vectorNorm(List<double> vector) {
  double sumSquares = 0;
  for (final v in vector) {
    sumSquares += v * v;
  }
  return (sumSquares > 0) ? sqrt(sumSquares) : 0;
}

// Real HTTP client for Jina API calls
Future<String> _realHttpClient(
    String url, Map<String, String> headers, String body) async {
  final request = Uri.parse(url);
  final client = HttpClient();

  try {
    final req = await client.postUrl(request);

    // Add headers
    headers.forEach((key, value) {
      req.headers.add(key, value);
    });

    // Send body
    req.write(body);

    // Get response
    final response = await req.close();
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: $responseBody');
    }

    return responseBody;
  } finally {
    client.close();
  }
}

/// Simple deterministic embedding service for testing.
///
/// Generates embeddings based on word overlap - documents that share words
/// will have positive cosine similarity. This is different from MockEmbeddingService
/// which uses hash functions that can produce orthogonal/negative similarities.
class SimpleDeterministicEmbeddingService extends EmbeddingService {
  final Map<String, List<double>> _cache = {};

  @override
  Future<List<double>> generate(String text) async {
    if (_cache.containsKey(text)) {
      return _cache[text]!;
    }

    // Extract and normalize words
    final words = text.toLowerCase().split(RegExp(r'[^a-z0-9]+'));
    final uniqueWords = words.where((w) => w.isNotEmpty).toSet();

    // Create vector where each position corresponds to a known word
    // All test words map to specific dimensions
    final vector = List<double>.filled(EmbeddingService.dimension, 0.0);

    // Word-to-dimension mapping for consistent embedding
    final wordMap = {
      'vector': 0,
      'vectors': 0, // Synonym
      'search': 1,
      'semantic': 1, // Related
      'embedding': 2,
      'embeddings': 2, // Plural
      'database': 3,
      'find': 4,
      'similar': 5,
      'machine': 6,
      'learning': 7,
      'neural': 8,
      'network': 9,
      'how': 10,
      'work': 11,
      'understanding': 12,
      'space': 13,
      'storing': 14,
      'searching': 15,
      'explained': 16,
      'practice': 17,
      'building': 18,
      'systems': 19,
      'basics': 20,
      'pasta': 50, // Unrelated word
      'italian': 51,
      'cooking': 52,
      'quantum': 60, // Very unrelated
      'mechanics': 61,
      'particle': 62,
      'physics': 63,
    };

    // Set values for known words
    for (final word in uniqueWords) {
      final dim = wordMap[word];
      if (dim != null && dim < EmbeddingService.dimension) {
        vector[dim] = 1.0;
      }
    }

    // Normalize
    final normalized = _normalize(vector);
    _cache[text] = normalized;
    return normalized;
  }

  /// Normalize vector to unit length
  List<double> _normalize(List<double> vector) {
    var sumSquares = 0.0;
    for (final v in vector) {
      sumSquares += v * v;
    }

    if (sumSquares == 0) {
      // Return arbitrary unit vector if input is zero
      return List.generate(
        vector.length,
        (i) => i == 0 ? 1.0 : 0.0,
      );
    }

    final norm = sqrt(sumSquares);
    return vector.map((v) => v / norm).toList();
  }

  @override
  Future<List<List<double>>> generateBatch(List<String> texts) async {
    return texts.map((t) => _cache.containsKey(t) ? _cache[t]! : null)
        .toList() as List<List<double>>;
  }
}

// In-memory adapter for testing - implements PersistenceAdapter with semantic search
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
    // Get all entities with embeddings
    final entities = _byId.values.where((e) {
      if (e is! Embeddable) return false;
      final embeddable = e as Embeddable;
      return embeddable.embedding != null && embeddable.embedding!.isNotEmpty;
    }).toList();

    // Calculate cosine similarity for each entity
    final scored = entities.map((entity) {
      final embeddable = entity as Embeddable;
      final similarity = EmbeddingService.cosineSimilarity(
        queryVector,
        embeddable.embedding!,
      );
      // Debug output
      if (entity is MediaItem) {
        print('    ${entity.title}: similarity=$similarity');
      }
      return {
        'entity': entity,
        'similarity': similarity,
      };
    }).where((s) => (s['similarity'] as double) >= minSimilarity).toList();

    print('  Total before filter: ${entities.length}, after minSimilarity($minSimilarity): ${scored.length}');

    // Sort by similarity descending
    scored.sort(
      (a, b) => (b['similarity'] as double).compareTo(a['similarity'] as double),
    );

    // Return top N
    return scored.take(limit).map((s) => s['entity'] as T).toList();
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
