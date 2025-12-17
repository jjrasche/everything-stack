/// Mock Tool implementations for testing
/// These don't actually do anything - just return canned success/failure responses

import 'tool_executor.dart';

class MockReminderTool implements Tool {
  @override
  String get name => 'REMINDER';

  /// Mock reminder - just returns success
  /// In real implementation, this would:
  /// - Look up contact in entities
  /// - Parse duration
  /// - Schedule reminder
  /// - Return success or failure based on system state
  @override
  Future<ToolResult> invoke(Map<String, dynamic> slots) async {
    final target = slots['target'] as String?;
    final duration = slots['duration'] as String?;
    final message = slots['message'] as String?;

    // Simulate semantic validation
    if (target != null && target.isEmpty) {
      return ToolResult(
        success: false,
        message: 'Target contact is empty',
      );
    }

    // Simulate success
    return ToolResult(
      success: true,
      message: 'Reminder set for $target in $duration${message != null ? ' with message: $message' : ''}',
      metadata: {
        'reminder_id': 'reminder_${DateTime.now().millisecondsSinceEpoch}',
        'target': target,
        'duration': duration,
        'scheduled_at': DateTime.now().toIso8601String(),
      },
    );
  }
}

class MockMessageTool implements Tool {
  @override
  String get name => 'MESSAGE';

  /// Mock message - just returns success
  /// In real implementation, this would:
  /// - Look up contact in entities
  /// - Check if contact exists
  /// - Send message via provider
  /// - Return success or failure
  @override
  Future<ToolResult> invoke(Map<String, dynamic> slots) async {
    final target = slots['target'] as String?;
    final content = slots['content'] as String?;

    // Simulate semantic validation
    if (target == null || target.isEmpty) {
      return ToolResult(
        success: false,
        message: 'No target specified',
      );
    }

    if (content == null || content.isEmpty) {
      return ToolResult(
        success: false,
        message: 'Message content is empty',
      );
    }

    // Simulate contact not found
    if (target == 'unknown_person') {
      return ToolResult(
        success: false,
        message: 'Contact "$target" not found',
      );
    }

    // Simulate success
    return ToolResult(
      success: true,
      message: 'Message sent to $target',
      metadata: {
        'message_id': 'msg_${DateTime.now().millisecondsSinceEpoch}',
        'target': target,
        'content': content,
        'sent_at': DateTime.now().toIso8601String(),
      },
    );
  }
}

class MockAlarmTool implements Tool {
  @override
  String get name => 'ALARM';

  /// Mock alarm - just returns success
  /// In real implementation, this would:
  /// - Parse time
  /// - Validate time is in future
  /// - Schedule alarm
  /// - Return success or failure
  @override
  Future<ToolResult> invoke(Map<String, dynamic> slots) async {
    final time = slots['time'];

    // Validate time was provided
    if (time == null) {
      return ToolResult(
        success: false,
        message: 'Time not specified',
      );
    }

    // Parse if string
    late DateTime alarmTime;
    if (time is DateTime) {
      alarmTime = time;
    } else if (time is String) {
      try {
        alarmTime = DateTime.parse(time);
      } catch (e) {
        return ToolResult(
          success: false,
          message: 'Invalid time format: $time',
        );
      }
    } else {
      return ToolResult(
        success: false,
        message: 'Time must be DateTime or ISO string',
      );
    }

    // Simulate validation - time must be in future
    if (alarmTime.isBefore(DateTime.now())) {
      return ToolResult(
        success: false,
        message: 'Alarm time is in the past',
      );
    }

    // Simulate success
    return ToolResult(
      success: true,
      message: 'Alarm set for ${alarmTime.toIso8601String()}',
      metadata: {
        'alarm_id': 'alarm_${DateTime.now().millisecondsSinceEpoch}',
        'time': alarmTime.toIso8601String(),
        'scheduled_at': DateTime.now().toIso8601String(),
      },
    );
  }
}

/// Create a standard set of mock tools for testing
Map<String, Tool> createMockTools() {
  return {
    'REMINDER': MockReminderTool(),
    'MESSAGE': MockMessageTool(),
    'ALARM': MockAlarmTool(),
  };
}
