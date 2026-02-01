/// # Invocation Chunking Integration Test
///
/// Tests that LLM invocations are chunked as whole units for VoiceTraits retrieval.
/// Each LLM invocation should produce:
/// - 1 chunk for the conversation turn (User + Assistant as a unit)
/// - NOT fragmented into smaller chunks
///
/// This enables VoiceTraits to retrieve complete conversation examples for few-shot learning.
///
/// ## Test Philosophy
/// These tests use EXACT assertions and verify the full content structure.
/// We verify not just that a chunk exists, but that it contains the complete
/// conversation turn with both user query AND assistant response.

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/types/llm_types.dart';
import 'package:everything_stack_template/services/chunking_service.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:get_it/get_it.dart';
import 'shared/test_harness.dart';
import 'shared/test_context.dart';
import 'shared/response_map_implementer.dart';

// Test query and expected response - these are used for exact content verification
const _testQuery = 'Can you explain the process of photosynthesis in detail?';
const _testResponse = '''Photosynthesis is a complex biological process that converts light energy into chemical energy.

The process occurs in two main stages:

1. Light-dependent reactions: These occur in the thylakoid membranes where chlorophyll absorbs sunlight. Water molecules are split, releasing oxygen as a byproduct. ATP and NADPH are produced.

2. Light-independent reactions (Calvin Cycle): These occur in the stroma. Carbon dioxide is fixed into organic compounds using the ATP and NADPH from the light reactions. The end product is glucose.

The overall equation is: 6CO2 + 6H2O + light energy → C6H12O6 + 6O2

This process is fundamental to life on Earth as it produces oxygen and forms the base of most food chains.''';

final _utterances = {
  'long_question': _testQuery,
};

final _responses = {
  _testQuery: LLMResponse(
    id: 'long_1',
    content: _testResponse,
    toolCalls: [],
    tokensUsed: 150,
  ),
};

/// Poll for a condition with timeout instead of fixed delay.
/// Returns true if condition met, false if timeout.
Future<bool> _pollUntil(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  Duration interval = const Duration(milliseconds: 200),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return true;
    await Future.delayed(interval);
  }
  return false;
}

final invocationChunkingTest = IntegrationTestConfig(
  name: 'Invocation Chunking (Whole Units)',

  repos: [
    InvocationRepository<Invocation>,
  ],

  utterances: _utterances,

  mockImplementers: {
    'groq': ResponseMapLLMImplementer(_responses),
  },

  testLogic: (t) async {
    print('\n=== TEST: Invocation Chunking as Whole Units ===');

    // ===== CLEANUP: Delete old invocations to avoid polluting test =====
    print('\n[Cleanup] Deleting old LLM invocations...');
    final invocationRepo = GetIt.instance<InvocationRepository<Invocation>>();
    final chunkingService = GetIt.instance<ChunkingService>();

    final oldInvocations = await invocationRepo.findAll();
    var cleanedCount = 0;
    for (final inv in oldInvocations) {
      if (inv.componentType == 'llm') {
        await chunkingService.deleteByEntityId(inv.uuid);
        await invocationRepo.delete(inv.uuid);
        cleanedCount++;
      }
    }
    print('   Cleaned up $cleanedCount old LLM invocations');

    // Verify cleanup worked
    final postCleanup = await invocationRepo.findAll();
    final llmAfterCleanup = postCleanup.where((i) => i.componentType == 'llm').length;
    expect(
      llmAfterCleanup,
      equals(0),
      reason: 'Cleanup MUST remove all LLM invocations before test',
    );

    // ===== SETUP: Send a query that generates a long response =====
    print('\n[Setup] Sending query that generates long response...');
    print('   Query: "$_testQuery"');
    await t.stt('long_question');

    // ===== POLL: Wait for LLM invocation to be created (not fixed delay) =====
    print('\n[Poll] Waiting for LLM invocation to be created...');
    final invocationCreated = await _pollUntil(() async {
      final invs = await invocationRepo.findAll();
      return invs.any((i) => i.componentType == 'llm');
    });

    expect(
      invocationCreated,
      isTrue,
      reason: 'LLM invocation MUST be created within 10 seconds',
    );

    // ===== POLL: Wait for chunk to be created =====
    print('[Poll] Waiting for chunk to be created...');
    String? targetUuid;
    final chunkCreated = await _pollUntil(() async {
      final invs = await invocationRepo.findAll();
      final llmInvs = invs.where((i) => i.componentType == 'llm').toList();
      if (llmInvs.isEmpty) return false;
      targetUuid = llmInvs.last.uuid;
      final chunks = await chunkingService.getChunksForEntity(targetUuid!);
      return chunks.isNotEmpty;
    });

    expect(
      chunkCreated,
      isTrue,
      reason: 'Chunk MUST be created for LLM invocation within 10 seconds',
    );

    // ===== VERIFY: Get the LLM invocation =====
    print('\n[Verify] Checking LLM invocation and chunks...');
    final allInvocations = await invocationRepo.findAll();
    final llmInvocations = allInvocations
        .where((inv) => inv.componentType == 'llm')
        .toList();

    print('   Found ${llmInvocations.length} LLM invocations');

    // At least 1 LLM invocation should exist
    expect(
      llmInvocations.length,
      greaterThanOrEqualTo(1),
      reason: 'Test should produce at least 1 LLM invocation',
    );

    // Find the invocation that contains our expected response about photosynthesis
    // (orchestration may create multiple invocations for context, etc.)
    final targetInvocation = llmInvocations.firstWhere(
      (inv) {
        final response = inv.output?['response'] as String?;
        // Match our mock response content
        return response != null && response.contains('Light-dependent reactions');
      },
      orElse: () => llmInvocations.last,  // Fallback to last if not found
    );

    final llmInv = targetInvocation;
    print('   Target LLM invocation UUID: ${llmInv.uuid}');
    print('   Response preview: "${(llmInv.output?['response'] as String? ?? '').substring(0, 80)}..."');

    // ===== VERIFY: Invocation content =====
    print('\n[Verify] Checking invocation content...');

    // Verify invocation has correct input/output
    expect(
      llmInv.input,
      isNotNull,
      reason: 'LLM invocation MUST have input',
    );
    expect(
      llmInv.output,
      isNotNull,
      reason: 'LLM invocation MUST have output',
    );

    // Verify output contains the response
    final outputResponse = llmInv.output!['response'] as String?;
    expect(
      outputResponse,
      isNotNull,
      reason: 'LLM invocation output MUST contain "response" field',
    );
    expect(
      outputResponse,
      contains('Photosynthesis'),
      reason: 'Response MUST contain the photosynthesis explanation',
    );

    // ===== VERIFY: getChunkingConfig returns correct value =====
    final chunkingConfig = llmInv.getChunkingConfig();
    print('   getChunkingConfig(): $chunkingConfig');

    expect(
      chunkingConfig,
      equals('invocation'),
      reason: 'LLM invocations MUST return "invocation" from getChunkingConfig()',
    );

    // ===== VERIFY: Chunk structure =====
    print('\n[Verify] Checking chunk structure...');
    final chunks = await chunkingService.getChunksForEntity(llmInv.uuid);
    print('   Chunks created: ${chunks.length}');

    // EXACT assertion: exactly 1 chunk for whole-unit chunking
    expect(
      chunks.length,
      equals(1),
      reason: 'LLM invocation MUST produce exactly 1 chunk (whole unit, not fragmented)',
    );

    final chunk = chunks.first;
    print('   Chunk ID: ${chunk.id}');
    print('   Chunk config: ${chunk.config}');
    print('   Chunk text length: ${chunk.text.length} chars');

    // ===== VERIFY: Chunk config =====
    expect(
      chunk.config,
      equals('invocation'),
      reason: 'Chunk config MUST be "invocation" for whole-unit chunking',
    );

    // ===== VERIFY: Chunk contains BOTH user query AND assistant response =====
    print('\n[Verify] Checking chunk content completeness...');

    // Must contain user prefix
    expect(
      chunk.text.contains('User:'),
      isTrue,
      reason: 'Chunk text MUST contain "User:" prefix (conversation format)',
    );

    // Must contain assistant prefix
    expect(
      chunk.text.contains('Assistant:'),
      isTrue,
      reason: 'Chunk text MUST contain "Assistant:" prefix (conversation format)',
    );

    // Must contain the user query
    expect(
      chunk.text.toLowerCase().contains('photosynthesis'),
      isTrue,
      reason: 'Chunk text MUST contain the user query about photosynthesis',
    );

    // Must contain key parts of the response
    expect(
      chunk.text.contains('Light-dependent reactions'),
      isTrue,
      reason: 'Chunk text MUST contain response content (Light-dependent reactions)',
    );
    expect(
      chunk.text.contains('Calvin Cycle'),
      isTrue,
      reason: 'Chunk text MUST contain response content (Calvin Cycle)',
    );
    expect(
      chunk.text.contains('6CO2 + 6H2O'),
      isTrue,
      reason: 'Chunk text MUST contain response content (chemical equation)',
    );

    // ===== VERIFY: Chunk has substantial content =====
    // The full conversation should be ~800+ characters
    print('   Chunk text preview: "${chunk.text.substring(0, 100)}..."');

    expect(
      chunk.text.length,
      greaterThan(700),
      reason: 'Chunk MUST contain full conversation (>700 chars expected)',
    );

    // ===== VERIFY: Chunk source entity linkage =====
    expect(
      chunk.sourceEntityId,
      equals(llmInv.uuid),
      reason: 'Chunk sourceEntityId MUST match the invocation UUID',
    );
    expect(
      chunk.sourceEntityType,
      equals('Invocation'),
      reason: 'Chunk sourceEntityType MUST be "Invocation"',
    );

    // ===== VERIFY: Token range is sensible =====
    expect(
      chunk.startToken,
      equals(0),
      reason: 'Whole-unit chunk startToken MUST be 0',
    );
    expect(
      chunk.endToken,
      greaterThan(0),
      reason: 'Whole-unit chunk endToken MUST be positive',
    );

    print('\n=== Invocation Chunking Test PASSED (all assertions verified) ===');
  },
);
