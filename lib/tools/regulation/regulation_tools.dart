library;

import '../../services/tool_registry.dart';
import 'repositories/person_repository.dart';
import 'repositories/regulation_entry_repository.dart';
import 'repositories/commitment_repository.dart';
import 'repositories/commitment_log_repository.dart';
import 'entities/person.dart';
import 'entities/regulation_entry_stub.dart'
    if (dart.library.io) 'entities/regulation_entry.dart';
import 'entities/commitment_stub.dart'
    if (dart.library.io) 'entities/commitment.dart';
import 'entities/commitment_log_stub.dart'
    if (dart.library.io) 'entities/commitment_log.dart';

// ============ Tool Functions ============

/// Log a regulation event from voice transcript
/// Auto-creates Person entities if names not found
Future<Map<String, dynamic>> regulationLogEntry(
  Map<String, dynamic> params,
  PersonRepository personRepo,
  RegulationEntryRepository entryRepo,
) async {
  // Required parameters
  final entryTypeStr = params['entry_type'] as String?;
  if (entryTypeStr == null) {
    throw ArgumentError('entry_type is required');
  }

  final personNames = params['person_names'] as List<dynamic>?;
  if (personNames == null || personNames.isEmpty) {
    throw ArgumentError('person_names is required and must not be empty');
  }

  final rawTranscript = params['raw_transcript'] as String?;
  if (rawTranscript == null || rawTranscript.isEmpty) {
    throw ArgumentError('raw_transcript is required');
  }

  final severityStr = params['severity'] as String?;
  if (severityStr == null) {
    throw ArgumentError('severity is required');
  }

  // Parse enums
  EntryType? entryType;
  try {
    entryType = EntryType.values.firstWhere(
      (e) => e.toString().split('.').last == entryTypeStr,
    );
  } catch (e) {
    throw ArgumentError(
        'Invalid entry_type: $entryTypeStr. Must be one of: ${EntryType.values.map((e) => e.toString().split('.').last).join(', ')}');
  }

  Severity? severity;
  try {
    severity = Severity.values.firstWhere(
      (e) => e.toString().split('.').last == severityStr,
    );
  } catch (e) {
    throw ArgumentError(
        'Invalid severity: $severityStr. Must be one of: ${Severity.values.map((e) => e.toString().split('.').last).join(', ')}');
  }

  // Optional parameters
  final regulationStrategy = params['regulation_strategy'] as String?;
  final category = params['category'] as String?;
  final notes = params['notes'] as String?;

  // Auto-create or find persons
  final personIds = <String>[];
  for (final name in personNames) {
    final personName = name.toString();
    var person = await personRepo.findByName(personName);

    if (person == null) {
      // Auto-create person
      person = Person(
        name: personName,
        role: null, // Can be set later
        notes: 'Auto-created during regulation entry',
      );
      await personRepo.save(person);
    }

    personIds.add(person.uuid);
  }

  // Create regulation entry
  final entry = RegulationEntry(
    entryType: entryType,
    personIds: personIds,
    rawTranscript: rawTranscript,
    regulationStrategy: regulationStrategy,
    severity: severity,
    category: category,
    notes: notes,
  );

  await entryRepo.save(entry);

  return {
    'entry_id': entry.uuid,
    'entry_type': entryTypeStr,
    'person_ids': personIds,
    'person_names': personNames,
    'severity': severityStr,
    'category': category,
    'regulation_strategy': regulationStrategy,
    'created_at': entry.createdAt.toIso8601String(),
    'status': 'saved',
  };
}

/// Log commitment completion for today
Future<Map<String, dynamic>> regulationLogCommitment(
  Map<String, dynamic> params,
  CommitmentRepository commitmentRepo,
  CommitmentLogRepository logRepo,
  PersonRepository personRepo,
) async {
  // Required parameters
  final commitmentName = params['commitment_name'] as String?;
  if (commitmentName == null || commitmentName.isEmpty) {
    throw ArgumentError('commitment_name is required');
  }

  // Optional parameters
  final completed = params['completed'] as bool? ?? true;
  final personName = params['person_name'] as String?;
  final notes = params['notes'] as String?;

  // Find commitment by name (case-insensitive)
  final allCommitments = await commitmentRepo.findAll();
  final commitment = allCommitments.firstWhere(
    (c) => c.name.toLowerCase() == commitmentName.toLowerCase(),
    orElse: () => throw ArgumentError(
        'Commitment not found: $commitmentName. Use commitment.create first.'),
  );

  // Find or create person if specified
  String? personId;
  if (personName != null && personName.isNotEmpty) {
    var person = await personRepo.findByName(personName);
    if (person == null) {
      person = Person(
        name: personName,
        notes: 'Auto-created during commitment log',
      );
      await personRepo.save(person);
    }
    personId = person.uuid;
  }

  // Check if log already exists for today
  final today = DateTime.now();
  var log = await logRepo.findByCommitmentAndDate(commitment.uuid, today);

  if (log != null) {
    // Update existing log
    log.completed = completed;
    if (personId != null) log.personId = personId;
    if (notes != null) log.notes = notes;
    await logRepo.save(log);

    return {
      'log_id': log.uuid,
      'commitment_id': commitment.uuid,
      'commitment_name': commitment.name,
      'date': log.date.toIso8601String(),
      'completed': completed,
      'person_id': personId,
      'status': 'updated',
    };
  } else {
    // Create new log
    log = CommitmentLog(
      commitmentId: commitment.uuid,
      date: DateTime(today.year, today.month, today.day),
      completed: completed,
      personId: personId,
      notes: notes,
    );
    await logRepo.save(log);

    return {
      'log_id': log.uuid,
      'commitment_id': commitment.uuid,
      'commitment_name': commitment.name,
      'date': log.date.toIso8601String(),
      'completed': completed,
      'person_id': personId,
      'status': 'created',
    };
  }
}

/// Create a new commitment
Future<Map<String, dynamic>> commitmentCreate(
  Map<String, dynamic> params,
  CommitmentRepository commitmentRepo,
  PersonRepository personRepo,
) async {
  // Required parameters
  final name = params['name'] as String?;
  if (name == null || name.isEmpty) {
    throw ArgumentError('name is required');
  }

  // Optional parameters
  final rationale = params['rationale'] as String?;
  final interval = params['interval'] as String? ?? 'daily';
  final timeOfDayStr = params['time_of_day'] as String?;
  final verificationConditions =
      params['verification_conditions'] as List<dynamic>? ?? [];
  final personNames = params['person_names'] as List<dynamic>? ?? [];

  // Parse time_of_day if provided (ISO 8601 format)
  DateTime? timeOfDay;
  if (timeOfDayStr != null) {
    try {
      timeOfDay = DateTime.parse(timeOfDayStr);
    } catch (e) {
      throw ArgumentError(
          'Invalid time_of_day format. Use ISO 8601: $timeOfDayStr');
    }
  }

  // Auto-create or find persons
  final personIds = <String>[];
  for (final name in personNames) {
    final personName = name.toString();
    var person = await personRepo.findByName(personName);

    if (person == null) {
      person = Person(
        name: personName,
        notes: 'Auto-created during commitment creation',
      );
      await personRepo.save(person);
    }

    personIds.add(person.uuid);
  }

  // Create commitment
  final commitment = Commitment(
    name: name,
    rationale: rationale,
    interval: interval,
    timeOfDay: timeOfDay,
    verificationConditions:
        verificationConditions.map((v) => v.toString()).toList(),
    personIds: personIds,
    active: true,
  );

  await commitmentRepo.save(commitment);

  return {
    'commitment_id': commitment.uuid,
    'name': name,
    'interval': interval,
    'rationale': rationale,
    'verification_conditions': verificationConditions,
    'person_ids': personIds,
    'person_names': personNames,
    'active': true,
    'created_at': commitment.createdAt.toIso8601String(),
    'status': 'created',
  };
}

/// List all active commitments
Future<Map<String, dynamic>> commitmentList(
  Map<String, dynamic> params,
  CommitmentRepository commitmentRepo,
) async {
  final activeCommitments = await commitmentRepo.findActive();

  return {
    'commitments': activeCommitments
        .map((c) => {
              'commitment_id': c.uuid,
              'name': c.name,
              'interval': c.interval,
              'rationale': c.rationale,
              'verification_conditions': c.verificationConditions,
              'person_ids': c.personIds,
              'time_of_day': c.timeOfDay?.toIso8601String(),
              'active': c.active,
            })
        .toList(),
    'count': activeCommitments.length,
  };
}

// ============ Tool Registration ============

/// Register all regulation tools with the registry
void registerRegulationTools(
  ToolRegistry registry,
  PersonRepository personRepo,
  RegulationEntryRepository entryRepo,
  CommitmentRepository commitmentRepo,
  CommitmentLogRepository logRepo,
) {
  registry.register(
    ToolDefinition(
      name: 'regulation.log_entry',
      namespace: 'regulation',
      description:
          'Log a regulation event from voice transcript. Auto-creates Person entities if names not found. '
          'Entry types: dysregulationCatch, interventionCatch, madeWorse, household, rupture. '
          'Severities: minor, medium, major.',
      parameters: {
        'type': 'object',
        'properties': {
          'entry_type': {
            'type': 'string',
            'description':
                'Type of regulation event (dysregulationCatch, interventionCatch, madeWorse, household, rupture)',
            'enum': [
              'dysregulationCatch',
              'interventionCatch',
              'madeWorse',
              'household',
              'rupture'
            ],
          },
          'person_names': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Names of people involved (will auto-create if not found)',
          },
          'raw_transcript': {
            'type': 'string',
            'description': 'Exact transcript from STT',
          },
          'severity': {
            'type': 'string',
            'description': 'Severity level (minor, medium, major)',
            'enum': ['minor', 'medium', 'major'],
          },
          'regulation_strategy': {
            'type': 'string',
            'description':
                'Optional: What strategy was used (e.g., "walked away", "deep breathing")',
          },
          'category': {
            'type': 'string',
            'description':
                'Optional: Emotional category (e.g., "incredulous", "dismissive", "flooded")',
          },
          'notes': {
            'type': 'string',
            'description': 'Optional: Additional notes',
          },
        },
        'required': [
          'entry_type',
          'person_names',
          'raw_transcript',
          'severity'
        ],
      },
    ),
    (params) => regulationLogEntry(params, personRepo, entryRepo),
  );

  registry.register(
    ToolDefinition(
      name: 'regulation.log_commitment',
      namespace: 'regulation',
      description:
          'Log commitment completion for today. Creates or updates log entry for current date.',
      parameters: {
        'type': 'object',
        'properties': {
          'commitment_name': {
            'type': 'string',
            'description':
                'Name of the commitment (must exist - use commitment.create first)',
          },
          'completed': {
            'type': 'boolean',
            'description': 'Whether commitment was completed (default: true)',
          },
          'person_name': {
            'type': 'string',
            'description':
                'Optional: Name of person who completed it (auto-creates if not found)',
          },
          'notes': {
            'type': 'string',
            'description': 'Optional: Additional notes',
          },
        },
        'required': ['commitment_name'],
      },
    ),
    (params) =>
        regulationLogCommitment(params, commitmentRepo, logRepo, personRepo),
  );

  registry.register(
    ToolDefinition(
      name: 'commitment.create',
      namespace: 'commitment',
      description:
          'Create a new commitment. Intervals: daily, weekly, monthly.',
      parameters: {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'Commitment name',
          },
          'rationale': {
            'type': 'string',
            'description': 'Optional: Why this commitment matters',
          },
          'interval': {
            'type': 'string',
            'description': 'Interval: daily, weekly, monthly (default: daily)',
            'enum': ['daily', 'weekly', 'monthly'],
          },
          'time_of_day': {
            'type': 'string',
            'description':
                'Optional: Scheduled time (ISO 8601 format, e.g., "2024-01-01T09:00:00")',
          },
          'verification_conditions': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Optional: Conditions to verify completion (e.g., ["meditated for 10 minutes", "journaled"])',
          },
          'person_names': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Optional: Names of people involved (auto-creates if not found)',
          },
        },
        'required': ['name'],
      },
    ),
    (params) => commitmentCreate(params, commitmentRepo, personRepo),
  );

  registry.register(
    ToolDefinition(
      name: 'commitment.list',
      namespace: 'commitment',
      description: 'List all active commitments',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    (params) => commitmentList(params, commitmentRepo),
  );
}
