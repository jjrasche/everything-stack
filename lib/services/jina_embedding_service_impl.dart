/// Production implementation of JinaEmbeddingService with HTTP client
///
/// Wraps the abstract JinaEmbeddingService with actual HTTP calls using dart:http.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'embedding_service.dart';

/// Create a production-ready JinaEmbeddingService with HTTP client.
///
/// Usage:
/// ```dart
/// final apiKey = 'your-jina-api-key';
/// final service = createJinaEmbeddingService(apiKey);
/// EmbeddingService.instance = service;
/// ```
JinaEmbeddingService createJinaEmbeddingService(String apiKey) {
  return JinaEmbeddingService(
    apiKey: apiKey,
    httpClient: (url, headers, body) async {
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: body,
      );

      if (response.statusCode != 200) {
        throw EmbeddingServiceException(
          'HTTP ${response.statusCode}: ${response.body}',
        );
      }

      return response.body;
    },
  );
}
