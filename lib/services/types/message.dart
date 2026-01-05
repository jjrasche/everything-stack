/// # Message
///
/// Typed representation of a conversation message.
/// Used by LLM service for type-safe message handling.

import 'dart:math' show min;

/// A single message in a conversation.
class Message {
  /// Who is speaking: 'user', 'assistant', or 'system'.
  final String role;

  /// The message content/text.
  final String content;

  /// When this message was created (optional).
  final DateTime? timestamp;

  Message({
    required this.role,
    required this.content,
    this.timestamp,
  });

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
  };

  /// Deserialize from JSON.
  factory Message.fromJson(Map<String, dynamic> json) => Message(
    role: json['role'] as String,
    content: json['content'] as String,
    timestamp: json['timestamp'] != null
        ? DateTime.parse(json['timestamp'] as String)
        : null,
  );

  @override
  String toString() => 'Message(role: $role, content: ${content.substring(0, min(50, content.length))}...)';
}
