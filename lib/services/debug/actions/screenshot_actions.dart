import 'package:get_it/get_it.dart';
import '../debug_server.dart';
import '../screenshot_service.dart';
import '../vlm_analyzer.dart';
import '../ui_interaction_schema.dart';

void registerScreenshotActions(DebugServer server, GetIt getIt) {
  server.registerAction('captureScreenshot', (params) async {
    final context = params['context'] ?? 'action-request';
    final path = await ScreenshotService.instance.capture(context: context);
    return {
      'success': path != null,
      'path': path,
      'timestamp': DateTime.now().toIso8601String(),
    };
  });

  server.registerAction('listScreenshots', (params) async {
    final limit = int.tryParse(params['limit'] ?? '10') ?? 10;
    final screenshots =
        await ScreenshotService.instance.getRecentScreenshots(limit: limit);
    return {
      'count': screenshots.length,
      'screenshots': screenshots,
    };
  });

  server.registerAction('analyzeScreenshot', (params) async {
    if (!VlmAnalyzer.instance.isConfigured) {
      return {
        'error': 'VLM not configured',
        'hint': 'Set ANTHROPIC_API_KEY or OPENAI_API_KEY environment variable',
      };
    }

    String? imagePath = params['path'];
    if (imagePath == null || imagePath.isEmpty) {
      imagePath =
          await ScreenshotService.instance.capture(context: 'vlm-analysis');
      if (imagePath == null) {
        return {'error': 'Failed to capture screenshot'};
      }
    }

    final prompt = params['prompt'] ??
        'Describe this UI screenshot. Focus on: 1) What screen/state is shown, '
            '2) Any error messages or warnings, 3) Data being displayed, '
            '4) Any UI issues or unexpected states.';

    final analysis = await VlmAnalyzer.instance.analyzeScreenshot(
      imagePath: imagePath,
      prompt: prompt,
    );

    return {
      'imagePath': imagePath,
      'prompt': prompt,
      'analysis': analysis,
      'timestamp': DateTime.now().toIso8601String(),
    };
  });

  server.registerAction('analyzeStructured', (params) async {
    if (!VlmAnalyzer.instance.isConfigured) {
      return {
        'error': 'VLM not configured',
        'hint': 'Set ANTHROPIC_API_KEY or OPENAI_API_KEY environment variable',
      };
    }

    final screenName = params['screen'] ?? 'voice_assistant';
    final schema = UiInteractionSchema.forScreen(screenName);
    if (schema == null) {
      return {
        'error': 'Unknown screen: $screenName',
        'availableScreens': UiInteractionSchema.knownScreens,
      };
    }

    String? imagePath = params['path'];
    if (imagePath == null || imagePath.isEmpty) {
      imagePath = await ScreenshotService.instance
          .capture(context: 'structured-analysis');
      if (imagePath == null) {
        return {'error': 'Failed to capture screenshot'};
      }
    }

    final query = params['query'] ?? 'What is the current state?';

    try {
      final result = await schema.analyzeWithVlm(
        vlm: VlmAnalyzer.instance,
        screenshotPath: imagePath,
        query: query,
      );

      return {
        'success': true,
        'imagePath': imagePath,
        'screen': result.screenIdentified,
        'state': result.screenState,
        'data': result.data,
        'availableActions': result.availableActions,
        'errors': result.errors,
        'warnings': result.warnings,
        'hasErrors': result.hasErrors,
        'canInteract': result.canInteract,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  });
}
