/// Abstract ONNX inference session.
/// Runners depend on this interface, not on flutter_onnxruntime directly.
/// Real implementation wraps OrtSession; tests use mocks.
abstract class InferenceSession {
  List<String> get inputNames;
  List<String> get outputNames;

  /// Run inference with named input tensors.
  /// Returns named output tensors as flat lists.
  Future<Map<String, List<dynamic>>> run(Map<String, List<int>> inputs);

  Future<void> close();
}

/// Lazy-loading cache of ONNX inference sessions.
/// Only class that imports flutter_onnxruntime in production code.
///
/// Tests replace this with a mock that returns mock InferenceSessions.
abstract class SessionPool {
  /// Load or retrieve a cached session for the given model.
  Future<InferenceSession> acquire(String modelId, String assetPath);

  /// Release a specific model's session.
  Future<void> release(String modelId);

  /// Close all cached sessions.
  Future<void> disposeAll();
}
