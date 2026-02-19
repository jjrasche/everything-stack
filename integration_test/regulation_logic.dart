/// # Regulation Tracking Integration Test
///
/// Tests event-driven regulation tracking with regulation tools.
/// Verifies:
/// - EventBus → ExecutionLoop → ContextSelector → LLM → ToolExecutor → Regulation Repositories
/// - Auto-creation of Person entities
/// - Regulation entry logging
/// - Commitment creation and logging
/// - Invocation logging
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/types/llm_types.dart';
import 'package:everything_stack_template/tools/regulation/repositories/person_repository.dart';
import 'package:everything_stack_template/tools/regulation/repositories/regulation_entry_repository.dart';
import 'package:everything_stack_template/tools/regulation/repositories/commitment_repository.dart';
import 'package:everything_stack_template/tools/regulation/repositories/commitment_log_repository.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'shared/test_harness.dart';
import 'shared/response_map_implementer.dart';
import 'mocks/mock_flutter_tts_implementer.dart';

// Define utterances once - used in both test logic and mock responses
final _utterances = {
  'turn1': 'I caught myself getting frustrated with Alice. I walked away.',
  'turn2': 'Create a daily commitment for morning meditation',
  'turn3': 'I completed my morning meditation today',
};

final _responses = {
  _utterances['turn1']!: LLMResponse(
    id: 'mock_1',
    content: 'Logging your dysregulation catch with Alice',
    toolCalls: [
      LLMToolCall(
        id: 'call_1',
        toolName: 'regulation.log_entry',
        params: {
          'entry_type': 'dysregulationCatch',
          'person_names': ['me', 'Alice'],
          'raw_transcript': _utterances['turn1']!,
          'severity': 'minor',
          'regulation_strategy': 'walked away',
        },
      ),
    ],
    tokensUsed: 25,
  ),
  _utterances['turn2']!: LLMResponse(
    id: 'mock_2',
    content: 'Creating daily morning meditation commitment',
    toolCalls: [
      LLMToolCall(
        id: 'call_2',
        toolName: 'commitment.create',
        params: {
          'name': 'Morning meditation',
          'interval': 'daily',
          'rationale': 'Start day with mindfulness',
        },
      ),
    ],
    tokensUsed: 20,
  ),
  _utterances['turn3']!: LLMResponse(
    id: 'mock_3',
    content: 'Logging your commitment completion',
    toolCalls: [
      LLMToolCall(
        id: 'call_3',
        toolName: 'regulation.log_commitment',
        params: {
          'commitment_name': 'Morning meditation',
          'completed': true,
        },
      ),
    ],
    tokensUsed: 15,
  ),
};

final regulationTrackingTest = IntegrationTestConfig(
  name: 'Regulation Tracking',

  repos: [
    PersonRepository,
    RegulationEntryRepository,
    CommitmentRepository,
    CommitmentLogRepository,
    InvocationRepository<Invocation>,
  ],

  utterances: _utterances,

  mockImplementers: {
    'groq': ResponseMapLLMImplementer(_responses),
    'tts': MockFlutterTTSImplementer(),
  },

  testLogic: (t) async {
    // Clear any leftover regulation entities from previous test runs
    final existingPersons = await t.personRepo.findAll();
    for (final person in existingPersons) {
      await t.personRepo.deleteByUuid(person.uuid);
    }

    final existingEntries = await t.regulationEntryRepo.findAll();
    for (final entry in existingEntries) {
      await t.regulationEntryRepo.deleteByUuid(entry.uuid);
    }

    final existingCommitments = await t.commitmentRepo.findAll();
    for (final commitment in existingCommitments) {
      await t.commitmentRepo.deleteByUuid(commitment.uuid);
    }

    // ===== TURN 1: Log dysregulation catch =====
    await t.stt('turn1');

    // Verify Person auto-created
    final persons = await t.personRepo.findAll();
    expect(persons.length, greaterThanOrEqualTo(2),
        reason: 'Should have at least 2 persons (me, Alice)');

    final me = await t.personRepo.findByName('me');
    expect(me, isNotNull, reason: 'Person "me" should be auto-created');

    final alice = await t.personRepo.findByName('Alice');
    expect(alice, isNotNull, reason: 'Person "Alice" should be auto-created');

    // Verify RegulationEntry created
    final entries = await t.regulationEntryRepo.findAll();
    expect(entries.isNotEmpty, isTrue, reason: 'Should have regulation entries');

    final recentEntry = entries.last;
    expect(recentEntry.entryType.toString(), contains('dysregulationCatch'));
    expect(recentEntry.personIds, contains(me!.uuid));
    expect(recentEntry.personIds, contains(alice!.uuid));
    expect(recentEntry.regulationStrategy, equals('walked away'));
    expect(recentEntry.severity.toString(), contains('minor'));

    // ===== TURN 2: Create commitment =====
    await t.stt('turn2');

    final commitments = await t.commitmentRepo.findAll();
    expect(commitments.isNotEmpty, isTrue, reason: 'Should have commitments');

    final commitment = commitments.last;
    expect(commitment.name.toLowerCase(), contains('meditation'));
    expect(commitment.interval, equals('daily'));
    expect(commitment.active, isTrue);

    // ===== TURN 3: Log commitment completion =====
    await t.stt('turn3');

    final logs = await t.commitmentLogRepo.findByCommitment(commitment.uuid);
    expect(logs.isNotEmpty, isTrue, reason: 'Should have commitment logs');

    final log = logs.last;
    expect(log.commitmentId, equals(commitment.uuid));
    expect(log.completed, isTrue);

    // Verify today's date
    final today = DateTime.now();
    final logDate = log.date;
    expect(logDate.year, equals(today.year));
    expect(logDate.month, equals(today.month));
    expect(logDate.day, equals(today.day));

    // ===== VERIFY: Invocations recorded =====
    final invocations = await t.invocationRepo.findAll();
    final recent = invocations
        .where((i) => i.createdAt.isAfter(
            DateTime.now().subtract(const Duration(minutes: 2))))
        .toList();

    expect(recent.isNotEmpty, isTrue, reason: 'Should have invocations logged');

    final componentTypes = recent.map((i) => i.componentType).toSet();
    expect(componentTypes.contains('llm'), isTrue,
        reason: 'LLM should be invoked');
    expect(componentTypes.contains('tts'), isTrue,
        reason: 'TTS should be invoked');
    expect(componentTypes.contains('context_selector'), isTrue,
        reason: 'ContextSelector should be invoked');
    expect(componentTypes.contains('tool_executor'), isTrue,
        reason: 'ToolExecutor should be invoked');
  },
);
