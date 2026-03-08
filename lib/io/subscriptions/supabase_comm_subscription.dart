
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../patterns/subscription.dart';

/// Subscribes to the comm_events table via Supabase Realtime.
/// Emits the new row as a Map<String, dynamic> on each INSERT.
class SupabaseCommSubscription extends Subscription<Map<String, dynamic>> {
  final SupabaseClient _client;
  final String _table;
  final String _schema;

  RealtimeChannel? _channel;
  SubscriptionState _state = SubscriptionState.disconnected;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<SubscriptionState>.broadcast();

  SupabaseCommSubscription({
    required SupabaseClient client,
    String table = 'comm_events',
    String schema = 'public',
  })  : _client = client,
        _table = table,
        _schema = schema;

  @override
  String get id => 'supabase-realtime-$_table';

  @override
  SubscriptionState get state => _state;

  @override
  Stream<SubscriptionState> get stateChanges => _stateController.stream;

  @override
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  @override
  Future<void> subscribe() async {
    _setState(SubscriptionState.connecting);

    _channel = _client
        .channel('comm_events_inserts')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: _schema,
          table: _table,
          callback: _handleChange,
        )
        .subscribe((status, [error]) {
      _handleStatus(status, error);
    });
  }

  @override
  Future<void> unsubscribe() async {
    if (_channel != null) {
      await _client.removeChannel(_channel!);
      _channel = null;
    }
    _setState(SubscriptionState.disconnected);
  }

  @override
  void dispose() {
    _messageController.close();
    _stateController.close();
  }

  void _handleChange(PostgresChangePayload payload) {
    _messageController.add(payload.newRecord);
  }

  void _handleStatus(RealtimeSubscribeStatus status, Object? error) {
    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        _setState(SubscriptionState.active);
      case RealtimeSubscribeStatus.timedOut:
        _setState(SubscriptionState.reconnecting);
      case RealtimeSubscribeStatus.channelError:
        _setState(SubscriptionState.failed);
      case RealtimeSubscribeStatus.closed:
        _setState(SubscriptionState.disconnected);
    }
  }

  void _setState(SubscriptionState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }
}
