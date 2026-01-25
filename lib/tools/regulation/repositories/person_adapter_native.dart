/// Native platform Person adapter factory (ObjectBox)
///
/// This file is only imported on native platforms. It creates the
/// ObjectBox-based adapter for PersonRepository.
library;

import 'package:get_it/get_it.dart';
import 'package:objectbox/objectbox.dart';

import '../../../core/persistence/persistence_adapter.dart';
import '../entities/person.dart';
import '../adapters/person_objectbox_adapter.dart';

/// Create the appropriate adapter for native platforms (ObjectBox)
PersistenceAdapter<Person> createPersonAdapter() {
  final getIt = GetIt.instance;
  final store = getIt<Store>(instanceName: 'objectBoxStore');
  return PersonObjectBoxAdapter(store);
}
