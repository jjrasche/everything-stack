/// Integration test driver for CI/CD.
///
/// Required for `flutter drive` command to run integration tests on devices.
/// See: https://docs.flutter.dev/testing/integration-tests
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
