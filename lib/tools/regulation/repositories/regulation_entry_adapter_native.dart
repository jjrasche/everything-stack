/// Native platform RegulationEntry adapter factory (ObjectBox)
library;

import 'package:get_it/get_it.dart';
import 'package:objectbox/objectbox.dart';

import '../../../core/persistence/persistence_adapter.dart';
import '../entities/regulation_entry.dart';
import '../adapters/regulation_entry_objectbox_adapter.dart';

PersistenceAdapter<RegulationEntry> createRegulationEntryAdapter() {
  final getIt = GetIt.instance;
  final store = getIt<Store>(instanceName: 'objectBoxStore');
  return RegulationEntryObjectBoxAdapter(store);
}
