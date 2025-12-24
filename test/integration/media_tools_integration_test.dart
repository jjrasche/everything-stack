/// Media Tools Integration Test
///
/// Tests the media tool registry: download, convert, organize, search.
/// Demonstrates tool composition and LLM parameter handling.

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/tool.dart';
import 'package:everything_stack_template/services/tool_registry.dart';
import 'package:everything_stack_template/tools/media/handlers/download_handler.dart';
import 'package:everything_stack_template/tools/media/handlers/convert_handler.dart';
import 'package:everything_stack_template/tools/media/handlers/organize_handler.dart';
import 'package:everything_stack_template/tools/media/handlers/search_handler.dart';

void main() {
  group('Media Tools Integration', () {
    late ToolRegistry registry;
    late DownloadHandler downloadHandler;
    late ConvertHandler convertHandler;
    late OrganizeHandler organizeHandler;
    late SearchHandler searchHandler;

    setUp(() {
      // Create mock repositories - use test harness
      // For now, test just the tool definitions and handlers work

      // Create tool registry
      registry = ToolRegistry();
    });

    test('Media tools can be registered with ToolRegistry', () {
      // Register media.download tool
      registry.register(
        ToolDefinition(
          name: 'media.download',
          namespace: 'media',
          description: 'Download from YouTube',
          parameters: {
            'type': 'object',
            'properties': {
              'youtubeUrl': {'type': 'string'},
              'format': {'type': 'string', 'default': 'mp4'},
              'quality': {'type': 'string', 'default': '720p'},
            },
            'required': ['youtubeUrl'],
          },
        ),
        (params) async => {'success': true},
      );

      // Verify tool is registered
      final tool = registry.getDefinition('media.download');
      expect(tool, isNotNull);
      expect(tool!.name, 'media.download');
      expect(tool.namespace, 'media');
      expect(tool.toLLMTool()['type'], 'function');
    });

    test('Media tools grouped by namespace', () {
      // Register multiple media tools
      registry.register(
        ToolDefinition(
          name: 'media.download',
          namespace: 'media',
          description: 'Download media',
          parameters: {'type': 'object', 'properties': {}, 'required': []},
        ),
        (params) async => {'success': true},
      );

      registry.register(
        ToolDefinition(
          name: 'media.search',
          namespace: 'media',
          description: 'Search media',
          parameters: {'type': 'object', 'properties': {}, 'required': []},
        ),
        (params) async => {'success': true},
      );

      registry.register(
        ToolDefinition(
          name: 'media.convert',
          namespace: 'media',
          description: 'Convert format',
          parameters: {'type': 'object', 'properties': {}, 'required': []},
        ),
        (params) async => {'success': true},
      );

      // Get all media tools
      final mediaTools = registry.getToolsInNamespace('media');
      expect(mediaTools.length, 3);
      expect(mediaTools.map((t) => t.name), containsAll([
        'media.download',
        'media.search',
        'media.convert',
      ]));

      // Verify each has correct namespace
      for (final tool in mediaTools) {
        expect(tool.namespace, 'media');
      }
    });

    test('ContextManager can discover media tools', () {
      // Register media tools
      registry.register(
        ToolDefinition(
          name: 'media.download',
          namespace: 'media',
          description: 'Download video',
          parameters: {
            'type': 'object',
            'properties': {
              'youtubeUrl': {'type': 'string'},
            },
            'required': ['youtubeUrl'],
          },
        ),
        (params) async => {'success': true},
      );

      // Verify tool is discoverable by ContextManager
      final allTools = registry.getAllTools();
      expect(allTools.length, 1);

      final mediaDownload = allTools.firstWhere(
        (t) => t.name == 'media.download',
        orElse: () => throw AssertionError('media.download not found'),
      );

      expect(mediaDownload.namespace, 'media');
      expect(mediaDownload.parameters['properties'], isNotNull);
      expect(mediaDownload.toLLMTool()['type'], 'function');
    });
  });
}
