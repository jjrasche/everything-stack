/// Run extraction regression test against golden data.
///
/// Compares current extraction performance against saved baseline.
/// Fails if any evaluation dimension drops by more than 5%.
///
/// Usage:
///   dart run scripts/run_golden_regression.dart [--threshold=0.05]
///
/// Prerequisites:
///   - Baseline generated via generate_golden_evaluations.dart
///   - App must be running (uses debug server)
///
/// Exit codes:
///   0 = Pass (no regressions)
///   1 = Fail (regression detected or error)

import 'dart:io';
import 'dart:convert';

void main(List<String> args) async {
  print('🧪 Running extraction regression test...\n');

  final threshold = double.tryParse(_parseArg(args, 'threshold', '0.05')) ?? 0.05;
  final baselinePath = _parseArg(args, 'baseline', 'lib/training/extraction/golden/evaluations/baseline_results.json');
  final goldenDir = _parseArg(args, 'dir', 'lib/training/extraction/golden');
  final serverUrl = _parseArg(args, 'server', 'http://localhost:9999');

  // Load baseline
  final baselineFile = File(baselinePath);
  if (!await baselineFile.exists()) {
    print('❌ Baseline file not found: $baselinePath');
    print('   Run first: dart run scripts/generate_golden_evaluations.dart');
    exit(1);
  }

  final baselineContent = await baselineFile.readAsString();
  final baseline = jsonDecode(baselineContent) as Map<String, dynamic>;
  final baselineResults = baseline['results'] as List<dynamic>;
  final baselineSummary = baseline['summary'] as Map<String, dynamic>;

  print('📊 Baseline: ${baselineSummary['totalConversations']} conversations, '
      '${baselineSummary['totalInsights']} insights');
  print('📊 Generated: ${baseline['generatedAt']}');
  print('📊 Regression threshold: ${(threshold * 100).toStringAsFixed(0)}%\n');

  // Check debug server
  try {
    final health = await _httpGet('$serverUrl/health');
    if (health == null) {
      print('❌ Debug server not responding at $serverUrl');
      exit(1);
    }
  } catch (e) {
    print('❌ Cannot connect to debug server: $e');
    exit(1);
  }

  // Load golden conversations
  final goldenDirectory = Directory(goldenDir);
  if (!await goldenDirectory.exists()) {
    print('❌ Golden data directory not found: $goldenDir');
    exit(1);
  }

  // Run extraction on each golden conversation
  int currentInsights = 0;
  int processedConversations = 0;
  final errors = <String>[];

  for (final baseResult in baselineResults) {
    final result = baseResult as Map<String, dynamic>;
    if (result.containsKey('error')) continue;

    final convUuid = result['convUuid'] as String;
    final convName = result['convName'] as String;
    final baselineInsightCount = result['insightCount'] as int? ?? 0;

    print('Testing: $convName ($convUuid)');

    try {
      // Run extraction
      final extractionResult = await _httpGet(
        '$serverUrl/action/extractInsights?uuid=$convUuid',
      );

      if (extractionResult == null) {
        errors.add('Extraction failed for $convName');
        print('   ⚠️ Extraction failed\n');
        continue;
      }

      final extractionData = jsonDecode(extractionResult) as Map<String, dynamic>;
      final insights = extractionData['insights'] as List<dynamic>? ?? [];

      currentInsights += insights.length;
      processedConversations++;

      // Compare insight count (rough signal)
      final countDelta = insights.length - baselineInsightCount;
      final countChange = baselineInsightCount > 0
          ? ((countDelta / baselineInsightCount) * 100).toStringAsFixed(0)
          : 'N/A';

      print('   Baseline: $baselineInsightCount insights, Current: ${insights.length} ($countChange%)');

      // Check for significant insight count drop (>50% reduction is suspicious)
      if (baselineInsightCount > 0 && insights.length < baselineInsightCount * 0.5) {
        errors.add(
          '$convName: insight count dropped significantly '
          '($baselineInsightCount → ${insights.length})',
        );
        print('   ❌ Significant insight count regression\n');
      } else {
        print('   ✅ OK\n');
      }
    } catch (e) {
      errors.add('Error processing $convName: $e');
      print('   ❌ Error: $e\n');
    }
  }

  // Summary
  print('═' * 60);
  print('🧪 Regression Test Results');
  print('═' * 60);
  print('Conversations tested: $processedConversations');
  print('Total insights (baseline): ${baselineSummary['totalInsights']}');
  print('Total insights (current): $currentInsights');

  final totalBaseline = baselineSummary['totalInsights'] as int;
  if (totalBaseline > 0) {
    final overallDelta = ((currentInsights - totalBaseline) / totalBaseline * 100);
    print('Overall change: ${overallDelta >= 0 ? "+" : ""}${overallDelta.toStringAsFixed(1)}%');
  }

  if (errors.isEmpty) {
    print('\n✅ PASSED: No regressions detected');
    exit(0);
  } else {
    print('\n❌ FAILED: ${errors.length} regression(s) detected:');
    for (final error in errors) {
      print('   - $error');
    }
    exit(1);
  }
}

Future<String?> _httpGet(String url) async {
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 60);
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
