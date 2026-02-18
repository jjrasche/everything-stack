/// Shared CLI bootstrap utilities for all scripts.
///
/// Provides environment loading, ObjectBox store, InferenceService,
/// and golden data loading. No domain-specific dependencies.
///
/// Usage:
///   import 'shared_bootstrap.dart';
///   await loadEnvironment();
///   final store = await openScriptStore();
///   final inference = createInferenceService(store);

import 'dart:io';
import 'dart:convert';

import 'package:objectbox/objectbox.dart';

import '../lib/objectbox.g.dart';

import '../lib/persistence/objectbox/invocation_objectbox_adapter.dart';
import '../lib/persistence/objectbox/adaptation_state_objectbox_adapter.dart';
import '../lib/persistence/objectbox/feedback_objectbox_adapter.dart';

import '../lib/services/inference_service.dart';
import '../lib/services/implementations/groq_implementer.dart';

// ============ Typed Containers ============

/// Minimal CLI infrastructure: store + inference service.
/// Scripts that need more services build on top of this.
class ScriptInfrastructure {
  final Store store;
  final InferenceService inferenceService;

  ScriptInfrastructure({
    required this.store,
    required this.inferenceService,
  });

  void dispose() {
    store.close();
  }
}

/// Parsed golden conversation ready for processing.
class GoldenConversation {
  final String filename;
  final String convUuid;
  final String convName;
  final int turnCount;
  final List<Map<String, dynamic>> turns;

  GoldenConversation({
    required this.filename,
    required this.convUuid,
    required this.convName,
    required this.turnCount,
    required this.turns,
  });
}

// ============ Infrastructure Setup ============

/// Load .env and create store + inference service.
/// Caller MUST call result.dispose() in a finally block.
Future<ScriptInfrastructure> initializeInfrastructure() async {
  await loadEnvironment();
  final store = await openScriptStore();
  final inferenceService = createInferenceService(store);
  return ScriptInfrastructure(
    store: store,
    inferenceService: inferenceService,
  );
}

// ============ Environment State ============

/// Parsed .env values, populated by loadEnvironment().
final Map<String, String> env = {};

// ============ Concept Functions ============

Future<void> loadEnvironment() async {
  final file = File('.env');
  if (!await file.exists()) {
    print('Failed to load .env: file not found');
    print('Create .env with GROQ_API_KEY (and optionally JINA_API_KEY)');
    exit(1);
  }
  final lines = await file.readAsLines();
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final eqIndex = trimmed.indexOf('=');
    if (eqIndex < 0) continue;
    final key = trimmed.substring(0, eqIndex).trim();
    final value = trimmed.substring(eqIndex + 1).trim();
    env[key] = value;
  }
}

Future<Store> openScriptStore() async {
  return openStore(directory: 'objectbox');
}

InferenceService createInferenceService(Store store) {
  final groqKey = env['GROQ_API_KEY'];
  if (groqKey == null || groqKey.isEmpty) {
    print('GROQ_API_KEY missing from .env');
    exit(1);
  }

  return InferenceService(
    implementers: {'groq': GroqImplementer(apiKey: groqKey)},
    defaultImplementer: 'groq',
    invocationRepo: InvocationObjectBoxAdapter(store),
    adaptationStateRepo: AdaptationStateObjectBoxAdapter(store),
    feedbackRepo: FeedbackObjectBoxAdapter(store),
  );
}

// ============ Golden Data Utilities ============

/// Load golden conversations from exported JSON files.
///
/// Reads conv_*.json files from [dir], parses each into
/// a GoldenConversation with turns in {prompt, response} format.
Future<List<GoldenConversation>> loadGoldenConversations(String dir) async {
  final directory = Directory(dir);
  if (!await directory.exists()) {
    print('Golden data directory not found: $dir');
    print('Export conversations first:');
    print('  dart run scripts/query_imported_conversations.dart --export=uuid1,uuid2');
    exit(1);
  }

  final jsonFiles = await directory
      .list()
      .where((entity) => entity.path.endsWith('.json'))
      .toList();

  if (jsonFiles.isEmpty) {
    print('No .json files found in $dir');
    exit(1);
  }

  final conversations = <GoldenConversation>[];

  for (final file in jsonFiles) {
    final content = await File(file.path).readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;
    final conversation = data['conversation'] as Map<String, dynamic>;
    final rawTurns = conversation['turns'] as List<dynamic>;

    final turns = rawTurns.map((t) {
      final turn = t as Map<String, dynamic>;
      return <String, dynamic>{
        'prompt': turn['prompt'] ?? '',
        'response': turn['response'] ?? '',
      };
    }).toList();

    final filename = file.path.split(Platform.pathSeparator).last;

    conversations.add(GoldenConversation(
      filename: filename,
      convUuid: conversation['uuid'] as String,
      convName: conversation['name'] as String? ?? 'Unnamed',
      turnCount: turns.length,
      turns: turns,
    ));
  }

  conversations.sort((a, b) => a.filename.compareTo(b.filename));
  return conversations;
}

/// Parse a --key=value argument from command line args.
String parseArg(List<String> args, String key, String defaultValue) {
  for (final arg in args) {
    if (arg.startsWith('--$key=')) {
      return arg.substring('--$key='.length);
    }
  }
  return defaultValue;
}
