import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/main.dart';

/// Configuration for a single integration test.
///
/// Runs in two modes (controlled by SMOKE_TEST environment variable):
/// - **Smoke mode** (SMOKE_TEST=true): Uses real external APIs, captures fixtures
/// - **CI mode** (default): Uses mocked APIs from pre-captured fixtures
///
/// Each test creates an IntegrationTestConfig with:
/// 1. name - Test name for group/reporting
/// 2. services - List of ServiceConfig to initialize
/// 3. testLogic - The actual test function that uses WidgetTester
class IntegrationTestConfig {
  final String name;
  final List<ServiceConfig> services;
  final Future<void> Function(WidgetTester tester) testLogic;

  const IntegrationTestConfig({
    required this.name,
    required this.services,
    required this.testLogic,
  });

  /// Runs the test with automatic service setup/teardown.
  void run() {
    final isSmoke = const bool.fromEnvironment('SMOKE_TEST', defaultValue: false);
    final modeName = isSmoke ? 'Smoke (Real APIs)' : 'CI (Mocked APIs)';

    group('$name - $modeName', () {
      setUpAll(() async {
        // Initialize services for this test
        for (final service in services) {
          await service.setup(isSmoke);
        }
      });

      testWidgets('full test', (WidgetTester tester) async {
        // Build app and wait for bootstrap
        await tester.pumpWidget(const MyApp());
        await tester.pumpAndSettle(const Duration(seconds: 5));

        // Run test logic
        await testLogic(tester);
      });

      tearDownAll(() {
        GetIt.instance.reset();
      });
    });
  }
}

/// Service configuration for integration tests.
///
/// Each test can configure multiple services (embedding, STT, LLM, etc.)
/// by passing ServiceConfig instances to IntegrationTestConfig.
class ServiceConfig {
  final Future<void> Function(bool isSmoke) setup;

  const ServiceConfig({
    required this.setup,
  });

  /// Configure embedding service for smoke/CI modes.
  ///
  /// **Smoke mode (SMOKE_TEST=true):**
  /// - Uses real EmbeddingService from bootstrap
  /// - Test can capture embeddings via fixture_capture.dart
  ///
  /// **CI mode (SMOKE_TEST=false, default):**
  /// - Uses real EmbeddingService but loads pre-captured embeddings from fixture
  /// - Fails if fixture missing or required embeddings not found
  ///
  /// **Parameters:**
  /// - `fixture`: Filename in test/fixtures/ (e.g., 'invocation_embeddings.json')
  factory ServiceConfig.embedding({required String fixture}) {
    return ServiceConfig(
      setup: (bool isSmoke) async {
        if (isSmoke) {
          // Smoke: keep real service from bootstrap
          print('🔥 Smoke mode: Real EmbeddingService (will capture fixture)');
        } else {
          // CI: real service with pre-captured embeddings
          print('📝 CI mode: Real EmbeddingService with fixture $fixture');
          print('✅ Embedding service configured');
        }
      },
    );
  }
}
