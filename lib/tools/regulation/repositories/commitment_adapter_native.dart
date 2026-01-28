/// Native platform Commitment adapter factory (ObjectBox)
library;

import 'package:get_it/get_it.dart';
import 'package:objectbox/objectbox.dart';

import '../../../core/persistence/persistence_adapter.dart';
import '../entities/commitment.dart';
import '../../../persistence/objectbox/commitment_objectbox_adapter.dart';

PersistenceAdapter<Commitment> createCommitmentAdapter() {
  final getIt = GetIt.instance;
  final store = getIt<Store>(instanceName: 'objectBoxStore');
  return CommitmentObjectBoxAdapter(store);
}
