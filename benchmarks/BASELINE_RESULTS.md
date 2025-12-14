# Performance Baseline Results

**Date**: 2025-12-12
**Method**: Instrumented existing integration tests with `Stopwatch`
**Tests**: 5 key operations from passing test suite

---

## Native Platform (ObjectBox)

**Platform**: Windows Desktop
**Database**: ObjectBox with native HNSW
**Test Command**: `flutter test test/integration/notes_demo_test.dart test/integration/hnsw_integration_test.dart`

| Operation | Dataset | Time (ms) | Test Location |
|-----------|---------|-----------|---------------|
| Semantic search | 3 notes | **12ms** | notes_demo_test.dart:73 |
| Semantic search | 1 note | **8ms** | hnsw_integration_test.dart:75 |
| Get version history | 4 versions | **1ms** | notes_demo_test.dart:107 |
| Reconstruct from deltas | ~2 deltas | **29ms** | notes_demo_test.dart:107 |
| Graph traversal | 2-hop (3 nodes) | **2ms** | notes_demo_test.dart:182 |
| Bulk insert | 3 notes | **13ms** | hnsw_integration_test.dart:92 |

**Summary**:
- All operations < 30ms
- Semantic search: ~10ms average
- Graph operations: 1-2ms (very fast)
- Version operations: 1-29ms (delta reconstruction slower)

---

## Web Platform (IndexedDB)

**Status**: ⚠️  Web tests blocked by compilation issue

**Problem**: Integration tests import ObjectBox code which fails to compile for web target.
- `objectbox.g.dart` contains `dart:ffi` which isn't supported on web
- The conditional imports work at runtime but fail at compile time for web
- `IndexedDB` smoke tests exist but need timing instrumentation

**Next Steps**:
1. Add timing to `test/indexeddb_smoke_test.dart`
2. Run on Chrome to get web baseline
3. Compare native vs web performance

---

## Approach

**What worked**: Instrumenting existing tests instead of writing new ones
- No API mismatches (tests already passing)
- Minimal code changes (5 `Stopwatch` additions)
- Real-world operations (not synthetic benchmarks)

**What we learned**:
- Native performance is excellent across the board
- ObjectBox HNSW search is very fast (~10ms)
- Graph traversal benefits from indexed queries
- Version reconstruction has delta overhead (expected)

---

## Next: Web Baseline

To complete the comparison, we need web results. Options:

1. **Instrument IndexedDB smoke test** (quickest)
   - Add timing to existing `test/indexeddb_smoke_test.dart`
   - Run with `flutter test --platform chrome`
   - Get web performance numbers

2. **Fix web compilation** (proper solution)
   - Ensure integration tests compile for web
   - May require conditional imports for test files
   - More work but enables full test suite on web

**Recommendation**: Option 1 - instrument smoke test, get numbers today
