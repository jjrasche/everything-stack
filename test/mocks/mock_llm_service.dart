/// Mock LLMService for testing Intent Engine
/// Returns pre-configured responses without making actual LLM calls

class MockLLMService {
  /// Pre-configured response to return from next classify() call
  late Map<String, dynamic> mockResponse;

  /// Number of times classify() has been called
  int callCount = 0;

  /// The last prompt sent to classify()
  String lastPrompt = '';

  /// Track all calls made
  final List<Map<String, dynamic>> callHistory = [];

  /// Simulate a call to classify() that returns the mock response
  Future<Map<String, dynamic>> classify({
    required String utterance,
    required List<Map<String, String>> history,
    required Map<String, dynamic> entities,
  }) async {
    callCount++;

    // Construct the prompt that would be sent to LLM
    lastPrompt = _buildPrompt(utterance, history, entities);

    // Record call
    callHistory.add({
      'utterance': utterance,
      'history_length': history.length,
      'entity_keys': entities.keys.toList(),
      'timestamp': DateTime.now(),
    });

    // Return pre-configured response
    return mockResponse;
  }

  /// Build a prompt similar to what Intent Engine would send
  String _buildPrompt(
    String utterance,
    List<Map<String, String>> history,
    Map<String, dynamic> entities,
  ) {
    final buffer = StringBuffer();

    // Tool registry (simplified)
    buffer.writeln('Available tools:');
    buffer.writeln('1. REMINDER - Set a reminder for later');
    buffer.writeln('   - target (contact, required)');
    buffer.writeln('   - duration (duration, required)');
    buffer.writeln('   - message (text, optional)');
    buffer.writeln('2. MESSAGE - Send a message to a contact');
    buffer.writeln('   - target (contact, required)');
    buffer.writeln('   - content (text, required)');
    buffer.writeln('3. ALARM - Set an alarm');
    buffer.writeln('   - time (time, required)');

    // Conversation history
    if (history.isNotEmpty) {
      buffer.writeln('\nConversation history:');
      for (final turn in history) {
        buffer.writeln('${turn['role']}: ${turn['text']}');
      }
    }

    // Entities
    if (entities.isNotEmpty) {
      buffer.writeln('\nAvailable entities:');
      entities.forEach((key, values) {
        buffer.writeln('$key: $values');
      });
    }

    // User utterance
    buffer.writeln('\nUser says: $utterance');

    return buffer.toString();
  }

  /// Reset mock state for next test
  void reset() {
    callCount = 0;
    lastPrompt = '';
    callHistory.clear();
  }

  /// Configure mock to return an error (for error handling tests)
  void setError(String errorMessage) {
    mockResponse = {
      'error': errorMessage,
      'conversational_response': 'An error occurred.',
      'intents': [],
    };
  }
}
