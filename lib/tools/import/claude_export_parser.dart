/// # Claude Export Parser
///
/// Parses Claude.ai data export JSON files into structured conversation data.
/// Extracts human→assistant turn pairs for import as Invocations.
///
/// ## Export Format
/// Claude exports contain:
/// - conversations.json: Array of conversations with chat_messages
/// - memories.json: User profile and project memories
/// - projects.json: Project metadata
/// - users.json: Account info
///
/// ## Usage
/// ```dart
/// final parser = ClaudeExportParser();
/// final conversations = await parser.parseConversationsFile(path);
/// for (final conv in conversations.take(10)) {
///   for (final turn in conv.turns) {
///     // Create Invocation from turn
///   }
/// }
/// ```

import 'dart:convert';
import 'dart:io';

/// A parsed conversation from Claude export.
class ClaudeConversation {
  final String uuid;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ClaudeTurn> turns;

  ClaudeConversation({
    required this.uuid,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.turns,
  });

  @override
  String toString() =>
      'ClaudeConversation(name: $name, turns: ${turns.length})';
}

/// A single human→assistant turn pair.
class ClaudeTurn {
  final String humanMessageUuid;
  final String humanText;
  final DateTime humanCreatedAt;
  final String assistantText;

  ClaudeTurn({
    required this.humanMessageUuid,
    required this.humanText,
    required this.humanCreatedAt,
    required this.assistantText,
  });

  @override
  String toString() =>
      'ClaudeTurn(human: ${humanText.substring(0, humanText.length > 50 ? 50 : humanText.length)}...)';
}

/// Parser for Claude.ai data export files.
class ClaudeExportParser {
  /// Parse a conversations.json file.
  ///
  /// Returns list of conversations with extracted turns.
  /// Each turn is a human→assistant pair.
  Future<List<ClaudeConversation>> parseConversationsFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('File not found', path);
    }

    final content = await file.readAsString();
    final List<dynamic> rawConversations = jsonDecode(content);

    final conversations = <ClaudeConversation>[];

    for (final rawConv in rawConversations) {
      try {
        final conv = _parseConversation(rawConv as Map<String, dynamic>);
        if (conv.turns.isNotEmpty) {
          conversations.add(conv);
        }
      } catch (e) {
        // Skip malformed conversations
        print('⚠️ Skipping malformed conversation: $e');
      }
    }

    return conversations;
  }

  /// Parse a single conversation object.
  ClaudeConversation _parseConversation(Map<String, dynamic> raw) {
    final uuid = raw['uuid'] as String;
    final name = raw['name'] as String? ?? 'Untitled';
    final createdAt = DateTime.parse(raw['created_at'] as String);
    final updatedAt = DateTime.parse(raw['updated_at'] as String);

    final chatMessages = raw['chat_messages'] as List<dynamic>? ?? [];
    final turns = _extractTurns(chatMessages);

    return ClaudeConversation(
      uuid: uuid,
      name: name,
      createdAt: createdAt,
      updatedAt: updatedAt,
      turns: turns,
    );
  }

  /// Extract human→assistant turn pairs from chat messages.
  ///
  /// Rules:
  /// - Pairs consecutive human + assistant messages
  /// - For assistant: only include content where type == 'text' (skip thinking)
  /// - Use human message's created_at as the turn timestamp
  List<ClaudeTurn> _extractTurns(List<dynamic> chatMessages) {
    final turns = <ClaudeTurn>[];

    for (int i = 0; i < chatMessages.length - 1; i++) {
      final current = chatMessages[i] as Map<String, dynamic>;
      final next = chatMessages[i + 1] as Map<String, dynamic>;

      final currentSender = current['sender'] as String?;
      final nextSender = next['sender'] as String?;

      // Look for human → assistant pairs
      if (currentSender == 'human' && nextSender == 'assistant') {
        final humanText = _extractHumanText(current);
        final assistantText = _extractAssistantText(next);

        // Skip if either is empty
        if (humanText.isEmpty || assistantText.isEmpty) {
          continue;
        }

        final humanUuid = current['uuid'] as String? ?? '';
        final humanCreatedAt = _parseTimestamp(current);

        turns.add(ClaudeTurn(
          humanMessageUuid: humanUuid,
          humanText: humanText,
          humanCreatedAt: humanCreatedAt,
          assistantText: assistantText,
        ));
      }
    }

    return turns;
  }

  /// Extract text from human message.
  String _extractHumanText(Map<String, dynamic> message) {
    // Try content array first
    final content = message['content'] as List<dynamic>?;
    if (content != null && content.isNotEmpty) {
      final textParts = <String>[];
      for (final part in content) {
        if (part is Map<String, dynamic>) {
          final type = part['type'] as String?;
          if (type == 'text') {
            final text = part['text'] as String?;
            if (text != null && text.isNotEmpty) {
              textParts.add(text);
            }
          }
        }
      }
      if (textParts.isNotEmpty) {
        return textParts.join('\n');
      }
    }

    // Fall back to text field
    return message['text'] as String? ?? '';
  }

  /// Extract text from assistant message (only type=text, skip thinking).
  String _extractAssistantText(Map<String, dynamic> message) {
    final content = message['content'] as List<dynamic>?;
    if (content == null || content.isEmpty) {
      // Fall back to text field, but this might include thinking
      // So prefer empty if no content array
      return '';
    }

    final textParts = <String>[];
    for (final part in content) {
      if (part is Map<String, dynamic>) {
        final type = part['type'] as String?;
        // Only include 'text' type, skip 'thinking' and others
        if (type == 'text') {
          final text = part['text'] as String?;
          if (text != null && text.isNotEmpty) {
            textParts.add(text);
          }
        }
      }
    }

    return textParts.join('\n');
  }

  /// Parse timestamp from message, with fallback.
  DateTime _parseTimestamp(Map<String, dynamic> message) {
    // Try created_at first
    final createdAt = message['created_at'] as String?;
    if (createdAt != null) {
      try {
        return DateTime.parse(createdAt);
      } catch (_) {}
    }

    // Try content array for start_timestamp
    final content = message['content'] as List<dynamic>?;
    if (content != null && content.isNotEmpty) {
      final first = content.first as Map<String, dynamic>?;
      final startTimestamp = first?['start_timestamp'] as String?;
      if (startTimestamp != null) {
        try {
          return DateTime.parse(startTimestamp);
        } catch (_) {}
      }
    }

    // Fallback to now
    return DateTime.now();
  }
}
