/// # Claude Import Integration Test
///
/// Tests importing Claude.ai exports as Invocations.
/// Run with: flutter test integration_test/claude_import_test.dart -d windows

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:get_it/get_it.dart';

import 'package:everything_stack_template/bootstrap.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/core/entity_repository.dart';
import 'package:everything_stack_template/tools/import/claude_import_tool.dart';
import 'package:everything_stack_template/tools/import/claude_export_parser.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Claude Import', () {
    late EntityRepository<Invocation> invocationRepo;

    setUpAll(() async {
      // Bootstrap the app
      await initializeEverythingStack();
      await setupServiceLocator();

      invocationRepo = GetIt.instance<EntityRepository<Invocation>>();
    });

    testWidgets('parses conversations.json correctly', (tester) async {
      print('\n=== TEST: Parse Claude Export ===\n');

      const exportPath =
          'C:/Users/rasche_j/Downloads/data-2026-02-01-14-17-30-batch-0000/conversations.json';

      final parser = ClaudeExportParser();
      final conversations = await parser.parseConversationsFile(exportPath);

      print('Found ${conversations.length} conversations');

      // Show first 5
      for (final conv in conversations.take(5)) {
        print('  - "${conv.name}" (${conv.turns.length} turns)');
        if (conv.turns.isNotEmpty) {
          final firstTurn = conv.turns.first;
          print(
              '    First turn: ${firstTurn.humanText.substring(0, firstTurn.humanText.length > 60 ? 60 : firstTurn.humanText.length)}...');
        }
      }

      expect(conversations, isNotEmpty);
      expect(conversations.first.turns, isNotEmpty);

      print('\n=== PARSE TEST PASSED ===\n');
    });

    testWidgets('show imported conversation samples for test case selection', (tester) async {
      print('\n=== TEST: Show Imported Conversation Samples ===\n');

      // Get all imported invocations
      final allInvocations = await invocationRepo.findAll();
      final imported = allInvocations
          .where((inv) => inv.implementer == 'claude_import')
          .toList();

      // Sort by created date (newest first)
      imported.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      print('Found ${imported.length} imported invocations\n');
      print('=' * 80);

      // Show first 5 conversations with full turns
      for (int i = 0; i < imported.length && i < 5; i++) {
        final inv = imported[i];
        final prompt = inv.input?['prompt'] as String? ?? '';
        final response = inv.output?['response'] as String? ?? '';

        print('\n[$i] UUID: ${inv.uuid}');
        print('    Event: ${inv.eventId}');
        print('    Created: ${inv.createdAt}');
        print('');
        print('    User: ${_preview(prompt, 250)}');
        print('');
        print('    Assistant: ${_preview(response, 250)}');
        print('\n' + '-' * 80);
      }

      print('\n✅ Found ${imported.length} imported conversations.');
      print('   Use these for atomic insight extraction test cases.\n');

      expect(imported.length, greaterThan(0));
    });
  }
}

String _preview(String text, int maxLen) {
  if (text.length <= maxLen) return text;
  return text.substring(0, maxLen) + '...';
}
  });
}
