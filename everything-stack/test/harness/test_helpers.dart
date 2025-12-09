/// # Test Harness
/// 
/// Shared test utilities for parameterized, data-driven testing.
/// Use these helpers to keep tests DRY and consistent.

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

/// Initialize Isar for testing.
/// Call in setUpAll.
Future<Isar> initTestIsar() async {
  await Isar.initializeIsarCore(download: true);
  return await Isar.open(
    [], // Add your schemas here
    directory: '',
    name: 'test_${DateTime.now().millisecondsSinceEpoch}',
  );
}

/// Close and delete test database.
/// Call in tearDownAll.
Future<void> cleanupTestIsar(Isar isar) async {
  await isar.close(deleteFromDisk: true);
}

/// Base class for parameterized test cases.
/// Extend for domain-specific test data.
abstract class TestCase {
  String get description;
}

/// Run parameterized test for each case.
/// 
/// Usage:
/// ```dart
/// parameterizedTest(
///   'should calculate distance',
///   [
///     DistanceTestCase(from: boston, to: nyc, expectedKm: 306),
///     DistanceTestCase(from: boston, to: la, expectedKm: 4169),
///   ],
///   (testCase) async {
///     final actual = calculateDistance(testCase.from, testCase.to);
///     expect(actual, closeTo(testCase.expectedKm, 10));
///   },
/// );
/// ```
void parameterizedTest<T extends TestCase>(
  String description,
  List<T> cases,
  Future<void> Function(T testCase) body,
) {
  group(description, () {
    for (final testCase in cases) {
      test(testCase.description, () => body(testCase));
    }
  });
}

/// Semantic similarity test case.
/// For testing Embeddable pattern.
class SimilarityTestCase extends TestCase {
  final String query;
  final String content;
  final bool shouldMatch;
  final double? minSimilarity;
  
  SimilarityTestCase({
    required this.query,
    required this.content,
    required this.shouldMatch,
    this.minSimilarity,
  });
  
  @override
  String get description => 
    shouldMatch 
      ? '"$query" should find "$content"'
      : '"$query" should not find "$content"';
}

/// Location proximity test case.
/// For testing Locatable pattern.
class ProximityTestCase extends TestCase {
  final double fromLat;
  final double fromLng;
  final double toLat;
  final double toLng;
  final double expectedDistanceKm;
  final double toleranceKm;
  
  ProximityTestCase({
    required this.fromLat,
    required this.fromLng,
    required this.toLat,
    required this.toLng,
    required this.expectedDistanceKm,
    this.toleranceKm = 1.0,
  });
  
  @override
  String get description => 
    '($fromLat,$fromLng) to ($toLat,$toLng) = ${expectedDistanceKm}km';
}

/// Time range test case.
/// For testing Temporal pattern.
class TimeRangeTestCase extends TestCase {
  final DateTime itemDue;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final bool shouldInclude;
  
  TimeRangeTestCase({
    required this.itemDue,
    required this.rangeStart,
    required this.rangeEnd,
    required this.shouldInclude,
  });
  
  @override
  String get description =>
    shouldInclude
      ? 'item due $itemDue should be in range'
      : 'item due $itemDue should not be in range';
}

/// Access control test case.
/// For testing Ownable pattern.
class AccessTestCase extends TestCase {
  final String ownerId;
  final List<String> sharedWith;
  final String visibility;
  final String queryingUserId;
  final bool shouldHaveAccess;
  
  AccessTestCase({
    required this.ownerId,
    required this.sharedWith,
    required this.visibility,
    required this.queryingUserId,
    required this.shouldHaveAccess,
  });
  
  @override
  String get description =>
    'user $queryingUserId ${shouldHaveAccess ? "can" : "cannot"} access';
}
