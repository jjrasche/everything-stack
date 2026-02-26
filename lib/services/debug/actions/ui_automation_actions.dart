import '../debug_server.dart';
import '../ui_automation_service.dart';

void registerUiAutomationActions(DebugServer server) {
  final uiAuto = UiAutomationService.instance;

  server.registerAction('ui/tap', (params) async {
    final target = params['target'];
    if (target == null || target.isEmpty) {
      return {
        'error': 'Missing target parameter',
        'hint': 'Use ?target=chat_panel.mic_button',
      };
    }
    return await uiAuto.tap(target);
  });

  server.registerAction('ui/long_press', (params) async {
    final target = params['target'];
    if (target == null || target.isEmpty) {
      return {'error': 'Missing target parameter'};
    }
    return await uiAuto.longPress(target);
  });

  server.registerAction('ui/type', (params) async {
    final target = params['target'];
    final text = params['text'];
    if (target == null || target.isEmpty) {
      return {'error': 'Missing target parameter'};
    }
    if (text == null) {
      return {'error': 'Missing text parameter'};
    }
    final submit = params['submit']?.toLowerCase() == 'true';
    return await uiAuto.type(target, text, submit: submit);
  });

  server.registerAction('ui/slide', (params) async {
    final target = params['target'];
    final valueStr = params['value'];
    if (target == null || target.isEmpty) {
      return {'error': 'Missing target parameter'};
    }
    if (valueStr == null) {
      return {'error': 'Missing value parameter (0.0-1.0)'};
    }
    final value = double.tryParse(valueStr);
    if (value == null) {
      return {'error': 'Invalid value: $valueStr (expected 0.0-1.0)'};
    }
    return await uiAuto.slide(target, value);
  });

  server.registerAction('ui/tree', (params) async {
    return uiAuto.getTree();
  });

  server.registerAction('ui/find', (params) async {
    final label = params['label'] ?? '';
    final results = uiAuto.find(label);
    return {
      'query': label,
      'count': results.length,
      'widgets': results,
    };
  });
}
