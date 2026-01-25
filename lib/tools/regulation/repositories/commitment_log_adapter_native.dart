/// Native platform CommitmentLog adapter factory (ObjectBox)
library;

import 'package:get_it/get_it.dart';
import 'package:objectbox/objectbox.dart';

import '../../../core/persistence/persistence_adapter.dart';
import '../entities/commitment_log.dart';
import '../adapters/commitment_log_objectbox_adapter.dart';

PersistenceAdapter<CommitmentLog> createCommitmentLogAdapter() {
  final getIt = GetIt.instance;
  final store = getIt<Store>(instanceName: 'objectBoxStore');
  return CommitmentLogObjectBoxAdapter(store);
}
