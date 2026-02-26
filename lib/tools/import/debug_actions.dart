import 'package:get_it/get_it.dart';
import '../../core/entity_repository.dart';
import '../../core/invocation_repository.dart';
import '../../core/invocation.dart';
import '../../services/debug/debug_server.dart';
import 'claude_import_tool.dart';

String _truncate(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength)}...';
}

void registerConversationDebugActions(DebugServer server, GetIt getIt) {
  server.registerAction('queryImportedInvocations', (params) async {
    try {
      final repo = getIt<InvocationRepository<Invocation>>();
      final all = await repo.findAll();

      final imported =
          all.where((inv) => inv.implementer == 'claude_import').toList();

      final limit = params['limit'] != null
          ? int.tryParse(params['limit']!) ?? 10
          : 10;
      final offset = params['offset'] != null
          ? int.tryParse(params['offset']!) ?? 0
          : 0;

      final page = imported.skip(offset).take(limit).toList();

      return {
        'total': imported.length,
        'offset': offset,
        'limit': limit,
        'results': page.map((inv) => {
          'uuid': inv.uuid,
          'eventId': inv.eventId,
          'createdAt': inv.createdAt.toIso8601String(),
          'componentType': inv.componentType,
          'implementer': inv.implementer,
          'input': {
            'prompt': (inv.input?['prompt'] as String?)?.substring(
                0,
                ((inv.input?['prompt'] as String?)?.length ?? 0) > 100
                    ? 100
                    : (inv.input?['prompt'] as String?)?.length ?? 0),
          },
          'output': {
            'response': (inv.output?['response'] as String?)?.substring(
                0,
                ((inv.output?['response'] as String?)?.length ?? 0) > 100
                    ? 100
                    : (inv.output?['response'] as String?)?.length ?? 0),
          },
        }).toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  server.registerAction('importClaude', (params) async {
    final path = params['path'];
    if (path == null || path.isEmpty) {
      return {
        'error': 'Missing path parameter',
        'hint': 'Use ?path=/path/to/conversations.json',
      };
    }

    try {
      final repo = getIt<EntityRepository<Invocation>>();
      final importer = ClaudeImportTool(invocationRepo: repo);

      final limit =
          params['limit'] != null ? int.tryParse(params['limit']!) : null;

      final result = await importer.importFromExport(
        conversationsPath: path,
        limit: limit,
        skipExisting: true,
      );

      return {
        'success': true,
        'conversations': result.conversations,
        'imported': result.imported,
        'skipped': result.skipped,
        'errors': result.errors.take(10).toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  server.registerAction('listConversations', (params) async {
    try {
      final repo = getIt<InvocationRepository<Invocation>>();
      final all = await repo.findAll();

      final imported =
          all.where((inv) => inv.implementer == 'claude_import').toList();

      final Map<String, List<Invocation>> byConversation = {};
      for (final inv in imported) {
        final convUuid = inv.metadata?['sourceConversationUuid'] as String?;
        if (convUuid != null) {
          byConversation.putIfAbsent(convUuid, () => []).add(inv);
        }
      }

      final conversations = byConversation.entries.toList()
        ..sort((a, b) {
          final aFirst = a.value
              .map((inv) => inv.createdAt)
              .reduce((a, b) => a.isBefore(b) ? a : b);
          final bFirst = b.value
              .map((inv) => inv.createdAt)
              .reduce((a, b) => a.isBefore(b) ? a : b);
          return bFirst.compareTo(aFirst);
        });

      final limit = params['limit'] != null
          ? int.tryParse(params['limit']!) ?? 20
          : 20;
      final offset = params['offset'] != null
          ? int.tryParse(params['offset']!) ?? 0
          : 0;

      final page = conversations.skip(offset).take(limit).toList();

      return {
        'total': conversations.length,
        'offset': offset,
        'limit': limit,
        'conversations': page.map((entry) {
          final turns = entry.value
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          final first = turns.first;
          final last = turns.last;
          final firstPrompt = first.input?['prompt'] as String? ?? '';
          final lastResponse = last.output?['response'] as String? ?? '';

          return {
            'uuid': entry.key,
            'name':
                first.metadata?['sourceConversationName'] ?? 'Unnamed',
            'turnCount': turns.length,
            'firstTurnDate': first.createdAt.toIso8601String(),
            'lastTurnDate': last.createdAt.toIso8601String(),
            'firstPromptPreview': _truncate(firstPrompt, 80),
            'lastResponsePreview': _truncate(lastResponse, 80),
          };
        }).toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  server.registerAction('getConversation', (params) async {
    final convUuid = params['uuid'];
    if (convUuid == null || convUuid.isEmpty) {
      return {
        'error': 'Missing uuid parameter',
        'hint': 'Use ?uuid=<conversation-uuid>',
      };
    }

    try {
      final repo = getIt<InvocationRepository<Invocation>>();
      final all = await repo.findAll();

      final turns = all
          .where((inv) =>
              inv.implementer == 'claude_import' &&
              inv.metadata?['sourceConversationUuid'] == convUuid)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      if (turns.isEmpty) {
        return {'error': 'Conversation not found', 'uuid': convUuid};
      }

      int totalChars = 0;
      for (final turn in turns) {
        totalChars += (turn.input?['prompt'] as String?)?.length ?? 0;
        totalChars += (turn.output?['response'] as String?)?.length ?? 0;
      }
      final estimatedTokens = (totalChars / 4).round();

      return {
        'uuid': convUuid,
        'name':
            turns.first.metadata?['sourceConversationName'] ?? 'Unnamed',
        'turnCount': turns.length,
        'estimatedTokens': estimatedTokens,
        'firstTurnDate': turns.first.createdAt.toIso8601String(),
        'lastTurnDate': turns.last.createdAt.toIso8601String(),
        'turns': turns.map((inv) => {
          'uuid': inv.uuid,
          'createdAt': inv.createdAt.toIso8601String(),
          'prompt': inv.input?['prompt'],
          'response': inv.output?['response'],
        }).toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  server.registerAction('exportConversationForTest', (params) async {
    final convUuid = params['uuid'];
    if (convUuid == null || convUuid.isEmpty) {
      return {
        'error': 'Missing uuid parameter',
        'hint': 'Use ?uuid=<conversation-uuid>',
      };
    }

    try {
      final repo = getIt<InvocationRepository<Invocation>>();
      final all = await repo.findAll();

      final turns = all
          .where((inv) =>
              inv.implementer == 'claude_import' &&
              inv.metadata?['sourceConversationUuid'] == convUuid)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      if (turns.isEmpty) {
        return {'error': 'Conversation not found', 'uuid': convUuid};
      }

      return {
        'id': 'conv_${convUuid.substring(0, 8)}',
        'description':
            'TODO: Add description of what makes this conversation interesting',
        'conversation': {
          'uuid': convUuid,
          'name':
              turns.first.metadata?['sourceConversationName'] ?? 'Unnamed',
          'turn_count': turns.length,
          'first_turn_date': turns.first.createdAt.toIso8601String(),
          'last_turn_date': turns.last.createdAt.toIso8601String(),
          'turns': turns.asMap().entries.map((entry) {
            final idx = entry.key;
            final inv = entry.value;
            return {
              'turn_index': idx,
              'uuid': inv.uuid,
              'created_at': inv.createdAt.toIso8601String(),
              'prompt': inv.input?['prompt'],
              'response': inv.output?['response'],
            };
          }).toList(),
        },
        'expected_insights': [
          {
            'content': 'TODO: [Fact]. Because [reason].',
            'source_turns': [0],
            'notes':
                'Add expected insights to extract from this conversation',
          }
        ],
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });

  server.registerAction('analyzeConversationsForTests', (params) async {
    try {
      final repo = getIt<InvocationRepository<Invocation>>();
      final all = await repo.findAll();

      final imported =
          all.where((inv) => inv.implementer == 'claude_import').toList();

      final Map<String, List<Invocation>> byConversation = {};
      for (final inv in imported) {
        final convUuid = inv.metadata?['sourceConversationUuid'] as String?;
        if (convUuid != null) {
          byConversation.putIfAbsent(convUuid, () => []).add(inv);
        }
      }

      final scored = byConversation.entries.map((entry) {
        final turns = entry.value
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        final turnCount = turns.length;
        int totalChars = 0;
        int technicalWords = 0;

        for (final turn in turns) {
          final prompt = turn.input?['prompt'] as String? ?? '';
          final response = turn.output?['response'] as String? ?? '';
          totalChars += prompt.length + response.length;

          final text = '$prompt $response'.toLowerCase();
          if (text.contains(RegExp(
              r'\b(function|class|api|database|service|component|implement|algorithm|pattern|architecture)\b'))) {
            technicalWords++;
          }
        }

        final avgCharsPerTurn = totalChars / turnCount;
        final estimatedTokens = (totalChars / 4).round();

        double score = 0;
        if (turnCount >= 3) score += 30;
        if (turnCount >= 5) score += 20;
        if (avgCharsPerTurn >= 200 && avgCharsPerTurn <= 1000) score += 30;
        score += (technicalWords / turnCount) * 20;

        final firstPrompt = turns.first.input?['prompt'] as String? ?? '';

        return {
          'uuid': entry.key,
          'name':
              turns.first.metadata?['sourceConversationName'] ?? 'Unnamed',
          'turnCount': turnCount,
          'estimatedTokens': estimatedTokens,
          'avgCharsPerTurn': avgCharsPerTurn.round(),
          'technicalDensity': (technicalWords / turnCount * 100).round(),
          'score': score.round(),
          'firstPrompt': _truncate(firstPrompt, 100),
        };
      }).toList()
        ..sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

      final limit = params['limit'] != null
          ? int.tryParse(params['limit']!) ?? 10
          : 10;

      return {
        'total': scored.length,
        'criteria': {
          'turnCount': '3+ turns preferred, 5+ excellent',
          'avgLength': '200-1000 chars/turn ideal',
          'technical': 'Higher density of technical terms better',
        },
        'topCandidates': scored.take(limit).toList(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });
}
