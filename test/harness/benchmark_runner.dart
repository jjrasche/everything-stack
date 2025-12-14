/// # Benchmark Runner
///
/// ## What it does
/// Reusable performance measurement infrastructure for Everything Stack.
/// Measures timing, calculates statistics, outputs structured results.
///
/// ## Usage
/// ```dart
/// final runner = BenchmarkRunner();
/// final result = await runner.measure(
///   'semantic_search',
///   () async => await repo.searchSimilar('query'),
///   iterations: 10,
/// );
/// print('p95: ${result.p95.inMilliseconds}ms');
/// expect(result.p95, lessThan(Duration(milliseconds: 200)));
/// ```
///
/// ## Output
/// Results can be serialized to JSON for baseline tracking in CI:
/// ```dart
/// final json = result.toJson();
/// File('benchmarks/baseline.json').writeAsStringSync(jsonEncode(json));
/// ```

import 'dart:async';
import 'dart:math' show max, min;

/// Result of a benchmark measurement
class BenchmarkResult {
  /// Name of the benchmark
  final String name;

  /// All measured durations
  final List<Duration> durations;

  /// Platform info (native or web)
  final String platform;

  /// Timestamp when benchmark was run
  final DateTime timestamp;

  BenchmarkResult({
    required this.name,
    required this.durations,
    required this.platform,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Minimum duration
  Duration get min => durations.reduce((a, b) => a < b ? a : b);

  /// Maximum duration
  Duration get max => durations.reduce((a, b) => a > b ? a : b);

  /// Average (mean) duration
  Duration get avg {
    final total = durations.fold<int>(0, (sum, d) => sum + d.inMicroseconds);
    return Duration(microseconds: total ~/ durations.length);
  }

  /// Median (p50) duration
  Duration get p50 => _percentile(0.50);

  /// 95th percentile duration
  Duration get p95 => _percentile(0.95);

  /// 99th percentile duration
  Duration get p99 => _percentile(0.99);

  /// Calculate percentile from sorted durations
  Duration _percentile(double percentile) {
    if (durations.isEmpty) {
      return Duration.zero;
    }

    final sorted = List<Duration>.from(durations)
      ..sort((a, b) => a.compareTo(b));
    final index = (sorted.length * percentile).ceil() - 1;
    return sorted[max(0, min(index, sorted.length - 1))];
  }

  /// Convert to JSON for storage/reporting
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'platform': platform,
      'timestamp': timestamp.toIso8601String(),
      'iterations': durations.length,
      'min_ms': min.inMilliseconds,
      'max_ms': max.inMilliseconds,
      'avg_ms': avg.inMilliseconds,
      'p50_ms': p50.inMilliseconds,
      'p95_ms': p95.inMilliseconds,
      'p99_ms': p99.inMilliseconds,
      'all_durations_us': durations.map((d) => d.inMicroseconds).toList(),
    };
  }

  /// Pretty print for human reading
  @override
  String toString() {
    return '''
Benchmark: $name
Platform: $platform
Iterations: ${durations.length}
Min: ${min.inMilliseconds}ms
Max: ${max.inMilliseconds}ms
Avg: ${avg.inMilliseconds}ms
p50: ${p50.inMilliseconds}ms
p95: ${p95.inMilliseconds}ms
p99: ${p99.inMilliseconds}ms
''';
  }
}

/// Benchmark runner for performance testing
class BenchmarkRunner {
  /// Platform identifier (auto-detected or overridden for testing)
  final String platform;

  BenchmarkRunner({String? platform})
      : platform = platform ?? _detectPlatform();

  /// Detect current platform
  static String _detectPlatform() {
    // In tests, this will be 'vm' for flutter test or 'chrome' for flutter test --platform chrome
    // For real detection, could check kIsWeb from flutter foundation
    return 'vm'; // Default for test environment
  }

  /// Measure timing of an async operation
  ///
  /// Runs the operation multiple times and collects timing data.
  /// Returns BenchmarkResult with statistical analysis.
  ///
  /// [name] - Benchmark identifier
  /// [operation] - Async function to measure
  /// [iterations] - Number of times to run (default 10)
  /// [warmup] - Number of warmup runs before measurement (default 2)
  Future<BenchmarkResult> measure(
    String name,
    Future<void> Function() operation, {
    int iterations = 10,
    int warmup = 2,
  }) async {
    // Warmup phase - let JIT optimize, caches warm up
    for (int i = 0; i < warmup; i++) {
      await operation();
    }

    // Measurement phase
    final durations = <Duration>[];
    for (int i = 0; i < iterations; i++) {
      final stopwatch = Stopwatch()..start();
      await operation();
      stopwatch.stop();
      durations.add(stopwatch.elapsed);
    }

    return BenchmarkResult(
      name: name,
      durations: durations,
      platform: platform,
    );
  }

  /// Measure timing of a synchronous operation
  ///
  /// Same as measure() but for sync functions.
  BenchmarkResult measureSync(
    String name,
    void Function() operation, {
    int iterations = 10,
    int warmup = 2,
  }) {
    // Warmup
    for (int i = 0; i < warmup; i++) {
      operation();
    }

    // Measurement
    final durations = <Duration>[];
    for (int i = 0; i < iterations; i++) {
      final stopwatch = Stopwatch()..start();
      operation();
      stopwatch.stop();
      durations.add(stopwatch.elapsed);
    }

    return BenchmarkResult(
      name: name,
      durations: durations,
      platform: platform,
    );
  }
}

/// Collection of benchmark results
class BenchmarkSuite {
  final String name;
  final List<BenchmarkResult> results;
  final DateTime timestamp;

  BenchmarkSuite({
    required this.name,
    required this.results,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Convert entire suite to JSON
  Map<String, dynamic> toJson() {
    return {
      'suite': name,
      'timestamp': timestamp.toIso8601String(),
      'benchmarks': results.map((r) => r.toJson()).toList(),
    };
  }

  /// Pretty print summary
  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('Benchmark Suite: $name');
    buffer.writeln('Timestamp: $timestamp');
    buffer.writeln('');
    for (final result in results) {
      buffer.writeln(result);
    }
    return buffer.toString();
  }
}
