/// # Timer Tools
///
/// Tool functions for timer management.
/// Registered with ToolRegistry and called by ToolExecutor.

import '../../services/tool_registry.dart';
import 'repositories/timer_repository.dart';
import 'entities/timer.dart';

// ============ Tool Functions ============

/// Set a countdown timer
Future<Map<String, dynamic>> timerSet(
  Map<String, dynamic> params,
  TimerRepository repo,
) async {
  final durationSeconds = params['duration_seconds'] as int?;
  if (durationSeconds == null || durationSeconds <= 0) {
    throw ArgumentError('duration_seconds must be a positive integer');
  }

  final label = params['label'] as String?;

  final now = DateTime.now();
  final timer = Timer(
    label: label ?? 'Timer',
    durationSeconds: durationSeconds,
    setAt: now,
    endsAt: now.add(Duration(seconds: durationSeconds)),
  );

  await repo.save(timer);

  return {
    'timer_id': timer.uuid,
    'duration_seconds': durationSeconds,
    'label': timer.label,
    'set_at': timer.setAt.toIso8601String(),
    'ends_at': timer.endsAt.toIso8601String(),
    'status': 'active',
  };
}

/// Cancel a timer
Future<Map<String, dynamic>> timerCancel(
  Map<String, dynamic> params,
  TimerRepository repo,
) async {
  final timerId = params['timer_id'] as String?;

  Timer? timer;

  if (timerId != null && timerId.isNotEmpty) {
    // Cancel specific timer by ID
    timer = await repo.findByUuid(timerId);
    if (timer == null) {
      throw ArgumentError('Timer not found: $timerId');
    }
  } else {
    // Cancel most recent active timer
    final activeTimers = await repo.findActive();
    if (activeTimers.isEmpty) {
      return {
        'cancelled': false,
        'message': 'No active timers to cancel',
      };
    }
    // Get the most recently created active timer
    activeTimers.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    timer = activeTimers.first;
  }

  timer.cancel();
  await repo.save(timer);

  return {
    'timer_id': timer.uuid,
    'label': timer.label,
    'cancelled_at': DateTime.now().toIso8601String(),
    'status': 'cancelled',
  };
}

/// Get active timers
Future<Map<String, dynamic>> timerList(
  Map<String, dynamic> params,
  TimerRepository repo,
) async {
  final activeTimers = await repo.findActive();

  return {
    'active_timers': activeTimers
        .map((t) => {
              'timer_id': t.uuid,
              'label': t.label,
              'remaining_seconds': t.remainingSeconds,
              'ends_at': t.endsAt.toIso8601String(),
            })
        .toList(),
    'count': activeTimers.length,
  };
}

// ============ Tool Registration ============

/// Register all timer tools with the registry
void registerTimerTools(ToolRegistry registry, TimerRepository repo) {
  registry.register(
    ToolDefinition(
      name: 'timer.set',
      namespace: 'timer',
      description: 'Set a countdown timer for a specified duration',
      parameters: {
        'type': 'object',
        'properties': {
          'duration_seconds': {
            'type': 'integer',
            'description': 'Duration in seconds (must be positive)',
          },
          'label': {
            'type': 'string',
            'description': 'Optional label for the timer',
          },
        },
        'required': ['duration_seconds'],
      },
    ),
    (params) => timerSet(params, repo),
  );

  registry.register(
    ToolDefinition(
      name: 'timer.cancel',
      namespace: 'timer',
      description:
          'Cancel a timer. If timer_id omitted, cancels most recent active timer',
      parameters: {
        'type': 'object',
        'properties': {
          'timer_id': {
            'type': 'string',
            'description':
                'UUID of timer to cancel. If omitted, cancels most recent active timer',
          },
        },
      },
    ),
    (params) => timerCancel(params, repo),
  );

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
    (params) => timerList(params, repo),
  );
}
