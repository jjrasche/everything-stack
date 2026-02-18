import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Declares a downloadable ONNX model.
class ModelSpec {
  final String modelId;
  final String fileName;
  final String downloadUrl;
  final List<CompanionFile> companions;

  const ModelSpec({
    required this.modelId,
    required this.fileName,
    required this.downloadUrl,
    this.companions = const [],
  });
}

/// A companion file a model needs (e.g., tokenizer vocabulary).
class CompanionFile {
  final String fileName;
  final String downloadUrl;

  const CompanionFile({
    required this.fileName,
    required this.downloadUrl,
  });
}

/// Downloads, caches, and serves ONNX model files on demand.
/// Runners call [ensure] with a [ModelSpec]; the loader handles the rest.
class ModelLoader {
  final String _cacheDir;

  ModelLoader({required String cacheDir}) : _cacheDir = cacheDir;

  /// Download model and companions if not already cached.
  Future<void> ensure(ModelSpec spec) async {
    await _download(spec.downloadUrl, await modelPath(spec));

    for (final companion in spec.companions) {
      final path = await companionPath(spec, companion.fileName);
      await _download(companion.downloadUrl, path);
    }
  }

  /// Check if model and all companions exist locally.
  Future<bool> isCached(ModelSpec spec) async {
    if (!File(await modelPath(spec)).existsSync()) return false;

    for (final companion in spec.companions) {
      if (!File(await companionPath(spec, companion.fileName)).existsSync()) {
        return false;
      }
    }
    return true;
  }

  /// Absolute path to the model's ONNX file.
  Future<String> modelPath(ModelSpec spec) async {
    return '${_modelDir(spec.modelId)}/${spec.fileName}';
  }

  /// Absolute path to a companion file.
  Future<String> companionPath(ModelSpec spec, String fileName) async {
    return '${_modelDir(spec.modelId)}/$fileName';
  }

  /// Delete a cached model and all its files.
  Future<void> evict(String modelId) async {
    final dir = Directory(_modelDir(modelId));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  String _modelDir(String modelId) => '$_cacheDir/$modelId';

  Future<void> _download(String url, String targetPath) async {
    final file = File(targetPath);
    if (file.existsSync()) return;

    await Directory(file.parent.path).create(recursive: true);
    debugPrint('ModelLoader: downloading $url');
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Download failed ($url): ${response.statusCode}');
    }

    await file.writeAsBytes(response.bodyBytes);
    debugPrint('ModelLoader: saved ${file.lengthSync()} bytes to $targetPath');
  }
}
