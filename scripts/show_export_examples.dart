/// Quick script to parse Claude export and show example conversations for test case selection.

import 'dart:io';
import '../lib/tools/import/claude_export_parser.dart';

void main() async {
  const exportPath =
      'C:/Users/rasche_j/Downloads/data-2026-02-01-14-17-30-batch-0000/conversations.json';

  final parser = ClaudeExportParser();
  final conversations = await parser.parseConversationsFile(exportPath);

  print('Found ${conversations.length} conversations\n');
  print('=' * 80);

  // Show first 10 with substantive content
  int shown = 0;
  for (final conv in conversations) {
    if (shown >= 10) break;
    if (conv.turns.length < 3) continue; // Skip short conversations

    shown++;
    print('\n[$shown] "${conv.name}"');
    print('    ${conv.turns.length} turns, created ${conv.createdAt}');
    print('');

    // Show first 2 turns
    for (final turn in conv.turns.take(2)) {
      final humanPreview =
          turn.humanText.length > 100 ? turn.humanText.substring(0, 100) : turn.humanText;
      final assistantPreview = turn.assistantText.length > 100
          ? turn.assistantText.substring(0, 100)
          : turn.assistantText;

      print('    User: $humanPreview...');
      print('    Assistant: $assistantPreview...');
      print('');
    }

    print('-' * 80);
  }

  print('\nDone. Pick 3-5 conversations for test cases.');
}
