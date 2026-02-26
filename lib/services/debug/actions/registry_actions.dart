import 'package:get_it/get_it.dart';
import '../../../core/debug/debug.dart';
import '../debug_server.dart';

void registerRegistryActions(DebugServer server, DebugRegistry registry) {
  server.registerAction('invoke', (params) async {
    final target = params['target'];
    if (target == null || !target.contains('.')) {
      return {
        'error': 'Missing target. Format: component.action',
        'available': registry.getAllActions(),
      };
    }

    final parts = target.split('.');
    final result = await registry.invokeAction(parts[0], parts[1], params);
    return result ?? {'error': 'Unknown component or action'};
  });

  server.registerAction('listActions', (params) async {
    return {
      'components': registry.componentNames,
      'actions': registry.getAllActions(),
    };
  });
}
