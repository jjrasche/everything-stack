/// Step 2: Extract atomic insights per-turn from selected conversations.
///
/// Run Phase A (single conversation):
///   flutter test test/services/extraction/step2_extract_per_turn_test.dart --name="Phase A"
///
/// Run Phase B (all 30 conversations):
///   flutter test test/services/extraction/step2_extract_per_turn_test.dart --name="Phase B"
///
/// Reads: lib/training/extraction/golden/selection/selected_conversations.json (from Step 1)
///        ObjectBox store (full turn data)
/// Writes: lib/training/extraction/golden/conv_<uuid8>.json per conversation
/// Cost:   Phase A: ~3-5 Groq calls on 8B. Phase B: ~90 calls on 8B.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/objectbox.g.dart';
import 'package:everything_stack_template/persistence/objectbox/wrappers/invocation_ob.dart';
import 'package:everything_stack_template/persistence/objectbox/invocation_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/adaptation_state_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/feedback_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/atomic_insight_objectbox_adapter.dart';
import 'package:everything_stack_template/persistence/objectbox/prompt_version_objectbox_adapter.dart';
import 'package:everything_stack_template/services/inference_service.dart';
import 'package:everything_stack_template/services/implementations/groq_implementer.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/extraction/atomic_insight_extractor.dart';
import 'package:everything_stack_template/services/prompt/prompt_registry.dart';
import 'package:everything_stack_template/domain/atomic_insight.dart';
import 'package:everything_stack_template/domain/atomic_insight_repository.dart';
import 'package:everything_stack_template/domain/prompt_version_repository.dart';

void main() {
  late Store store;
  late AtomicInsightExtractor extractor;

  setUp(() async {
    await dotenv.load(fileName: '.env');
    store = await _openStore();

    final groqKey = dotenv.env['GROQ_API_KEY'] ?? '';
    expect(groqKey, isNotEmpty, reason: 'GROQ_API_KEY required in .env');

    extractor = _wireExtractor(store, groqKey);
  });

  tearDown(() {
    store.close();
  });

  test('Phase A: extract from single conversation', () async {
    final selectedConversations = await _loadSelectedConversations();
    expect(selectedConversations, isNotEmpty, reason: 'Run step1 first');

    final first = selectedConversations.first;
    final turns = _loadTurnsFromStore(store, first['convUuid'] as String);
    print('Phase A: "${first['convName']}" (${turns.length} turns)');

    final insights = await _extractPerTurn(extractor, turns);
    _printExtractionDetail(turns, insights);

    expect(insights, isNotEmpty, reason: 'Should extract at least one insight');
  });

  test('Phase B: extract from all selected conversations', () async {
    final selectedConversations = await _loadSelectedConversations();
    expect(selectedConversations, isNotEmpty, reason: 'Run step1 first');

    final outputDir = Directory('lib/training/extraction/golden');
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    var totalInsights = 0;

    for (final conv in selectedConversations) {
      final convUuid = conv['convUuid'] as String;
      final convName = conv['convName'] as String;
      final turns = _loadTurnsFromStore(store, convUuid);

      if (turns.isEmpty) {
        print('SKIP: "$convName" - no turns found in store');
        continue;
      }

      print('Extracting: "$convName" (${turns.length} turns)');
      final insights = await _extractPerTurn(extractor, turns);
      totalInsights += insights.length;

      final uuid8 = convUuid.substring(0, 8);
      await _writeConversationResult(
        outputDir: outputDir,
        uuid8: uuid8,
        convUuid: convUuid,
        convName: convName,
        turns: turns,
        insights: insights,
      );

      print('  -> ${insights.length} insights -> conv_$uuid8.json');
    }

    print('\nTotal insights across ${selectedConversations.length} '
        'conversations: $totalInsights');
    expect(totalInsights, greaterThan(0));
  });
}

// ============ Extraction ============

/// Extract insights one turn at a time, accumulating dedup context.
Future<List<_InsightWithSource>> _extractPerTurn(
  AtomicInsightExtractor extractor,
  List<Map<String, dynamic>> turns,
) async {
  final allInsights = <_InsightWithSource>[];

  for (var turnIndex = 0; turnIndex < turns.length; turnIndex++) {
    final singleTurn = [turns[turnIndex]];

    final extracted = await extractor.extractFromConversation(
      turns: singleTurn,
      batchSize: 1,
    );

    for (final insight in extracted) {
      allInsights.add(_InsightWithSource(
        insight: insight,
        sourceTurnIndex: turnIndex,
      ));
    }
  }

  return allInsights;
}

// ============ Data Types ============

class _InsightWithSource {
  final AtomicInsight insight;
  final int sourceTurnIndex;

  _InsightWithSource({required this.insight, required this.sourceTurnIndex});
}

// ============ Store Queries ============

List<Map<String, dynamic>> _loadTurnsFromStore(Store store, String convUuid) {
  final box = store.box<InvocationOB>();
  final query = box.query(
    InvocationOB_.implementer.equals('claude_import'),
  ).build();
  final allInvocations = query.find();
  query.close();

  final matchingTurns = <InvocationOB>[];
  for (final inv in allInvocations) {
    final metadata = _parseJson(inv.metadataJson);
    if (metadata['sourceConversationUuid'] == convUuid) {
      matchingTurns.add(inv);
    }
  }

  // Sort by creation date to preserve conversation order
  matchingTurns.sort((a, b) => a.createdAt.compareTo(b.createdAt));

  return matchingTurns.map((inv) {
    final input = _parseJson(inv.inputJson);
    final output = _parseJson(inv.outputJson);
    return <String, dynamic>{
      'prompt': input['prompt'] ?? '',
      'response': output['response'] ?? '',
    };
  }).toList();
}

// ============ Bootstrap ============

AtomicInsightExtractor _wireExtractor(Store store, String groqKey) {
  final inferenceService = InferenceService(
    implementers: {'groq': GroqImplementer(apiKey: groqKey)},
    defaultImplementer: 'groq',
    invocationRepo: InvocationObjectBoxAdapter(store),
    adaptationStateRepo: AdaptationStateObjectBoxAdapter(store),
    feedbackRepo: FeedbackObjectBoxAdapter(store),
  );

  // NullEmbeddingService disables vector dedup intentionally.
  // LLM sees previous insights in context and skips duplicates.
  final insightRepo = AtomicInsightRepository(
    adapter: AtomicInsightObjectBoxAdapter(store),
    embeddingService: NullEmbeddingService(),
  );

  final promptVersionRepo = PromptVersionRepository(
    adapter: PromptVersionObjectBoxAdapter(store),
    embeddingService: NullEmbeddingService(),
  );

  final promptRegistry = PromptRegistry(
    repo: promptVersionRepo,
    componentType: 'extraction_prompt',
    hardcodedDefault: AtomicInsightExtractor.defaultSystemPrompt,
  );

  return AtomicInsightExtractor(
    insightRepo: insightRepo,
    inferenceService: inferenceService,
    promptRegistry: promptRegistry,
  );
}

// ============ IO ============

Future<List<Map<String, dynamic>>> _loadSelectedConversations() async {
  final file = File('lib/training/extraction/golden/selection/selected_conversations.json');
  if (!await file.exists()) {
    throw StateError('Run step1 first: selected_conversations.json not found');
  }
  final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  final conversations = data['conversations'] as List<dynamic>;
  return conversations.cast<Map<String, dynamic>>();
}

Future<void> _writeConversationResult({
  required Directory outputDir,
  required String uuid8,
  required String convUuid,
  required String convName,
  required List<Map<String, dynamic>> turns,
  required List<_InsightWithSource> insights,
}) async {
  final jsonData = {
    'convUuid': convUuid,
    'convName': convName,
    'turnCount': turns.length,
    'insightCount': insights.length,
    'turns': turns,
    'insights': insights.map((iws) => {
      'content': iws.insight.content,
      'scope': iws.insight.scope,
      'type': iws.insight.type,
      'sourceTurnIndex': iws.sourceTurnIndex,
    }).toList(),
  };

  final file = File('${outputDir.path}/conv_$uuid8.json');
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(jsonData),
  );
}

// ============ Print ============

void _printExtractionDetail(
  List<Map<String, dynamic>> turns,
  List<_InsightWithSource> insights,
) {
  print('\n=== EXTRACTION DETAIL ===');
  for (var i = 0; i < turns.length; i++) {
    final prompt = turns[i]['prompt']?.toString() ?? '';
    final promptPreview = prompt.length > 100
        ? '${prompt.substring(0, 100)}...'
        : prompt;
    print('\nTurn $i: $promptPreview');

    final turnInsights = insights.where((iws) => iws.sourceTurnIndex == i);
    if (turnInsights.isEmpty) {
      print('  (no insights)');
    } else {
      for (final iws in turnInsights) {
        print('  -> [${iws.insight.scope}] ${iws.insight.content}');
      }
    }
  }

  print('\n=== SUMMARY ===');
  print('Turns: ${turns.length}');
  print('Insights: ${insights.length}');

  final byScope = <String, int>{};
  for (final iws in insights) {
    byScope[iws.insight.scope] = (byScope[iws.insight.scope] ?? 0) + 1;
  }
  print('By scope: $byScope');
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
