/// # VLM Analyzer
///
/// Analyzes screenshots using a Vision Language Model.
/// Enables AI-driven visual debugging without human screenshot review.
///
/// ## Usage
/// ```dart
/// final analysis = await VlmAnalyzer.instance.analyzeScreenshot(
///   imagePath: 'logs/screenshots/2024-01-15-debug.png',
///   prompt: 'Describe any error messages or unexpected UI states',
/// );
/// print(analysis); // "The screen shows a search results list with..."
/// ```

import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class VlmAnalyzer {
  static final VlmAnalyzer instance = VlmAnalyzer._();
  VlmAnalyzer._();

  String? _apiKey;
  String _provider = 'anthropic'; // 'anthropic' or 'openai'

  /// Initialize with API key. Call during bootstrap if VLM analysis is needed.
  void initialize({required String apiKey, String provider = 'anthropic'}) {
    _apiKey = apiKey;
    _provider = provider;
  }

  /// Auto-initialize from dotenv/environment
  void autoInitialize() {
    // Try dotenv first, then OS environment
    String? anthropicKey = _getEnvValue('ANTHROPIC_API_KEY');
    String? openaiKey = _getEnvValue('OPENAI_API_KEY');

    if (anthropicKey != null && anthropicKey.isNotEmpty) {
      initialize(apiKey: anthropicKey, provider: 'anthropic');
    } else if (openaiKey != null && openaiKey.isNotEmpty) {
      initialize(apiKey: openaiKey, provider: 'openai');
    }
  }

  /// Get value from dotenv or OS environment
  String? _getEnvValue(String key) {
    // Try dotenv first
    try {
      final value = dotenv.maybeGet(key);
      if (value != null && value.isNotEmpty) return value;
    } catch (e) {
      // dotenv not initialized
    }
    // Fall back to OS environment
    return Platform.environment[key];
  }

  /// Check if VLM is configured
  bool get isConfigured => _apiKey != null && _apiKey!.isNotEmpty;

  /// Analyze a screenshot with a prompt
  ///
  /// Returns text description of what the VLM sees.
  /// Returns error message if VLM is not configured or analysis fails.
  Future<String> analyzeScreenshot({
    required String imagePath,
    String prompt = 'Describe what you see in this UI screenshot. Focus on any errors, unexpected states, or notable UI elements.',
  }) async {
    if (!isConfigured) {
      return 'Error: VLM not configured. Set ANTHROPIC_API_KEY or OPENAI_API_KEY in environment.';
    }

    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return 'Error: Screenshot file not found: $imagePath';
      }

      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);

      if (_provider == 'anthropic') {
        return await _analyzeWithClaude(base64Image, prompt);
      } else {
        return await _analyzeWithOpenAI(base64Image, prompt);
      }
    } catch (e) {
      return 'Error analyzing screenshot: $e';
    }
  }

  /// Analyze using Claude's vision API
  Future<String> _analyzeWithClaude(String base64Image, String prompt) async {
    final response = await http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': _apiKey!,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': 'claude-sonnet-4-20250514',
        'max_tokens': 1024,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': 'image/png',
                  'data': base64Image,
                },
              },
              {
                'type': 'text',
                'text': prompt,
              },
            ],
          },
        ],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final content = data['content'] as List;
      if (content.isNotEmpty && content[0]['type'] == 'text') {
        return content[0]['text'] as String;
      }
      return 'Error: Unexpected response format';
    } else {
      return 'Error: API returned ${response.statusCode}: ${response.body}';
    }
  }

  /// Analyze using OpenAI's vision API
  Future<String> _analyzeWithOpenAI(String base64Image, String prompt) async {
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'model': 'gpt-4o',
        'max_tokens': 1024,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': prompt,
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/png;base64,$base64Image',
                },
              },
            ],
          },
        ],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final choices = data['choices'] as List;
      if (choices.isNotEmpty) {
        return choices[0]['message']['content'] as String;
      }
      return 'Error: No response content';
    } else {
      return 'Error: API returned ${response.statusCode}: ${response.body}';
    }
  }
}
