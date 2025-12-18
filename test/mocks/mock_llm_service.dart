/// Mock LLMService for testing Intent Engine
/// Returns pre-configured JSON responses as token streams

import 'package:everything_stack/services/llm_service.dart';

class MockLLMService extends LLMService {
  /// Pre-configured JSON response to return
  late String mockJsonResponse;

  /// Number of times chat() has been called
  int callCount = 0;

  /// Track all calls
  final List<Map<String, dynamic>> callHistory = [];

  /// Token size for streaming (default 1 token per character)
  int tokenSize = 1;

  @override
  Future<void> initialize() async {
    // Mock initialization
  }

  @override
  Stream<String> chat({
    required List<Message> history,
    required String userMessage,
    String? systemPrompt,
    int? maxTokens,
  }) async* {
    callCount++;

    // Record call
    callHistory.add({
      'history_length': history.length,
      'userMessage': userMessage,
      'systemPrompt': systemPrompt,
      'maxTokens': maxTokens,
      'timestamp': DateTime.now(),
    });

    // Yield mock response as tokens
    // Simulate streaming by yielding chunks
    for (var i = 0; i < mockJsonResponse.length; i += tokenSize) {
      final endIndex = (i + tokenSize).clamp(0, mockJsonResponse.length);
      yield mockJsonResponse.substring(i, endIndex);
      // Small delay to simulate network latency
      await Future.delayed(Duration(milliseconds: 1));
    }
  }

  @override
  void dispose() {
    // Mock cleanup
  }

  @override
  bool get isReady => true;

  /// Configure mock to return a specific JSON response
  void setMockResponse(String jsonResponse) {
    mockJsonResponse = jsonResponse;
  }

  /// Configure mock to return a specific JSON object
  void setMockResponseFromMap(Map<String, dynamic> json) {
    mockJsonResponse = _jsonEncode(json);
  }

  /// Simple JSON encoder
  static String _jsonEncode(Map<String, dynamic> json) {
    final buffer = StringBuffer();

    _encodeValue(json, buffer);

    return buffer.toString();
  }

  static void _encodeValue(dynamic value, StringBuffer buffer) {
    if (value == null) {
      buffer.write('null');
    } else if (value is bool) {
      buffer.write(value ? 'true' : 'false');
    } else if (value is num) {
      buffer.write(value);
    } else if (value is String) {
      buffer.write('"${value.replaceAll('"', '\\"')}"');
    } else if (value is List) {
      buffer.write('[');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) buffer.write(',');
        _encodeValue(value[i], buffer);
      }
      buffer.write(']');
    } else if (value is Map) {
      buffer.write('{');
      var first = true;
      value.forEach((k, v) {
        if (!first) buffer.write(',');
        first = false;
        _encodeValue(k, buffer);
        buffer.write(':');
        _encodeValue(v, buffer);
      });
      buffer.write('}');
    }
  }

  /// Reset mock state
  void reset() {
    callCount = 0;
    callHistory.clear();
  }
}
