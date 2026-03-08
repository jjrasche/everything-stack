import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/io/patterns/subscription.dart';

/// In-memory subscription for testing the pattern contract.
class TestSubscription extends Subscription<Map<String, dynamic>> {
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  SubscriptionState _state = SubscriptionState.disconnected;
  final _stateController = StreamController<SubscriptionState>.broadcast();

  @override
  String get id => 'test-sub';

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

  /// Simulate an incoming message.
  void emit(Map<String, dynamic> payload) {
    _controller.add(payload);
  }
}

void main() {
  late TestSubscription subscription;

  setUp(() {
    subscription = TestSubscription();
  });

  tearDown(() {
    subscription.dispose();
  });

  group('Subscription pattern', () {
    test('starts disconnected', () {
      expect(subscription.state, SubscriptionState.disconnected);
    });

    test('transitions to active on subscribe', () async {
      await subscription.subscribe();
      expect(subscription.state, SubscriptionState.active);
    });

    test('transitions to disconnected on unsubscribe', () async {
      await subscription.subscribe();
      await subscription.unsubscribe();
      expect(subscription.state, SubscriptionState.disconnected);
    });

    test('publishes state changes', () async {
      final states = <SubscriptionState>[];
      subscription.stateChanges.listen(states.add);

      await subscription.subscribe();
      await subscription.unsubscribe();
      await Future.delayed(Duration.zero);

      expect(states, [SubscriptionState.active, SubscriptionState.disconnected]);
    });

    test('delivers messages to listeners', () async {
      final received = <Map<String, dynamic>>[];
      subscription.messages.listen(received.add);

      await subscription.subscribe();
      subscription.emit({'source_type': 'teams', 'content_text': 'Hello'});
      subscription.emit({'source_type': 'gitlab', 'content_text': 'Build ok'});
      await Future.delayed(Duration.zero);

      expect(received, hasLength(2));
      expect(received[0]['source_type'], 'teams');
      expect(received[1]['source_type'], 'gitlab');
    });

    test('multiple listeners receive same messages', () async {
      final listener1 = <Map<String, dynamic>>[];
      final listener2 = <Map<String, dynamic>>[];
      subscription.messages.listen(listener1.add);
      subscription.messages.listen(listener2.add);

      await subscription.subscribe();
      subscription.emit({'content_text': 'broadcast'});
      await Future.delayed(Duration.zero);

      expect(listener1, hasLength(1));
      expect(listener2, hasLength(1));
    });
  });
}
