import 'dart:convert';
import 'package:get_it/get_it.dart';
import '../../event_bus.dart';
import '../../../core/event.dart';
import '../debug_server.dart';

void registerEventInjectionActions(DebugServer server, GetIt getIt) {
  server.registerAction('inject_event', (params) async {
    final eventType = params['eventType'];
    if (eventType == null || eventType.isEmpty) {
      return {'error': 'Missing eventType parameter'};
    }
    final eventBus = getIt<EventBus>();
    final correlationId = params['correlationId'] ??
        'debug-${DateTime.now().millisecondsSinceEpoch}';
    await eventBus.publish(Event(
      eventType: eventType,
      correlationId: correlationId,
      source: 'debug',
      payloadJson: params['payload'] ?? '{}',
    ));
    return {'success': true, 'eventType': eventType, 'correlationId': correlationId};
  });

  server.registerAction('inject_transcription', (params) async {
    final text = params['text'];
    if (text == null || text.isEmpty) {
      return {'error': 'Missing text parameter'};
    }
    final eventBus = getIt<EventBus>();
    final correlationId = 'debug-${DateTime.now().millisecondsSinceEpoch}';
    await eventBus.publish(Event(
      eventType: 'transcription_complete',
      correlationId: correlationId,
      source: 'debug',
      payloadJson: jsonEncode({
        'transcript': text,
        'confidence': 1.0,
      }),
    ));
    return {'success': true, 'injected': text, 'correlationId': correlationId};
  });
}
