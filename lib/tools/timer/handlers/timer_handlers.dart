/// # Timer Tool Handlers
///
/// ## What it does
/// Registers timer tools (set, cancel, list) with ToolRegistry.
/// Each handler is a Dart function that operates on TimerRepository.
///
/// ## Tools
/// - timer.set: Create a new countdown timer
/// - timer.cancel: Cancel an active timer
/// - timer.list: List active timers
///
/// ## Usage
/// ```dart
/// final registry = ToolRegistry();
/// registerTimerTools(registry, timerRepo);
/// ```

import '../../../services/tool_registry.dart';
import '../repositories/timer_repository.dart';
import '../entities/timer.dart';

/// Register all timer tools with the registry
void registerTimerTools(ToolRegistry registry, TimerRepository timerRepo) {
  // timer.set
  registry.register(
    ToolDefinition(
      name: 'timer.set',
      namespace: 'timer',
      description: 'Set a countdown timer with a label and duration in seconds',
      parameters: {
        'type': 'object',
        'properties': {
          'label': {
            'type': 'string',
            'description': 'Timer label (e.g., "5 minute break", "pasta timer")',
          },
          'durationSeconds': {
            'type': 'integer',
            'description': 'Timer duration in seconds',
            'minimum': 1,
          },
        },
        'required': ['label', 'durationSeconds'],
      },
    ),
    (params) async {
      final now = DateTime.now();
      final durationSeconds = params['durationSeconds'] as int;
      final timer = Timer(
        label: params['label'] as String,
        durationSeconds: durationSeconds,
        setAt: now,
        endsAt: now.add(Duration(seconds: durationSeconds)),
      );

      await timerRepo.save(timer);

      return {
        'success': true,
        'id': timer.uuid,
        'label': timer.label,
        'durationSeconds': timer.durationSeconds,
        'endsAt': timer.endsAt.toIso8601String(),
        'status': 'set',
      };
    },
  );

  // timer.cancel
  registry.register(
    ToolDefinition(
      name: 'timer.cancel',
      namespace: 'timer',
      description: 'Cancel an active timer by UUID or label',
      parameters: {
        'type': 'object',
        'properties': {
          'id': {
            'type': 'string',
            'description': 'Timer UUID (optional if label provided)',
          },
          'label': {
            'type': 'string',
            'description': 'Timer label (optional if id provided)',
          },
        },
      },
    ),
    (params) async {
      Timer? timer;

      if (params['id'] != null) {
        timer = await timerRepo.findByUuid(params['id'] as String);
      } else if (params['label'] != null) {
        timer = await timerRepo.findByLabel(params['label'] as String);
      }

      if (timer == null) {
        return {
          'success': false,
          'error': 'Timer not found',
        };
      }

      if (timer.fired) {
        return {
          'success': false,
          'error': 'Timer already fired or cancelled',
          'id': timer.uuid,
        };
      }

      timer.cancel();
      await timerRepo.save(timer);

      return {
        'success': true,
        'id': timer.uuid,
        'label': timer.label,
        'status': 'cancelled',
      };
    },
  );

  // timer.list
  registry.register(
    ToolDefinition(
      name: 'timer.list',
      namespace: 'timer',
      description: 'List all active timers',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    (params) async {
      final activeTimers = await timerRepo.findActive();

      return {
        'success': true,
        'count': activeTimers.length,
        'timers': activeTimers.map((timer) {
          return {
            'id': timer.uuid,
            'label': timer.label,
            'remainingSeconds': timer.remainingSeconds,
            'endsAt': timer.endsAt.toIso8601String(),
          };
        }).toList(),
      };
    },
  );
}
