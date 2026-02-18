import 'package:objectbox/objectbox.dart';
import 'package:everything_stack_template/domain/atomic_insight.dart';
import 'package:everything_stack_template/core/base_entity.dart';

@Entity()
class AtomicInsightOB {
  @Id()
  int id = 0;

  @Unique()
  String uuid = '';

  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  String? syncId;

  // ============ AtomicInsight-specific fields ============

  /// Freeform text content: "[Atomic idea]. Because [reason]."
  @Index()
  late String content;

  /// Scope where this insight lives: 'session', 'day', 'week', 'project', 'life'
  @Index()
  late String scope;

  /// Optional type tag: 'learning', 'project', 'exploration'
  String? type;

  /// Quoted substring from episodic source supporting this insight
  String? evidenceSpan;

  /// Optional project UUID (if scope='project' or insight is within a project)
  @Index()
  String? projectId;

  /// Whether this insight is archived (removed from active context)
  bool isArchived = false;

  /// When this insight was archived (null if not archived)
  @Property(type: PropertyType.date)
  DateTime? archivedAt;

  /// Embedding vector for semantic search
  /// Stored as Float64List for efficient storage.
  /// Nullable for backwards compatibility with existing data.
  @Property(type: PropertyType.floatVector)
  List<double>? embedding;

  /// Sync status stored as int (enum index)
  int syncStatus = 0;

  AtomicInsightOB();

  // ============ Conversion Methods ============

  /// Convert from domain AtomicInsight to ObjectBox wrapper
  factory AtomicInsightOB.fromAtomicInsight(AtomicInsight insight) {
    return AtomicInsightOB()
      ..id = insight.id
      ..uuid = insight.uuid
      ..createdAt = insight.createdAt
      ..updatedAt = insight.updatedAt
      ..syncId = insight.syncId
      ..content = insight.content
      ..scope = insight.scope
      ..type = insight.type
      ..evidenceSpan = insight.evidenceSpan
      ..projectId = insight.projectId
      ..isArchived = insight.isArchived
      ..archivedAt = insight.archivedAt
      ..embedding = insight.embedding
      ..syncStatus = insight.syncStatus.index;
  }

  /// Convert from ObjectBox wrapper back to domain AtomicInsight
  AtomicInsight toAtomicInsight() {
    final insight = AtomicInsight(
      content: content,
      scope: scope,
      type: type,
      evidenceSpan: evidenceSpan,
      projectId: projectId,
      isArchived: isArchived,
    )
      ..id = id
      ..uuid = uuid
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..syncId = syncId
      ..archivedAt = archivedAt
      ..embedding = embedding
      ..syncStatus = SyncStatus.values[syncStatus];

    return insight;
  }

  /// Validate insight data before storage.
  void validate() {
    if (uuid.isEmpty) throw ArgumentError('uuid cannot be empty');
    if (content.isEmpty) throw ArgumentError('content cannot be empty');
    if (scope.isEmpty) throw ArgumentError('scope cannot be empty');
    if (!['session', 'day', 'week', 'project', 'life'].contains(scope)) {
      throw ArgumentError(
          'scope must be one of: session, day, week, project, life');
    }
    if (type != null &&
        !['learning', 'project', 'exploration'].contains(type)) {
      throw ArgumentError(
          'type must be one of: learning, project, exploration (or null)');
    }
  }

  @override
  String toString() =>
      'AtomicInsightOB($uuid, scope: $scope, archived: $isArchived, content: ${content.substring(0, content.length > 50 ? 50 : content.length)}...)';
}
