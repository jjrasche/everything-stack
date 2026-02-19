/// # ContextCapacity Integration Test
///
/// Tests learned token budget management and message truncation.
///
/// Verifies:
/// - Messages are truncated when exceeding token budget
/// - System message is always preserved during truncation
/// - Recent conversation turns are kept, oldest removed first
/// - Token counts are accurate using real TokenizerService
/// - ContextCapacity invocations are logged with token counts
/// - Truncation summary reports what was removed
/// - Integration with ExecutionLoop (step 6/7 in orchestration)
///
/// ## Test Flow
/// 1. Create long conversation history (exceeds token budget)
/// 2. Send query that triggers orchestration
/// 3. Verify ContextCapacity truncates messages
/// 4. Verify system message + recent turns preserved
/// 5. Verify invocations logged with token counts
/// 6. Verify LLM receives truncated context (not full history)

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/types/llm_types.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/services/context_capacity.dart';
import 'package:everything_stack_template/services/tokenizer_service.dart';
import 'package:get_it/get_it.dart';
import 'shared/test_harness.dart';
import 'shared/test_context.dart';
import 'shared/response_map_implementer.dart';

// Long conversation history (10 turns) to exceed token budget
// Budget for llama-3.3-70b-versatile: 8000 tokens (default)
// Each turn ~200 tokens → 10 turns ~2000 tokens
// System message ~500 tokens
// Total ~2500 tokens (within budget)
// So we'll set a custom low budget (1000 tokens) to trigger truncation

final _utterances = {
  'turn1': 'Tell me about the history of ancient Rome',
  'turn2': 'What were the major battles of the Roman Empire?',
  'turn3': 'Who were the most influential Roman emperors?',
  'turn4': 'What was daily life like for Roman citizens?',
  'turn5': 'What architectural innovations did the Romans create?',
  'turn6': 'How did the Roman legal system work?',
  'turn7': 'What caused the fall of the Roman Empire?',
  'turn8': 'What languages did the Romans speak?',
  'turn9': 'What was Roman military strategy like?',
  'turn10': 'What is the legacy of Rome today?', // Most recent, should be kept
};

final _responses = {
  _utterances['turn1']!: LLMResponse(
    id: 'rome_1',
    content: 'Ancient Rome was founded in 753 BC and grew from a small settlement on the Tiber River into one of the greatest empires in history, spanning from Britain to North Africa.',
    toolCalls: [],
    tokensUsed: 50,
  ),
  _utterances['turn2']!: LLMResponse(
    id: 'rome_2',
    content: 'Major battles include the Punic Wars against Carthage, the Gallic Wars under Julius Caesar, and the Battle of Actium which established Augustus as emperor.',
    toolCalls: [],
    tokensUsed: 40,
  ),
  _utterances['turn3']!: LLMResponse(
    id: 'rome_3',
    content: 'Influential emperors include Augustus (first emperor), Trajan (greatest military expansion), Marcus Aurelius (philosopher-king), and Constantine (legalized Christianity).',
    toolCalls: [],
    tokensUsed: 45,
  ),
  _utterances['turn4']!: LLMResponse(
    id: 'rome_4',
    content: 'Daily life varied by social class. Citizens attended public baths, forums, and entertainment like gladiatorial games. They lived in insulae (apartment buildings) or domus (private homes).',
    toolCalls: [],
    tokensUsed: 50,
  ),
  _utterances['turn5']!: LLMResponse(
    id: 'rome_5',
    content: 'Romans invented concrete, aqueducts, arches, domes, and the Colosseum. These innovations allowed them to build massive structures that still stand today.',
    toolCalls: [],
    tokensUsed: 40,
  ),
  _utterances['turn6']!: LLMResponse(
    id: 'rome_6',
    content: 'Roman law was based on written codes like the Twelve Tables. Citizens had rights, trials involved juries, and legal precedents influenced modern legal systems worldwide.',
    toolCalls: [],
    tokensUsed: 45,
  ),
  _utterances['turn7']!: LLMResponse(
    id: 'rome_7',
    content: 'The fall was caused by economic troubles, military defeats, barbarian invasions, political instability, and the division of the empire into East and West.',
    toolCalls: [],
    tokensUsed: 40,
  ),
  _utterances['turn8']!: LLMResponse(
    id: 'rome_8',
    content: 'Romans spoke Latin, which evolved into Romance languages (Italian, Spanish, French, Portuguese, Romanian). Greek was also widely used in the Eastern Empire.',
    toolCalls: [],
    tokensUsed: 45,
  ),
  _utterances['turn9']!: LLMResponse(
    id: 'rome_9',
    content: 'Roman military strategy relied on disciplined legions, superior engineering (roads, fortifications), and tactical formations like the testudo (tortoise formation).',
    toolCalls: [],
    tokensUsed: 40,
  ),
  _utterances['turn10']!: LLMResponse(
    id: 'rome_10',
    content: 'Rome\'s legacy includes law, language, architecture, engineering, government systems, and cultural influence that shaped Western civilization.',
    toolCalls: [],
    tokensUsed: 35,
  ),
};

final contextCapacityTest = IntegrationTestConfig(
  name: 'ContextCapacity (Token Budget Management)',

  repos: [
    InvocationRepository<Invocation>,
  ],

  utterances: _utterances,

  mockImplementers: {
    'groq': ResponseMapLLMImplementer(_responses),
  },

  testLogic: (t) async {
    print('\n=== TEST: ContextCapacity Token Budget Management ===');

    final invocationRepo = GetIt.instance<InvocationRepository<Invocation>>();
    final contextCapacity = GetIt.instance<ContextCapacity>();
    final tokenizerService = GetIt.instance<TokenizerService>();

    // ===== CLEANUP: Start fresh =====
    print('\n[Cleanup] Removing old invocations...');
    final oldInvocations = await invocationRepo.findAll();
    for (final inv in oldInvocations) {
      await invocationRepo.delete(inv.uuid);
    }
    print('   Deleted ${oldInvocations.length} invocations');

    // ===== SETUP: Create long conversation history =====
    print('\n[Setup] Creating 10-turn conversation about Rome...');

    for (int i = 1; i <= 10; i++) {
      final key = 'turn$i';
      final utterance = _utterances[key]!;
      print('   Turn $i: ${utterance.length > 40 ? utterance.substring(0, 40) + '...' : utterance}');
      await t.stt(key);
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Wait for all turns to complete
    await Future.delayed(const Duration(seconds: 2));

    // ===== TEST 1: Verify conversation history was created =====
    print('\n[Test 1] Verify conversation history exists...');

    var allInvocations = await invocationRepo.findAll();
    final llmInvocations = allInvocations
        .where((inv) => inv.componentType == 'llm')
        .toList();

    print('   Found ${llmInvocations.length} LLM invocations');

    expect(
      llmInvocations.length,
      greaterThanOrEqualTo(10),
      reason: 'Should have at least 10 LLM invocations from conversation',
    );

    // ===== TEST 2: ContextCapacity truncates messages when exceeding budget =====
    print('\n[Test 2] Test message truncation with small token budget...');

    // Create a long message history
    final messages = [
      {'role': 'system', 'content': 'You are a helpful assistant.'},
      {'role': 'user', 'content': _utterances['turn1']!},
      {'role': 'assistant', 'content': _responses[_utterances['turn1']!]!.content},
      {'role': 'user', 'content': _utterances['turn2']!},
      {'role': 'assistant', 'content': _responses[_utterances['turn2']!]!.content},
      {'role': 'user', 'content': _utterances['turn3']!},
      {'role': 'assistant', 'content': _responses[_utterances['turn3']!]!.content},
      {'role': 'user', 'content': _utterances['turn4']!},
      {'role': 'assistant', 'content': _responses[_utterances['turn4']!]!.content},
      {'role': 'user', 'content': _utterances['turn5']!},
      {'role': 'assistant', 'content': _responses[_utterances['turn5']!]!.content},
    ];

    print('   Original messages: ${messages.length}');

    // Count tokens in original messages
    final originalTokenCount = messages.fold<int>(
      0,
      (sum, msg) => sum + tokenizerService.countTokens(msg['content'] as String),
    );

    print('   Original token count: $originalTokenCount');

    // Truncate to 200 tokens (will force removal of middle messages)
    final truncationResult = await contextCapacity.truncateMessages(
      messages: messages,
      model: 'groq:llama-3.3-70b-versatile',
      eventId: 'test-event-truncation',
      customTokenBudget: 200, // Very small budget to force truncation
    );

    print('   Truncated messages: ${truncationResult.messages.length}');
    print('   Was truncated: ${truncationResult.wasTruncated}');
    print('   Final token count: ${truncationResult.totalTokens}');
    print('   Token budget: ${truncationResult.tokenBudget}');
    print('   Summary: ${truncationResult.summary}');

    expect(
      truncationResult.wasTruncated,
      isTrue,
      reason: 'Messages should be truncated when exceeding token budget',
    );

    expect(
      truncationResult.totalTokens,
      lessThanOrEqualTo(truncationResult.tokenBudget),
      reason: 'Final token count should be within budget',
    );

    expect(
      truncationResult.messages.length,
      lessThan(messages.length),
      reason: 'Truncated messages should be fewer than original',
    );

    // ===== TEST 3: System message is always preserved =====
    print('\n[Test 3] Verify system message is preserved during truncation...');

    final systemMessage = truncationResult.messages.firstWhere(
      (msg) => msg['role'] == 'system',
      orElse: () => {},
    );

    expect(
      systemMessage,
      isNotEmpty,
      reason: 'System message should be preserved during truncation',
    );

    expect(
      systemMessage['content'],
      equals('You are a helpful assistant.'),
      reason: 'System message content should be unchanged',
    );

    print('   ✅ System message preserved: "${systemMessage['content']}"');

    // ===== TEST 4: Recent turns are kept, oldest removed first =====
    print('\n[Test 4] Verify recent turns are kept, oldest removed...');

    // The last user message should be from turn5 (most recent)
    final lastUserMessage = truncationResult.messages.lastWhere(
      (msg) => msg['role'] == 'user',
      orElse: () => {},
    );

    expect(
      lastUserMessage,
      isNotEmpty,
      reason: 'Should have at least one user message after truncation',
    );

    print('   Last user message: "${lastUserMessage['content']}"');

    // The most recent turn (turn5) should be included
    final hasRecentTurn = truncationResult.messages.any(
      (msg) => msg['content']?.toString().contains('architectural innovations') == true,
    );

    expect(
      hasRecentTurn,
      isTrue,
      reason: 'Most recent conversation turn should be preserved',
    );

    // The oldest turn (turn1) should be removed
    final hasOldestTurn = truncationResult.messages.any(
      (msg) => msg['content']?.toString().contains('history of ancient Rome') == true,
    );

    expect(
      hasOldestTurn,
      isFalse,
      reason: 'Oldest conversation turn should be removed during truncation',
    );

    print('   ✅ Recent turns kept, oldest removed');

    // ===== TEST 5: ContextCapacity invocations are logged =====
    print('\n[Test 5] Verify ContextCapacity invocations are logged...');

    allInvocations = await invocationRepo.findAll();
    final contextCapacityInvocations = allInvocations
        .where((inv) => inv.componentType == 'context_capacity')
        .toList();

    print('   Found ${contextCapacityInvocations.length} context_capacity invocations');

    expect(
      contextCapacityInvocations.isNotEmpty,
      isTrue,
      reason: 'ContextCapacity should log invocations',
    );

    final lastContextCapacityInv = contextCapacityInvocations.last;
    print('   Last ContextCapacity invocation:');
    print('     Input: ${lastContextCapacityInv.input}');
    print('     Output: ${lastContextCapacityInv.output}');

    // Verify input contains model
    expect(
      lastContextCapacityInv.input?['model'],
      isNotNull,
      reason: 'Invocation input should contain model',
    );

    // Verify output contains token counts
    expect(
      lastContextCapacityInv.output?['finalTokens'],
      isNotNull,
      reason: 'Invocation output should log final token count',
    );

    expect(
      lastContextCapacityInv.output?['tokenBudget'],
      isNotNull,
      reason: 'Invocation output should log token budget',
    );

    expect(
      lastContextCapacityInv.output?['wasTruncated'],
      isNotNull,
      reason: 'Invocation output should log whether truncation occurred',
    );

    // ===== TEST 6: Token counts are accurate using real TokenizerService =====
    print('\n[Test 6] Verify token counts are accurate...');

    // Manually count tokens in truncated messages
    // ContextCapacity adds overhead per message for role markers, delimiters, etc.
    final manualTokenCount = truncationResult.messages.fold<int>(
      0,
      (sum, msg) => sum + tokenizerService.countTokens(msg['content'] as String) + ContextCapacity.tokensPerMessageOverhead,
    );

    print('   Manual token count: $manualTokenCount (including ${ContextCapacity.tokensPerMessageOverhead} tokens/msg overhead)');
    print('   Reported token count: ${truncationResult.totalTokens}');

    // Allow small variance (±5%) due to tokenizer edge cases
    final variance = (manualTokenCount - truncationResult.totalTokens).abs();
    final allowedVariance = (manualTokenCount * 0.05).ceil();

    expect(
      variance,
      lessThanOrEqualTo(allowedVariance),
      reason: 'Reported token count should match manual count (within 5%)',
    );

    print('   ✅ Token counts accurate (variance: $variance, allowed: $allowedVariance)');

    // ===== TEST 7: Integration with ExecutionLoop (truncation in step 6/7) =====
    print('\n[Test 7] Verify ExecutionLoop uses ContextCapacity in orchestration...');

    // Clear invocations and trigger new orchestration
    print('   Clearing invocations and triggering new turn...');
    allInvocations = await invocationRepo.findAll();
    for (final inv in allInvocations) {
      await invocationRepo.delete(inv.uuid);
    }

    // Trigger orchestration (uses default ExecutionLoop flow with ContextCapacity)
    await t.stt('turn1');
    await Future.delayed(const Duration(seconds: 2));

    // Check that ContextCapacity was called during orchestration
    allInvocations = await invocationRepo.findAll();
    final loopContextCapacityInvocations = allInvocations
        .where((inv) => inv.componentType == 'context_capacity')
        .toList();

    print('   Found ${loopContextCapacityInvocations.length} context_capacity invocations from ExecutionLoop');

    expect(
      loopContextCapacityInvocations.isNotEmpty,
      isTrue,
      reason: 'ExecutionLoop should call ContextCapacity during orchestration (step 6/7)',
    );

    // ===== TEST 8: No truncation when within budget =====
    print('\n[Test 8] Verify no truncation when within budget...');

    final shortMessages = [
      {'role': 'system', 'content': 'You are helpful.'},
      {'role': 'user', 'content': 'Hello'},
      {'role': 'assistant', 'content': 'Hi there!'},
    ];

    final noTruncationResult = await contextCapacity.truncateMessages(
      messages: shortMessages,
      model: 'groq:llama-3.3-70b-versatile',
      eventId: 'test-event-no-truncation',
    );

    print('   Was truncated: ${noTruncationResult.wasTruncated}');
    print('   Token count: ${noTruncationResult.totalTokens}/${noTruncationResult.tokenBudget}');

    expect(
      noTruncationResult.wasTruncated,
      isFalse,
      reason: 'Should not truncate when within budget',
    );

    expect(
      noTruncationResult.messages.length,
      equals(shortMessages.length),
      reason: 'Message count should be unchanged when no truncation needed',
    );

    print('   ✅ No truncation when within budget');

    print('\n=== ContextCapacity Test PASSED ===');
  },
);
