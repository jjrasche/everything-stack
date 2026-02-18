/// Generate baseline evaluations for golden test conversations.
///
/// Reads golden test data from lib/training/extraction/golden/*.json,
/// runs extraction + evaluation, and saves results to
/// lib/training/extraction/golden/evaluations/baseline_results.json.
///
/// Usage:
///   dart run scripts/generate_golden_evaluations.dart [--dir=lib/training/extraction/golden]
///
/// Prerequisites:
///   - Golden conversations exported via query_imported_conversations.dart --export
///   - App must be running (uses debug server for extraction + evaluation)
///
/// Alternative: Use debug server directly:
///   curl "http://localhost:9999/action/invoke?target=extractor.extractFromConversation&uuid=<uuid>"

import 'dart:io';
import 'dart:convert';

void main(List<String> args) async {
  print('📊 Generating baseline evaluations for golden test data...\n');

  final goldenDir = _parseArg(args, 'dir', 'lib/training/extraction/golden');
  final outputDir = 'lib/training/extraction/golden/evaluations';
  final serverUrl = _parseArg(args, 'server', 'http://localhost:9999');

  // Ensure output directory exists
  final outputDirectory = Directory(outputDir);
  if (!await outputDirectory.exists()) {
    await outputDirectory.create(recursive: true);
  }

  // Load golden conversations
  final goldenDirectory = Directory(goldenDir);
  if (!await goldenDirectory.exists()) {
    print('❌ Golden data directory not found: $goldenDir');
    print('   Run first: dart run scripts/query_imported_conversations.dart --export=<uuids>');
    exit(1);
  }

  final goldenFiles = await goldenDirectory
      .list()
      .where((entity) => entity.path.endsWith('.json'))
      .toList();

  if (goldenFiles.isEmpty) {
    print('❌ No golden test files found in $goldenDir');
    exit(1);
  }

  print('📂 Found ${goldenFiles.length} golden test files\n');

  // Check debug server connectivity
  try {
    final healthCheck = await _httpGet('$serverUrl/health');
    if (healthCheck == null) {
      print('❌ Debug server not responding at $serverUrl');
      print('   Start the app first: flutter run -d windows');
      exit(1);
    }
    print('✅ Debug server connected\n');
  } catch (e) {
    print('❌ Cannot connect to debug server: $e');
    print('   Start the app first: flutter run -d windows');
    exit(1);
  }

  final results = <Map<String, dynamic>>[];
  final allDimensionRates = <String, List<double>>{};

  for (final file in goldenFiles) {
    final filename = file.path.split(Platform.pathSeparator).last;
    print('Processing: $filename');

    try {
      final content = await File(file.path).readAsString();
      final goldenData = jsonDecode(content) as Map<String, dynamic>;
      final conversation = goldenData['conversation'] as Map<String, dynamic>;
      final convUuid = conversation['uuid'] as String;
      final convName = conversation['name'] as String? ?? 'Unnamed';
      final turns = conversation['turns'] as List<dynamic>;

      // Run extraction via debug server
      print('   Extracting insights from $convName (${turns.length} turns)...');
      final extractionResult = await _httpGet(
        '$serverUrl/action/extractInsights?uuid=$convUuid',
      );

      if (extractionResult == null) {
        print('   ⚠️ Extraction failed for $filename');
        results.add({
          'file': filename,
          'convUuid': convUuid,
          'convName': convName,
          'error': 'Extraction failed',
        });
        continue;
      }

      final extractionData = jsonDecode(extractionResult) as Map<String, dynamic>;
      final insights = extractionData['insights'] as List<dynamic>? ?? [];

      print('   Extracted ${insights.length} insights');

      // Prepare turns for evaluation
      final turnMaps = turns.map((t) {
        final turn = t as Map<String, dynamic>;
        return {
          'prompt': turn['prompt'] ?? '',
          'response': turn['response'] ?? '',
        };
      }).toList();

      // Run evaluation via debug server
      final insightContents = insights.map((i) => (i as Map<String, dynamic>)['content'] as String).toList();

      // Use evaluator action directly
      final evalResult = await _httpGet(
        '$serverUrl/action/invoke?target=evaluator.evaluate'
        '&convUuid=$convUuid',
      );

      // Store result
      final result = {
        'file': filename,
        'convUuid': convUuid,
        'convName': convName,
        'turnCount': turns.length,
        'insightCount': insights.length,
        'insights': insights,
        'extractedAt': DateTime.now().toIso8601String(),
      };

      if (evalResult != null) {
        final evalData = jsonDecode(evalResult) as Map<String, dynamic>;
        result['evaluation'] = evalData;
      }

      results.add(result);

      print('   ✅ Done: ${insights.length} insights extracted\n');
    } catch (e) {
      print('   ❌ Error processing $filename: $e\n');
      results.add({
        'file': filename,
        'error': e.toString(),
      });
    }
  }

  // Compute aggregate metrics
  int totalInsights = 0;
  int totalConversations = results.where((r) => !r.containsKey('error')).length;

  for (final r in results) {
    if (!r.containsKey('error')) {
      totalInsights += (r['insightCount'] as int? ?? 0);
    }
  }

  // Save baseline results
  final baseline = {
    'generatedAt': DateTime.now().toIso8601String(),
    'summary': {
      'totalConversations': totalConversations,
      'totalInsights': totalInsights,
      'avgInsightsPerConversation':
          totalConversations > 0 ? (totalInsights / totalConversations).toStringAsFixed(1) : '0',
      'errors': results.where((r) => r.containsKey('error')).length,
    },
    'results': results,
  };

  final outputFile = File('$outputDir/baseline_results.json');
  await outputFile.writeAsString(JsonEncoder.withIndent('  ').convert(baseline));

  print('═' * 60);
  print('📊 Baseline Results Summary');
  print('═' * 60);
  print('Conversations processed: $totalConversations');
  print('Total insights extracted: $totalInsights');
  print('Avg insights/conversation: ${totalConversations > 0 ? (totalInsights / totalConversations).toStringAsFixed(1) : "N/A"}');
  print('Errors: ${results.where((r) => r.containsKey('error')).length}');
  print('\n✅ Saved to: $outputDir/baseline_results.json');
}

/// Simple HTTP GET using dart:io HttpClient
Future<String?> _httpGet(String url) async {
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    client.close();
    return body;
  } catch (e) {
    return null;
  }
}

String _parseArg(List<String> args, String key, String defaultValue) {
  for (final arg in args) {
    if (arg.startsWith('--$key=')) {
      return arg.substring('--$key='.length);
    }
  }
  return defaultValue;
}
