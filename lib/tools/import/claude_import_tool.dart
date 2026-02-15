
import '../../core/invocation.dart';
import '../../core/entity_repository.dart';
import 'claude_export_parser.dart';

/// Result of an import operation.
class ClaudeImportResult {
  /// Number of conversations processed.
  final int conversations;

  /// Number of turns imported as Invocations.
  final int imported;

  /// Number of turns skipped (duplicates or errors).
  final int skipped;

  /// Error messages for debugging.
  final List<String> errors;

  ClaudeImportResult({
    required this.conversations,
    required this.imported,
    required this.skipped,
    required this.errors,
  });

  @override
  String toString() =>
      'ClaudeImportResult(conversations: $conversations, imported: $imported, skipped: $skipped)';
}

/// Tool for importing Claude.ai exports into the Invocation system.
class ClaudeImportTool {
  final EntityRepository<Invocation> invocationRepo;
  final ClaudeExportParser _parser = ClaudeExportParser();

  ClaudeImportTool({required this.invocationRepo});

  /// Import conversations from a Claude export file.
  ///
  /// [conversationsPath] - Path to conversations.json file
  /// [limit] - Maximum number of conversations to import (null = all)
  /// [skipExisting] - Skip turns that already exist (by eventId/humanMessageUuid)
  Future<ClaudeImportResult> importFromExport({
    required String conversationsPath,
    int? limit,
    bool skipExisting = true,
  }) async {
    print('📥 Starting Claude import from: $conversationsPath');
    print('   Limit: ${limit ?? "none"}');

    final allConversations =
        await _parser.parseConversationsFile(conversationsPath);
    print('   Found ${allConversations.length} conversations with turns');

    final conversations =
        limit != null ? allConversations.take(limit).toList() : allConversations;

    int imported = 0;
    int skipped = 0;
    final errors = <String>[];

    for (final conv in conversations) {
      print('\n📂 Importing: "${conv.name}" (${conv.turns.length} turns)');

      for (final turn in conv.turns) {
        try {
          // Check for existing (by uuid = humanMessageUuid)
          // We use the human message UUID as the Invocation UUID for dedup
          if (skipExisting) {
            final existing = await invocationRepo.findByUuid(turn.humanMessageUuid);
            if (existing != null) {
              print('   ⏭️ Skipping existing: ${turn.humanMessageUuid}');
              skipped++;
              continue;
            }
          }

          // Use human message UUID as Invocation UUID for deduplication
          final invocation = Invocation(
            eventId: turn.humanMessageUuid,
            componentType: 'llm',
            implementer: 'claude_import',
            success: true,
            confidence: 1.0,
            input: {
              'prompt': turn.humanText,
            },
            output: {
              'response': turn.assistantText,
            },
            metadata: {
              'sourceConversationName': conv.name,
              'sourceConversationUuid': conv.uuid,
            },
          );

          // Set uuid from human message for dedup on re-import
          invocation.uuid = turn.humanMessageUuid;

          invocation.createdAt = turn.humanCreatedAt;
          invocation.updatedAt = turn.humanCreatedAt;

          // Save (triggers chunking + embedding via SemanticIndexableHandler)
          await invocationRepo.save(invocation);

          print(
              '   ✅ Imported: ${turn.humanText.substring(0, turn.humanText.length > 40 ? 40 : turn.humanText.length)}...');
          imported++;
        } catch (e) {
          print('   ❌ Error: $e');
          errors.add('${conv.name}/${turn.humanMessageUuid}: $e');
          skipped++;
        }
      }
    }

    print('\n📊 Import complete:');
    print('   Conversations: ${conversations.length}');
    print('   Imported: $imported');
    print('   Skipped: $skipped');
    if (errors.isNotEmpty) {
      print('   Errors: ${errors.length}');
    }

    return ClaudeImportResult(
      conversations: conversations.length,
      imported: imported,
      skipped: skipped,
      errors: errors,
    );
  }
}
