import 'dart:async';

enum SubscriptionState {
  disconnected,
  connecting,
  active,
  reconnecting,
  failed,
}

/// IO pattern for one-directional event streams.
/// Connect to a source, receive messages. No sending.
///
/// Used by: Supabase Realtime, SSE, MQTT subscriptions.
abstract class Subscription<T> {
  String get id;
  SubscriptionState get state;
  Stream<SubscriptionState> get stateChanges;
  Stream<T> get messages;

  Future<void> subscribe();
  Future<void> unsubscribe();
  void dispose();
}
