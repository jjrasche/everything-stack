import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/io/patterns/subscription.dart';
import 'package:everything_stack_template/tools/comms/entities/comm_event.dart';
import 'package:everything_stack_template/tools/comms/repositories/comm_event_repository.dart';
import 'package:everything_stack_template/tools/comms/comm_ingestion_service.dart';
import 'package:everything_stack_template/tools/comms/comm_subscription_bridge.dart';
import 'package:everything_stack_template/persistence/objectbox/comm_event_objectbox_adapter.dart';
import 'package:everything_stack_template/objectbox.g.dart';

/// Test subscription that emits payloads on demand.
class FakeRealtimeSubscription extends Subscription<Map<String, dynamic>> {
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<SubscriptionState>.broadcast();
  SubscriptionState _state = SubscriptionState.disconnected;

  @override
  String get id => 'fake-realtime';

  @override
  SubscriptionState get state => _state;

  @override
  Stream<SubscriptionState> get stateChanges => _stateController.stream;

  @override
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  @override
  Future<void> subscribe() async {
    _state = SubscriptionState.active;
    _stateController.add(_state);
  }

  @override
  Future<void> unsubscribe() async {
    _state = SubscriptionState.disconnected;
    _stateController.add(_state);
  }

  @override
  void dispose() {
    _controller.close();
    _stateController.close();
  }

  void emit(Map<String, dynamic> payload) => _controller.add(payload);
}

void main() {
  late Store store;
  late CommEventRepository repo;
  late CommIngestionService ingestionService;
  late FakeRealtimeSubscription subscription;
  late CommSubscriptionBridge bridge;

  setUp(() async {
    store = await openStore(
        directory: 'test_db_wiring_${DateTime.now().millisecondsSinceEpoch}');
    final adapter = CommEventObjectBoxAdapter(store);
    repo = CommEventRepository.withAdapter(adapter);
    ingestionService = CommIngestionService(repository: repo);
    subscription = FakeRealtimeSubscription();
    bridge = CommSubscriptionBridge(
      subscription: subscription,
      ingestionService: ingestionService,
    );
  });

  tearDown(() {
    bridge.dispose();
    ingestionService.dispose();
    subscription.dispose();
    store.close();
  });

  group('CommSubscriptionBridge', () {
    test('subscription messages flow through to persisted CommEvents', () async {
      await bridge.start();

      subscription.emit({
        'source_type': 'teams',
        'source_id': 'msg-001',
        'content_text': 'Review the PR please',
        'sender_name': 'Dave Wilson',
      });

      // Allow async processing
      await Future.delayed(const Duration(milliseconds: 50));

      final events = await repo.findAll();
      expect(events, hasLength(1));
      expect(events.first.sourceType, 'teams');
      expect(events.first.contentText, 'Review the PR please');
      expect(events.first.senderName, 'Dave Wilson');
    });

    test('multiple messages each become persisted events', () async {
      await bridge.start();

      subscription.emit({
        'source_type': 'teams',
        'source_id': 'msg-001',
        'content_text': 'First message',
      });
      subscription.emit({
        'source_type': 'gitlab',
        'source_id': 'pipeline-001',
        'content_text': 'Pipeline failed',
      });

      await Future.delayed(const Duration(milliseconds: 50));

      final events = await repo.findAll();
      expect(events, hasLength(2));
    });

    test('stop cancels subscription and stops processing', () async {
      await bridge.start();
      await bridge.stop();

      subscription.emit({
        'source_type': 'teams',
        'source_id': 'msg-001',
        'content_text': 'Should not persist',
      });

      await Future.delayed(const Duration(milliseconds: 50));

      final events = await repo.findAll();
      expect(events, isEmpty);
    });

    test('invalid payloads do not crash the bridge', () async {
      final errors = <Object>[];
      bridge.errors.listen(errors.add);

      await bridge.start();

      // Missing required fields
      subscription.emit({'source_type': 'teams'});

      // Valid message after invalid one
      subscription.emit({
        'source_type': 'teams',
        'source_id': 'msg-002',
        'content_text': 'Valid message',
      });

      await Future.delayed(const Duration(milliseconds: 50));

      final events = await repo.findAll();
      expect(events, hasLength(1));
      expect(events.first.sourceId, 'msg-002');
      expect(errors, hasLength(1));
    });
  });
}
