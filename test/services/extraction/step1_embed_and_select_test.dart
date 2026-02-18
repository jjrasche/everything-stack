/// Step 1: Embed and select golden conversations.
///
/// Two independent tests:
///
///   Step 1a — Embed (runs Jina API, costs ~960K tokens):
///     flutter test test/services/extraction/step1_embed_and_select_test.dart --name="embed"
///
///   Step 1b — Select (reads cached embeddings, free, rerunnable):
///     flutter test test/services/extraction/step1_embed_and_select_test.dart --name="select"
///
/// Reads:  ObjectBox store (imported conversations)
/// Writes: lib/training/extraction/golden/selection/all_embeddings.json     (Step 1a — cached)
///         lib/training/extraction/golden/selection/selected_conversations.json  (Step 1b)
///         lib/training/extraction/golden/selection/selected_conversations.csv   (Step 1b)

import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/objectbox.g.dart';
import 'package:everything_stack_template/persistence/objectbox/wrappers/invocation_ob.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/jina_embedding_service_impl.dart';
import 'package:everything_stack_template/services/math/kmeans.dart';

/// Minimum turns to include a conversation in golden selection.
const int minTurnCount = 3;

/// Number of clusters for k-means.
const int clusterCount = 10;

/// Conversations selected per cluster.
const int selectionsPerCluster = 3;

/// Jina embedding batch size (API limit).
const int embeddingBatchSize = 50;

/// Path to cached embeddings (all 2,413 conversations).
const String embeddingCachePath = 'lib/training/extraction/golden/selection/all_embeddings.json';

/// Path to selected conversations output.
const String selectionOutputPath =
    'lib/training/extraction/golden/selection/selected_conversations.json';

void main() {
  test('Step 1a: embed all conversations (Jina API)', () async {
    final cacheFile = File(embeddingCachePath);
    if (await cacheFile.exists()) {
      final existing = jsonDecode(await cacheFile.readAsString())
          as Map<String, dynamic>;
      final count = (existing['conversations'] as List).length;
      print('Cache already exists with $count conversations.');
      print('Delete $embeddingCachePath to re-embed.');
      return;
    }

    await dotenv.load(fileName: '.env');
    final jinaKey = dotenv.env['JINA_API_KEY'] ?? '';
    expect(jinaKey, isNotEmpty, reason: 'JINA_API_KEY required in .env');

    final store = await _openStore();
    final embeddingService = createJinaEmbeddingService(jinaKey);

    try {
      final conversations = _queryConversations(store);
      final filtered = _filterByMinTurns(conversations, minTurnCount);
      print('Conversations with >= $minTurnCount turns: ${filtered.length}');

      final embeddingInputs = _buildEmbeddingInputs(filtered);
      final embeddings = await _embedInBatches(
        embeddingService,
        embeddingInputs,
        embeddingBatchSize,
      );

      await _writeEmbeddingCache(filtered, embeddings);
      expect(embeddings.length, filtered.length);
    } finally {
      store.close();
    }
  });

  test('Step 1b: select from cached embeddings (free, rerunnable)', () async {
    final cache = await _loadEmbeddingCache();
    print('Loaded ${cache.length} cached conversation embeddings');

    final embeddings =
        cache.map((c) => (c['embedding'] as List).cast<double>()).toList();

    final clusterResult = clusterVectors(
      vectors: embeddings,
      k: clusterCount,
      seed: 42,
    );

    _printClusterSummary(cache, clusterResult);

    final selected = _selectFromClusters(
      cache,
      clusterResult,
      selectionsPerCluster,
    );
    print('\nSelected ${selected.length} conversations for golden dataset');

    await _writeSelectedJson(selected, cache, clusterResult);
    await _writeSelectedCsv(selected, cache, clusterResult);

    expect(selected.length, greaterThan(0));
  });
}

// ============ Query ============

Map<String, List<InvocationOB>> _queryConversations(Store store) {
  final box = store.box<InvocationOB>();
  final query = box.query(
    InvocationOB_.implementer.equals('claude_import'),
  ).build();
  final allInvocations = query.find();
  query.close();
  print('Total imported turns: ${allInvocations.length}');

  final grouped = <String, List<InvocationOB>>{};
  for (final inv in allInvocations) {
    final metadata = _parseJson(inv.metadataJson);
    final convUuid = metadata['sourceConversationUuid'] as String?;
    if (convUuid != null) {
      grouped.putIfAbsent(convUuid, () => []).add(inv);
    }
  }
  print('Total conversations: ${grouped.length}');
  return grouped;
}

// ============ Filter ============

List<Map<String, dynamic>> _filterByMinTurns(
  Map<String, List<InvocationOB>> conversations,
  int minTurns,
) {
  final records = <Map<String, dynamic>>[];

  for (final entry in conversations.entries) {
    if (entry.value.length < minTurns) continue;

    final turns = entry.value;
    final firstTurn = turns.first;
    final lastTurn = turns.last;
    final metadata = _parseJson(firstTurn.metadataJson);

    final firstInput = _parseJson(firstTurn.inputJson);
    final firstOutput = _parseJson(firstTurn.outputJson);
    final lastInput = _parseJson(lastTurn.inputJson);

    int totalChars = 0;
    DateTime mostRecent = turns.first.createdAt;
    for (final turn in turns) {
      totalChars += _countTurnChars(turn);
      if (turn.createdAt.isAfter(mostRecent)) mostRecent = turn.createdAt;
    }

    records.add({
      'convUuid': entry.key,
      'convName': metadata['sourceConversationName'] as String? ?? 'Unnamed',
      'turnCount': turns.length,
      'estimatedTokens': (totalChars / 4).ceil(),
      'mostRecentTurnDate': mostRecent.toIso8601String(),
      'firstUserQuery': firstInput['prompt']?.toString() ?? '',
      'firstAssistantResponse': firstOutput['response']?.toString() ?? '',
      'lastUserQuery': lastInput['prompt']?.toString() ?? '',
    });
  }

  return records;
}

// ============ Embedding ============

List<String> _buildEmbeddingInputs(List<Map<String, dynamic>> conversations) {
  return conversations.map((conv) {
    final buffer = StringBuffer();
    buffer.writeln(conv['convName']);
    buffer.writeln(_truncate(conv['firstUserQuery'] as String, 500));
    buffer.writeln(_truncate(conv['firstAssistantResponse'] as String, 500));
    buffer.writeln(_truncate(conv['lastUserQuery'] as String, 500));
    return buffer.toString();
  }).toList();
}

Future<List<List<double>>> _embedInBatches(
  EmbeddingService service,
  List<String> texts,
  int batchSize,
) async {
  final allEmbeddings = <List<double>>[];

  for (var i = 0; i < texts.length; i += batchSize) {
    final batchEnd = (i + batchSize).clamp(0, texts.length);
    final batch = texts.sublist(i, batchEnd);

    print('Embedding batch ${i ~/ batchSize + 1}/'
        '${(texts.length / batchSize).ceil()} '
        '(${batch.length} texts)');

    final embeddings = await service.generateBatch(batch);
    allEmbeddings.addAll(embeddings);
  }

  print('Embedded ${allEmbeddings.length} conversations');
  return allEmbeddings;
}

// ============ Selection ============

/// Select top conversations per cluster, scored by proximity to centroid only.
/// No recency bias — tune selection params and rerun freely.
List<int> _selectFromClusters(
  List<Map<String, dynamic>> conversations,
  KMeansResult clusterResult,
  int perCluster,
) {
  final clusterMembers = <int, List<int>>{};
  for (var i = 0; i < clusterResult.assignments.length; i++) {
    final cluster = clusterResult.assignments[i];
    clusterMembers.putIfAbsent(cluster, () => []).add(i);
  }

  final selectedIndices = <int>[];

  for (final entry in clusterMembers.entries) {
    final scored = entry.value.map((idx) {
      final proximityScore = 1.0 - clusterResult.distances[idx];
      return (index: idx, score: proximityScore);
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));

    for (var i = 0; i < perCluster && i < scored.length; i++) {
      selectedIndices.add(scored[i].index);
    }
  }

  return selectedIndices;
}

// ============ Cache IO ============

Future<void> _writeEmbeddingCache(
  List<Map<String, dynamic>> conversations,
  List<List<double>> embeddings,
) async {
  final outputDir = Directory('lib/training/extraction/golden/selection');
  if (!await outputDir.exists()) {
    await outputDir.create(recursive: true);
  }

  final cacheData = <Map<String, dynamic>>[];
  for (var i = 0; i < conversations.length; i++) {
    cacheData.add({
      'convUuid': conversations[i]['convUuid'],
      'convName': conversations[i]['convName'],
      'turnCount': conversations[i]['turnCount'],
      'estimatedTokens': conversations[i]['estimatedTokens'],
      'mostRecentTurnDate': conversations[i]['mostRecentTurnDate'],
      'embedding': embeddings[i],
    });
  }

  final file = File(embeddingCachePath);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'embeddedAt': DateTime.now().toIso8601String(),
      'totalConversations': cacheData.length,
      'embeddingDimension': EmbeddingService.dimension,
      'embeddingModel': 'jina-embeddings-v3',
      'embeddingInput': 'title + firstUserQuery + firstAssistantResponse + lastUserQuery',
      'conversations': cacheData,
    }),
  );
  print('\nWrote embedding cache: ${file.path} (${cacheData.length} conversations)');
}

Future<List<Map<String, dynamic>>> _loadEmbeddingCache() async {
  final file = File(embeddingCachePath);
  if (!await file.exists()) {
    throw StateError(
      'No embedding cache found at $embeddingCachePath. '
      'Run Step 1a first.',
    );
  }
  final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  return (data['conversations'] as List).cast<Map<String, dynamic>>();
}

// ============ Selection Output ============

Future<void> _writeSelectedJson(
  List<int> selectedIndices,
  List<Map<String, dynamic>> allConversations,
  KMeansResult clusterResult,
) async {
  final outputDir = Directory('lib/training/extraction/golden/selection');
  if (!await outputDir.exists()) {
    await outputDir.create(recursive: true);
  }

  final jsonData = selectedIndices.map((idx) {
    final conv = allConversations[idx];
    return {
      'convUuid': conv['convUuid'],
      'convName': conv['convName'],
      'turnCount': conv['turnCount'],
      'estimatedTokens': conv['estimatedTokens'],
      'mostRecentTurnDate': conv['mostRecentTurnDate'],
      'cluster': clusterResult.assignments[idx],
      'distanceToCentroid': clusterResult.distances[idx],
    };
  }).toList();

  final file = File(selectionOutputPath);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'selectedAt': DateTime.now().toIso8601String(),
      'totalSelected': jsonData.length,
      'clusterCount': clusterCount,
      'selectionsPerCluster': selectionsPerCluster,
      'minTurnCount': minTurnCount,
      'conversations': jsonData,
    }),
  );
  print('\nWrote ${file.path}');
}

Future<void> _writeSelectedCsv(
  List<int> selectedIndices,
  List<Map<String, dynamic>> allConversations,
  KMeansResult clusterResult,
) async {
  final buffer = StringBuffer();
  buffer.writeln(
      'convName,convUuid,cluster,distanceToCentroid,turnCount,estimatedTokens,mostRecentDate');

  for (final idx in selectedIndices) {
    final conv = allConversations[idx];
    final name = conv['convName'] as String;
    final escapedName = '"${name.replaceAll('"', '""')}"';
    final cluster = clusterResult.assignments[idx];
    final distance = clusterResult.distances[idx].toStringAsFixed(4);
    buffer.writeln(
      '$escapedName,${conv['convUuid']},$cluster,$distance,'
      '${conv['turnCount']},${conv['estimatedTokens']},'
      '${conv['mostRecentTurnDate']}',
    );
  }

  final file = File('lib/training/extraction/golden/selection/selected_conversations.csv');
  await file.writeAsString(buffer.toString());
  print('Wrote ${file.path}');
}

// ============ Print ============

void _printClusterSummary(
  List<Map<String, dynamic>> conversations,
  KMeansResult clusterResult,
) {
  final clusterMembers = <int, List<int>>{};
  for (var i = 0; i < clusterResult.assignments.length; i++) {
    final cluster = clusterResult.assignments[i];
    clusterMembers.putIfAbsent(cluster, () => []).add(i);
  }

  print('\n=== CLUSTER SUMMARY ===');
  for (final entry in clusterMembers.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key))) {
    final members = entry.value;
    final sampleNames = members
        .take(3)
        .map((i) => _truncate(conversations[i]['convName'] as String, 50))
        .join(', ');
    print('  Cluster ${entry.key}: ${members.length} conversations');
    print('    Samples: $sampleNames');
  }
}

// ============ Helpers ============

Future<Store> _openStore() async {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ?? '';
  for (final path in ['$home/Documents/objectbox', 'objectbox']) {
    final dataFile = File('$path/data.mdb');
    if (await dataFile.exists() && await dataFile.length() > 100 * 1024) {
      print('Opening store at: $path');
      return openStore(directory: path);
    }
  }
  print('Opening store at: objectbox');
  return openStore(directory: 'objectbox');
}

Map<String, dynamic> _parseJson(String? jsonStr) {
  if (jsonStr == null) return <String, dynamic>{};
  return jsonDecode(jsonStr) as Map<String, dynamic>;
}

int _countTurnChars(InvocationOB turn) {
  final input = _parseJson(turn.inputJson);
  final output = _parseJson(turn.outputJson);
  return (input['prompt']?.toString() ?? '').length +
      (output['response']?.toString() ?? '').length;
}

String _truncate(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength)}...';
}
