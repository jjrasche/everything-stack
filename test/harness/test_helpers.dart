import 'package:flutter_test/flutter_test.dart';
// import 'package:everything_stack_template/bootstrap/persistence_factory.dart'; // Deleted in Phase 1
import 'package:everything_stack_template/core/edge_repository.dart';
import 'package:everything_stack_template/core/version_repository.dart';
import 'package:everything_stack_template/services/embedding_service.dart';
import 'package:everything_stack_template/services/blob_store.dart';

// Conditional import for platform-specific test persistence
import 'test_persistence_stub.dart'
    if (dart.library.io) 'test_persistence_io.dart'
    if (dart.library.html) 'test_persistence_web.dart' as persistence;

/// Test context containing all initialized services and repositories.
/// Note: PersistenceFactory was removed in Phase 1 refactoring
class TestContext {
  final EdgeRepository edgeRepo;
  final VersionRepository versionRepo;
  final MockEmbeddingService embeddingService;
  final MockBlobStore blobStore;

  TestContext({
    required this.edgeRepo,
    required this.versionRepo,
    required this.embeddingService,
    required this.blobStore,
  });

  /// Close all resources
  Future<void> dispose() async {
    blobStore.dispose();
  }
}

/// Initialize test environment with platform-specific persistence.
///
/// Works on:
/// - Native platforms (ObjectBox)
/// - Web (IndexedDB)
///
/// Call in setUp:
/// ```dart
/// late TestContext ctx;
/// setUp(() async {
///   ctx = await initTestEnvironment();
/// });
/// tearDown(() async {
///   await cleanupTestEnvironment(ctx);
/// });
/// ```
Future<TestContext> initTestEnvironment() async {
  // NOTE: PersistenceFactory was deleted in Phase 1 refactoring
  // Test infrastructure needs to be updated to use platform-specific adapters directly
  // For now, this is a stub implementation

  // Initialize services
  final embeddingService = MockEmbeddingService();
  final blobStore = MockBlobStore();
  await blobStore.initialize();

  throw UnimplementedError(
    'Test environment initialization requires platform-specific adapter setup. '
    'Use MockNoteAdapter or other test doubles directly in tests.',
  );
}

/// Cleanup test environment.
/// Call in tearDown.
Future<void> cleanupTestEnvironment(TestContext ctx) async {
  await ctx.dispose();
  await persistence.cleanupTestPersistence();
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
  String get description => shouldMatch
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
  String get description => shouldInclude
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
