/// Stub implementation - never used directly
library;

import 'package:uuid/uuid.dart';
import '../../services/sync_service.dart' show SyncStatus;

export '../../services/sync_service.dart' show SyncStatus;

const _uuidGenerator = Uuid();

abstract class BaseEntity {
  int id = 0;
  String uuid = _uuidGenerator.v4();
  DateTime createdAt = DateTime.now();
  DateTime updatedAt = DateTime.now();
  void touch() => updatedAt = DateTime.now();
  String? syncId;
  SyncStatus syncStatus = SyncStatus.local;
}
