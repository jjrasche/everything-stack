import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:everything_stack_template/services/embedding_service.dart';

/// Fixture capture utilities for smoke testing.
///
/// Use during smoke testing to capture real API responses as golden data for CI tests.
/// Example:
/// ```dart
/// if (isSmoke) {
///   final captured = <String, List<double>>{};
///   for (final text in textsToCapture) {
///     await captureEmbedding(captured, text);
///   }
///   await saveEmbeddingFixture(captured, 'invocation_embeddings.json');
/// }
/// ```

/// Capture embedding from real API and store in memory.
Future<void> captureEmbedding(
  Map<String, List<double>> captured,
  String text,
) async {
  final embeddingService = EmbeddingService.instance;
  try {
    final embedding = await embeddingService.generate(text);
    captured[text] = embedding;
    debugPrint('  📡 Captured: $text (${embedding.length} dims)');
  } catch (e) {
    debugPrint('  ⚠️ Failed to capture: $text - $e');
  }
}

/// Save captured embeddings to fixture file in test/fixtures/.
///
/// Creates directory if needed. Overwrites existing fixture.
Future<void> saveEmbeddingFixture(
  Map<String, List<double>> captured,
  String fixtureFilename,
) async {
  if (captured.isEmpty) {
    debugPrint('⚠️ No embeddings captured');
    return;
  }

  try {
    final fixturePath = '${Directory.current.path}/test/fixtures/$fixtureFilename';
    final json = jsonEncode(captured);
    final fixtureFile = File(fixturePath);

    // Create directory if needed
    final fixtureDir = fixtureFile.parent;
    if (!fixtureDir.existsSync()) {
      fixtureDir.createSync(recursive: true);
      debugPrint('  📁 Created directory: ${fixtureDir.path}');
    }

    fixtureFile.writeAsStringSync(json);
    debugPrint('  ✅ Fixture saved to: $fixturePath');
    debugPrint('  📊 Embedding vectors: ${captured.length}');
    debugPrint('  📐 Vector dimensions: ${captured.values.first.length}');
  } catch (e) {
    debugPrint('  ❌ Failed to save fixture: $e');
  }
}
