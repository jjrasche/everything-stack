import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/slm/model_loader.dart';

void main() {
  late Directory tempDir;
  late ModelLoader loader;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('model_loader_test_');
    loader = ModelLoader(cacheDir: tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('ModelLoader', () {
    test('isCached returns false when model not downloaded', () async {
      final spec = ModelSpec(
        modelId: 'test-model',
        fileName: 'model.onnx',
        downloadUrl: 'https://example.com/model.onnx',
      );

      expect(await loader.isCached(spec), isFalse);
    });

    test('isCached returns true after file is placed manually', () async {
      final spec = ModelSpec(
        modelId: 'test-model',
        fileName: 'model.onnx',
        downloadUrl: 'https://example.com/model.onnx',
      );

      final modelDir = Directory('${tempDir.path}/test-model');
      modelDir.createSync(recursive: true);
      File('${modelDir.path}/model.onnx')
          .writeAsBytesSync(Uint8List.fromList([1, 2, 3]));

      expect(await loader.isCached(spec), isTrue);
    });

    test('isCached returns false when companion file missing', () async {
      final spec = ModelSpec(
        modelId: 'test-model',
        fileName: 'model.onnx',
        downloadUrl: 'https://example.com/model.onnx',
        companions: [
          CompanionFile(
            fileName: 'vocab.json',
            downloadUrl: 'https://example.com/vocab.json',
          ),
        ],
      );

      final modelDir = Directory('${tempDir.path}/test-model');
      modelDir.createSync(recursive: true);
      File('${modelDir.path}/model.onnx')
          .writeAsBytesSync(Uint8List.fromList([1, 2, 3]));

      expect(await loader.isCached(spec), isFalse);
    });

    test('modelPath returns correct path for spec', () async {
      final spec = ModelSpec(
        modelId: 'test-model',
        fileName: 'model.onnx',
        downloadUrl: 'https://example.com/model.onnx',
      );

      final path = await loader.modelPath(spec);
      expect(path, '${tempDir.path}/test-model/model.onnx');
    });

    test('companionPath returns correct path', () async {
      final companion = CompanionFile(
        fileName: 'vocab.json',
        downloadUrl: 'https://example.com/vocab.json',
      );
      final spec = ModelSpec(
        modelId: 'test-model',
        fileName: 'model.onnx',
        downloadUrl: 'https://example.com/model.onnx',
        companions: [companion],
      );

      final path = await loader.companionPath(spec, 'vocab.json');
      expect(path, '${tempDir.path}/test-model/vocab.json');
    });

    test('evict deletes model directory', () async {
      final modelDir = Directory('${tempDir.path}/test-model');
      modelDir.createSync(recursive: true);
      File('${modelDir.path}/model.onnx')
          .writeAsBytesSync(Uint8List.fromList([1, 2, 3]));

      await loader.evict('test-model');
      expect(modelDir.existsSync(), isFalse);
    });

    test('evict is safe on nonexistent model', () async {
      await loader.evict('nonexistent');
      // No exception thrown
    });
  });
}
