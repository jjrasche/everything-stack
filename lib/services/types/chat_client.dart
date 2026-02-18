import 'message.dart';

/// Pure-Dart chat interface for LLM calls.
///
/// Implemented by InferenceService (Flutter app) and CliChatClient (CLI scripts).
/// Stages depend on this instead of InferenceService to stay Flutter-free.
abstract class ChatClient {
  Future<String> chat({
    required String eventId,
    required List<Message> messages,
  });
}
