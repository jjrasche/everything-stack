import 'package:get_it/get_it.dart';
import '../bootstrap.dart';

abstract class BootstrapModule {
  Future<void> register(GetIt getIt, EverythingStackConfig config);
  Future<void> dispose(GetIt getIt) async {}
}
