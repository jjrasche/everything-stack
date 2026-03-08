
import 'dart:async';
import '../../io/patterns/subscription.dart';
import 'comm_ingestion_service.dart';

/// Connects an IO Subscription to the CommIngestionService.
/// Messages from the subscription are ingested, persisted, and published.
/// Invalid payloads are routed to the error stream without stopping the bridge.
class CommSubscriptionBridge {
  final Subscription<Map<String, dynamic>> _subscription;
  final CommIngestionService _ingestionService;
  final _errorController = StreamController<Object>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _messageSubscription;

  CommSubscriptionBridge({
    required Subscription<Map<String, dynamic>> subscription,
    required CommIngestionService ingestionService,
  })  : _subscription = subscription,
        _ingestionService = ingestionService;

  Stream<Object> get errors => _errorController.stream;

  Future<void> start() async {
    await _subscription.subscribe();
    _messageSubscription = _subscription.messages.listen(_handleMessage);
  }

  Future<void> stop() async {
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    await _subscription.unsubscribe();
  }

  void dispose() {
    _messageSubscription?.cancel();
    _errorController.close();
  }

  Future<void> _handleMessage(Map<String, dynamic> payload) async {
    try {
      await _ingestionService.ingest(payload);
    } catch (error) {
      _errorController.add(error);
    }
  }
}
