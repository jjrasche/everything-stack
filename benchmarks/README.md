# Performance Benchmarks

## Overview

This directory contains baseline performance results for Everything Stack persistence layer across platforms.

## Running Benchmarks

### Both Platforms (Required)

```bash
# Native platform (ObjectBox)
flutter test test/performance/persistence_benchmarks.dart

# Web platform (IndexedDB)
flutter test --platform chrome test/performance/persistence_benchmarks.dart
```

### Establishing Baselines

First run after infrastructure changes:

```bash
# Generate native baseline
flutter test test/performance/persistence_benchmarks.dart > benchmarks/native_baseline.txt 2>&1

# Generate web baseline
flutter test --platform chrome test/performance/persistence_benchmarks.dart > benchmarks/web_baseline.txt 2>&1
```

JSON results are in the test output - extract and commit to `baseline_results.json`.

### Enforcing Thresholds

To fail tests on performance regression:

```bash
flutter test --dart-define=ENFORCE_THRESHOLDS=true test/performance/persistence_benchmarks.dart
```

## Pass Criteria

### Web (IndexedDB)
- Semantic search p95 < 200ms (1000 notes)
- Insert rate > 50 notes/sec
- 3-hop graph traversal < 100ms

### Native (ObjectBox)
- Semantic search p95 < 50ms (1000 notes)
- Insert rate > 50 notes/sec
- 3-hop graph traversal < 100ms

## CI Integration

### Current State
- Benchmarks run on both platforms
- Results are measured and reported
- Tests pass/fail based on ENFORCE_THRESHOLDS environment variable

### Future Enhancements
1. **Baseline Comparison**: Compare against committed baseline, fail if regression > 20%
2. **Trend Tracking**: Store results over time, visualize performance trends
3. **Automated Reporting**: Post benchmark results as PR comments

## Interpreting Results

### Good Performance
- Native should be ~4x faster than web for semantic search
- Both platforms should meet minimum thresholds
- Variance (p95 vs p50) should be low (< 2x)

### Red Flags
- p95 > 2x p50: High variance, investigate outliers
- Native slower than web: Something very wrong with ObjectBox
- Insert rate < 50/sec: Persistence layer bottleneck

## Test Data Strategy

Benchmarks use **MockEmbeddingService** with deterministic embeddings:
- Fast: No API calls
- Repeatable: Same input = same output
- Adequate: HNSW performance depends on vector math, not semantic quality

For functional testing of semantic search quality, see `test/integration/hnsw_integration_test.dart`.

## Maintenance

### When to Re-baseline
- After intentional performance optimizations
- After major architecture changes (e.g., new persistence adapter)
- After upgrading Flutter/ObjectBox/IndexedDB libraries

### When to Adjust Thresholds
- If baselines improve consistently, tighten thresholds
- If new platform requirements emerge (e.g., embedded targets)
- If user requirements change (e.g., need to support 10k notes)

## Baseline Files

- `native_baseline.txt` - Full test output from native run
- `web_baseline.txt` - Full test output from web run
- `baseline_results.json` - Structured results for programmatic comparison (future)
