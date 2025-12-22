/// # ToolRepository
///
/// ## What it does
/// Repository for Tool entities. Manages MCP tools within namespaces.
///
/// ## Usage
/// ```dart
/// final adapter = ToolObjectBoxAdapter(store);
/// final repo = ToolRepository(adapter: adapter);
///
/// // Find tools in a namespace
/// final taskTools = await repo.findByNamespace('task');
///
/// // Find specific tool
/// final createTool = await repo.findByFullName('task.create');
/// ```

import '../core/entity_repository.dart';
import '../core/persistence/persistence_adapter.dart';
import '../services/embedding_service.dart';
import 'tool.dart';

class ToolRepository extends EntityRepository<Tool> {
  ToolRepository({
    required PersistenceAdapter<Tool> adapter,
    EmbeddingService? embeddingService,
  }) : super(
          adapter: adapter,
          embeddingService: embeddingService ?? EmbeddingService.instance,
        );

  // ============ Tool-specific queries ============

  /// Find all tools in a namespace
  Future<List<Tool>> findByNamespace(String namespaceId) async {
    final all = await findAll();
    return all
        .where((tool) => tool.namespaceId == namespaceId)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Find tool by full name (e.g., "task.create")
  /// Returns null if not found
  Future<Tool?> findByFullName(String fullName) async {
    final parts = fullName.split('.');
    if (parts.length != 2) return null;

    final namespaceId = parts[0];
    final toolName = parts[1];

    final all = await findAll();
    try {
      return all.firstWhere(
          (tool) => tool.namespaceId == namespaceId && tool.name == toolName);
    } catch (e) {
      return null;
    }
  }

  /// Find tool by name within a namespace
  Future<Tool?> findByName(String namespaceId, String toolName) async {
    final all = await findAll();
    try {
      return all.firstWhere(
          (tool) => tool.namespaceId == namespaceId && tool.name == toolName);
    } catch (e) {
      return null;
    }
  }

  /// Get all unique namespace IDs that have tools
  Future<List<String>> getNamespaceIds() async {
    final all = await findAll();
    final namespaceIds = all.map((tool) => tool.namespaceId).toSet().toList();
    return namespaceIds..sort();
  }
}
