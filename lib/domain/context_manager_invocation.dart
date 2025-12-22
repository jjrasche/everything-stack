/// # ContextManagerInvocation
///
/// ## What it does
/// Logs context manager decisions for training and debugging.
/// Records which tools were considered, filtered, passed to LLM, and called.
///
/// ## Key insight
/// Invocable mixin tracks outcomes on result entities.
/// ContextManagerInvocation tracks the DECISION PROCESS:
/// - What tools were available?
/// - What got filtered out (and why)?
/// - What scores did each tool get?
/// - What did the LLM actually call?
///
/// ## Training feedback loop
/// After user feedback, query this invocation to understand:
/// - Was the right tool even in the candidate set?
/// - Was it filtered out too aggressively?
/// - Did semantic scoring rank it correctly?
/// - Did the LLM pick the right one from the final set?
///
/// ## Usage
/// ```dart
/// // Log a context manager decision
/// final invocation = ContextManagerInvocation(
///   correlationId: event.correlationId,
///   eventPayloadJson: jsonEncode(event.payload),
/// );
/// invocation.toolsAvailable = ['task.create', 'task.complete', 'task.list'];
/// invocation.toolsFiltered = ['task.list']; // low semantic score
/// invocation.toolsPassedToLLM = ['task.create', 'task.complete'];
/// invocation.semanticScores = {'task.create': 0.87, 'task.complete': 0.72};
/// invocation.toolsCalled = ['task.create'];
/// invocation.confidence = 0.87;
/// await invocationRepo.save(invocation);
/// ```

import 'dart:convert';

import 'package:objectbox/objectbox.dart';

import '../core/base_entity.dart';

@Entity()
class ContextManagerInvocation extends BaseEntity {
  // ============ BaseEntity field overrides ============
  @override
  @Id()
  int id = 0;

  @override
  @Unique()
  String uuid = '';

  @override
  @Property(type: PropertyType.date)
  DateTime createdAt = DateTime.now();

  @override
  @Property(type: PropertyType.date)
  DateTime updatedAt = DateTime.now();

  @override
  String? syncId;

  // ============ Component identity ============

  /// Always 'context_manager'
  final String componentType = 'context_manager';

  /// Context: 'conversation', 'retry', 'background', 'test'
  String contextType = 'conversation';

  // ============ Input ============

  /// Serialized event payload that triggered this invocation
  String eventPayloadJson = '{}';

  /// Embedding of the user utterance (for training analysis)
  @Transient()
  List<double> eventEmbedding = [];

  /// JSON storage for eventEmbedding
  String eventEmbeddingJson = '[]';

  /// Links to the Event chain
  String correlationId;

  /// Which personality was active during this invocation
  String? personalityId;

  // ============ Namespace Selection (hop 1) ============

  /// Which namespaces were considered
  @Transient()
  List<String> namespacesConsidered = [];
  String namespacesConsideredJson = '[]';

  /// Which namespace was selected by LLM
  String? selectedNamespace;

  /// Semantic scores for each namespace
  @Transient()
  Map<String, double> namespaceScores = {};
  String namespaceScoresJson = '{}';

  // ============ Tool Filtering (hop 2) ============

  /// All tools available in the selected namespace
  @Transient()
  List<String> toolsAvailable = [];
  String toolsAvailableJson = '[]';

  /// Tools filtered out (didn't pass threshold)
  @Transient()
  List<String> toolsFiltered = [];
  String toolsFilteredJson = '[]';

  /// Tools that made it to LLM
  @Transient()
  List<String> toolsPassedToLLM = [];
  String toolsPassedToLLMJson = '[]';

  /// Semantic/statistical scores per tool
  @Transient()
  Map<String, double> toolScores = {};
  String toolScoresJson = '{}';

  // ============ LLM Decision ============

  /// Which tools did the LLM actually call
  @Transient()
  List<String> toolsCalled = [];
  String toolsCalledJson = '[]';

  // ============ Context Assembly ============

  /// How many items of each type were included in context
  @Transient()
  Map<String, int> contextItemCounts = {};
  String contextItemCountsJson = '{}';

  /// IDs of context items (for replay)
  @Transient()
  List<String> contextItemIds = [];
  String contextItemIdsJson = '[]';

  // ============ Outcome ============

  /// Overall confidence in the decision (0.0-1.0)
  double confidence = 0.0;

  /// When this invocation occurred
  @Property(type: PropertyType.date)
  DateTime timestamp = DateTime.now();

  /// How long did this decision take (ms)
  int latencyMs = 0;

  /// Did this result in an error?
  String? errorType;
  String? errorMessage;

  // ============ Constructor ============

  ContextManagerInvocation({
    required this.correlationId,
    this.eventPayloadJson = '{}',
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  // ============ Lifecycle ============

  /// Prepare for save - serialize all transient fields
  void prepareForSave() {
    eventEmbeddingJson = jsonEncode(eventEmbedding);
    namespacesConsideredJson = jsonEncode(namespacesConsidered);
    namespaceScoresJson = jsonEncode(namespaceScores);
    toolsAvailableJson = jsonEncode(toolsAvailable);
    toolsFilteredJson = jsonEncode(toolsFiltered);
    toolsPassedToLLMJson = jsonEncode(toolsPassedToLLM);
    toolScoresJson = jsonEncode(toolScores);
    toolsCalledJson = jsonEncode(toolsCalled);
    contextItemCountsJson = jsonEncode(contextItemCounts);
    contextItemIdsJson = jsonEncode(contextItemIds);
    touch();
  }

  /// Load after read - deserialize all transient fields
  void loadAfterRead() {
    eventEmbedding = (jsonDecode(eventEmbeddingJson) as List<dynamic>)
        .map((e) => (e as num).toDouble())
        .toList();
    namespacesConsidered =
        (jsonDecode(namespacesConsideredJson) as List<dynamic>)
            .map((e) => e as String)
            .toList();
    namespaceScores = (jsonDecode(namespaceScoresJson) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, (v as num).toDouble()));
    toolsAvailable = (jsonDecode(toolsAvailableJson) as List<dynamic>)
        .map((e) => e as String)
        .toList();
    toolsFiltered = (jsonDecode(toolsFilteredJson) as List<dynamic>)
        .map((e) => e as String)
        .toList();
    toolsPassedToLLM = (jsonDecode(toolsPassedToLLMJson) as List<dynamic>)
        .map((e) => e as String)
        .toList();
    toolScores = (jsonDecode(toolScoresJson) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, (v as num).toDouble()));
    toolsCalled = (jsonDecode(toolsCalledJson) as List<dynamic>)
        .map((e) => e as String)
        .toList();
    contextItemCounts =
        (jsonDecode(contextItemCountsJson) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as int));
    contextItemIds = (jsonDecode(contextItemIdsJson) as List<dynamic>)
        .map((e) => e as String)
        .toList();
  }

  // ============ Analysis helpers ============

  /// Was the given tool filtered out?
  bool wasFiltered(String toolName) => toolsFiltered.contains(toolName);

  /// Was the given tool passed to LLM?
  bool wasPassedToLLM(String toolName) => toolsPassedToLLM.contains(toolName);

  /// Was the given tool actually called?
  bool wasCalled(String toolName) => toolsCalled.contains(toolName);

  /// How many tools were filtered out?
  int get filterCount => toolsFiltered.length;

  /// What percentage of tools passed to LLM?
  double get passRate {
    if (toolsAvailable.isEmpty) return 0.0;
    return toolsPassedToLLM.length / toolsAvailable.length;
  }

  // ============ Serialization ============

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'syncId': syncId,
      'componentType': componentType,
      'contextType': contextType,
      'eventPayloadJson': eventPayloadJson,
      'eventEmbedding': eventEmbedding,
      'correlationId': correlationId,
      'personalityId': personalityId,
      'namespacesConsidered': namespacesConsidered,
      'selectedNamespace': selectedNamespace,
      'namespaceScores': namespaceScores,
      'toolsAvailable': toolsAvailable,
      'toolsFiltered': toolsFiltered,
      'toolsPassedToLLM': toolsPassedToLLM,
      'toolScores': toolScores,
      'toolsCalled': toolsCalled,
      'contextItemCounts': contextItemCounts,
      'contextItemIds': contextItemIds,
      'confidence': confidence,
      'timestamp': timestamp.toIso8601String(),
      'latencyMs': latencyMs,
      'errorType': errorType,
      'errorMessage': errorMessage,
    };
  }

  factory ContextManagerInvocation.fromJson(Map<String, dynamic> json) {
    final invocation = ContextManagerInvocation(
      correlationId: json['correlationId'] as String,
      eventPayloadJson: json['eventPayloadJson'] as String? ?? '{}',
    );

    invocation.id = json['id'] as int? ?? 0;
    invocation.uuid = json['uuid'] as String? ?? '';
    invocation.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    invocation.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    invocation.syncId = json['syncId'] as String?;
    invocation.contextType = json['contextType'] as String? ?? 'conversation';
    invocation.personalityId = json['personalityId'] as String?;

    if (json['eventEmbedding'] != null) {
      invocation.eventEmbedding = (json['eventEmbedding'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList();
    }

    if (json['namespacesConsidered'] != null) {
      invocation.namespacesConsidered =
          (json['namespacesConsidered'] as List<dynamic>)
              .map((e) => e as String)
              .toList();
    }

    invocation.selectedNamespace = json['selectedNamespace'] as String?;

    if (json['namespaceScores'] != null) {
      invocation.namespaceScores =
          (json['namespaceScores'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as num).toDouble()));
    }

    if (json['toolsAvailable'] != null) {
      invocation.toolsAvailable = (json['toolsAvailable'] as List<dynamic>)
          .map((e) => e as String)
          .toList();
    }

    if (json['toolsFiltered'] != null) {
      invocation.toolsFiltered = (json['toolsFiltered'] as List<dynamic>)
          .map((e) => e as String)
          .toList();
    }

    if (json['toolsPassedToLLM'] != null) {
      invocation.toolsPassedToLLM =
          (json['toolsPassedToLLM'] as List<dynamic>)
              .map((e) => e as String)
              .toList();
    }

    if (json['toolScores'] != null) {
      invocation.toolScores = (json['toolScores'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble()));
    }

    if (json['toolsCalled'] != null) {
      invocation.toolsCalled = (json['toolsCalled'] as List<dynamic>)
          .map((e) => e as String)
          .toList();
    }

    if (json['contextItemCounts'] != null) {
      invocation.contextItemCounts =
          (json['contextItemCounts'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, v as int));
    }

    if (json['contextItemIds'] != null) {
      invocation.contextItemIds = (json['contextItemIds'] as List<dynamic>)
          .map((e) => e as String)
          .toList();
    }

    invocation.confidence = (json['confidence'] as num?)?.toDouble() ?? 0.0;
    invocation.timestamp = json['timestamp'] != null
        ? DateTime.parse(json['timestamp'] as String)
        : DateTime.now();
    invocation.latencyMs = json['latencyMs'] as int? ?? 0;
    invocation.errorType = json['errorType'] as String?;
    invocation.errorMessage = json['errorMessage'] as String?;

    return invocation;
  }
}
