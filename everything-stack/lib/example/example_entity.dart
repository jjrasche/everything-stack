/// # ExampleItem
/// 
/// Example entity demonstrating all patterns. Delete this file
/// when starting a real project.
/// 
/// Shows how to:
/// - Extend BaseEntity
/// - Mix in patterns
/// - Override required methods
/// - Compose functionality

import 'package:isar/isar.dart';
import '../core/base_entity.dart';
import '../patterns/embeddable.dart';
import '../patterns/temporal.dart';
import '../patterns/ownable.dart';
import '../patterns/versionable.dart';
import '../patterns/locatable.dart';
import '../patterns/edgeable.dart';

part 'example_entity.g.dart'; // Isar generator

@Collection()
class ExampleItem extends BaseEntity
    with Embeddable, Temporal, Ownable, Versionable, Locatable, Edgeable {

  /// Item name
  String name;

  /// Item description
  String description;

  /// Item status
  @enumerated
  ExampleStatus status;

  /// Tags for categorization
  List<String> tags;

  // ============ Isar enum field overrides ============
  // These override mixin fields to add @enumerated annotation

  @override
  @enumerated
  SyncStatus syncStatus = SyncStatus.local;

  @override
  @enumerated
  Visibility visibility = Visibility.private;

  ExampleItem({
    required this.name,
    this.description = '',
    this.status = ExampleStatus.active,
    this.tags = const [],
  });
  
  // ============ Embeddable ============
  
  /// Define what text represents this item for semantic search.
  /// Include all fields that someone might search by.
  @override
  String toEmbeddingInput() {
    return [
      name,
      description,
      tags.join(' '),
    ].where((s) => s.isNotEmpty).join('\n');
  }
  
  // ============ Edgeable ============
  
  /// Already inherited from mixin, but shown for clarity
  @override
  String get edgeableType => 'ExampleItem';
}

enum ExampleStatus {
  active,
  archived,
  deleted,
}

/// Repository for ExampleItem
/// Shows how to extend EntityRepository with domain-specific queries.
class ExampleItemRepository {
  // In real implementation, extend EntityRepository<ExampleItem>
  // and implement domain-specific methods like:
  
  // Future<List<ExampleItem>> findActive() { ... }
  // Future<List<ExampleItem>> findByTag(String tag) { ... }
  // Future<List<ExampleItem>> findNearby(double lat, double lng) { ... }
}
