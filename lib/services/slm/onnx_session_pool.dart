import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'session_pool.dart';

/// Wraps OrtSession to implement InferenceSession.
class _OnnxInferenceSession implements InferenceSession {
  final OrtSession _session;

  _OnnxInferenceSession(this._session);

  @override
  List<String> get inputNames => _session.inputNames;

  @override
  List<String> get outputNames => _session.outputNames;

  @override
  Future<Map<String, List<dynamic>>> run(Map<String, List<int>> inputs) async {
    final ortInputs = <String, OrtValue>{};
    try {
      for (final entry in inputs.entries) {
        ortInputs[entry.key] = await OrtValue.fromList(
          entry.value,
          [1, entry.value.length],
        );
      }

      final ortOutputs = await _session.run(ortInputs);
      final results = <String, List<dynamic>>{};

      for (final entry in ortOutputs.entries) {
        results[entry.key] = await entry.value.asFlattenedList();
        await entry.value.dispose();
      }

      return results;
    } finally {
      for (final tensor in ortInputs.values) {
        await tensor.dispose();
      }
    }
  }

  @override
  Future<void> close() async => _session.close();
}

/// Real ONNX Runtime session pool.
/// Caches sessions by modelId. Lazy-loads from Flutter assets.
class OnnxSessionPool implements SessionPool {
  final OnnxRuntime _runtime = OnnxRuntime();
  final Map<String, _OnnxInferenceSession> _sessions = {};

  @override
  Future<InferenceSession> acquire(String modelId, String assetPath) async {
    if (_sessions.containsKey(modelId)) return _sessions[modelId]!;

    final session = await _runtime.createSessionFromAsset(assetPath);
    final wrapped = _OnnxInferenceSession(session);
    _sessions[modelId] = wrapped;
    return wrapped;
  }

  @override
  Future<void> release(String modelId) async {
    final session = _sessions.remove(modelId);
    if (session != null) await session.close();
  }

  @override
  Future<void> disposeAll() async {
    for (final session in _sessions.values) {
      await session.close();
    }
    _sessions.clear();
  }
}
