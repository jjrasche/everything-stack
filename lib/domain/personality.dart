/// # Personality
///
/// ## What it does
/// Represents a trainable agent persona with its own attention patterns.
/// When you switch personalities, you switch the entire perceptual apparatus.
///
/// ## BREAKTHROUGH INSIGHT: Personality = Trainable Agent
/// A Personality owns its AdaptationStates. Training improves the active
/// personality's attention patterns. Different personalities have different
/// thresholds for different namespaces.
///
/// Examples:
/// - Medical personality has LOW threshold for health namespace (high attention)
/// - Task Planner has LOW threshold for task namespace
/// - Coach personality has LOW threshold for motivation namespace
///
/// ## Embedded adaptation states
/// Both NamespaceAdaptationState and ToolSelectionAdaptationState are
/// embedded inside Personality as JSON, not separate entities.
/// Single save = Personality + all its learned state atomically.
///
/// ## Usage
/// ```dart
/// // Get active personality
/// final personality = await personalityRepo.getActive();
///
/// // Check namespace attention
/// final taskThreshold = personality.namespaceAttention.getThreshold('task');
///
/// // Check tool selection for a namespace
/// final taskTools = personality.getToolAttention('task');
/// final ranked = taskTools.rankTools(['add', 'new', 'grocery']);
///
/// // After training, save the personality (saves all embedded state)
/// await personalityRepo.save(personality);
/// ```

import 'dart:convert';

import 'package:objectbox/objectbox.dart';

import '../core/base_entity.dart';
import 'namespace_adaptation_state.dart';
import 'tool_selection_adaptation_state.dart';

@Entity()
class Personality extends BaseEntity {
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

  // ============ Identity ============

  /// Display name: "Medical", "Task Planner", "Coach"
  String name;

  /// Optional description
  String? description;

  /// Is this the currently active personality?
  bool isActive = false;

  // ============ LLM Configuration ============

  /// System prompt defining behavioral frame
  /// Example: "You are a helpful medical assistant..."
  String systemPrompt;

  /// Template for formatting user input
  /// May include placeholders like {input}, {context}
  String userPromptTemplate = '{input}';

  /// LLM temperature (0.0 = deterministic, 1.0 = creative)
  /// Different personalities may prefer different risk levels
  double temperature = 0.7;

  /// Base model to use (e.g., "llama-3.3-70b-versatile")
  String baseModel = 'llama-3.3-70b-versatile';

  // ============ Embedded Adaptation States ============

  /// Namespace attention state (embedded, not a relation)
  @Transient()
  NamespaceAdaptationState namespaceAttention = NamespaceAdaptationState();

  /// JSON storage for namespaceAttention
  String namespaceAttentionJson = '{}';

  /// Per-namespace tool selection states (embedded)
  /// Maps namespace ID -> ToolSelectionAdaptationState
  @Transient()
  Map<String, ToolSelectionAdaptationState> toolAttentionPerNamespace = {};

  /// JSON storage for toolAttentionPerNamespace
  String toolAttentionJson = '{}';

  // ============ Constructor ============

  Personality({
    required this.name,
    required this.systemPrompt,
    this.description,
  }) {
    if (uuid.isEmpty) {
      uuid = super.uuid;
    }
  }

  // ============ Attention accessors ============

  /// Get tool attention for a namespace, creating if needed
  ToolSelectionAdaptationState getToolAttention(String namespaceId) {
    _loadToolAttentionIfNeeded();
    return toolAttentionPerNamespace.putIfAbsent(
      namespaceId,
      () => ToolSelectionAdaptationState(namespaceId: namespaceId),
    );
  }

  /// Set tool attention for a namespace
  void setToolAttention(
      String namespaceId, ToolSelectionAdaptationState state) {
    _loadToolAttentionIfNeeded();
    toolAttentionPerNamespace[namespaceId] = state;
    _saveToolAttention();
  }

  /// Get all namespace IDs that have tool attention states
  List<String> get namespacesWithToolAttention {
    _loadToolAttentionIfNeeded();
    return toolAttentionPerNamespace.keys.toList();
  }

  // ============ Lifecycle ============

  /// Prepare for save - serialize embedded states
  void prepareForSave() {
    _saveNamespaceAttention();
    _saveToolAttention();
    touch();
  }

  /// Load after read - deserialize embedded states
  void loadAfterRead() {
    _loadNamespaceAttentionIfNeeded();
    _loadToolAttentionIfNeeded();
  }

  // ============ JSON serialization helpers ============

  void _loadNamespaceAttentionIfNeeded() {
    if (namespaceAttentionJson != '{}') {
      final decoded =
          jsonDecode(namespaceAttentionJson) as Map<String, dynamic>;
      namespaceAttention = NamespaceAdaptationState.fromJson(decoded);
    }
  }

  void _saveNamespaceAttention() {
    namespaceAttentionJson = jsonEncode(namespaceAttention.toJson());
  }

  void _loadToolAttentionIfNeeded() {
    if (toolAttentionPerNamespace.isEmpty && toolAttentionJson != '{}') {
      final decoded = jsonDecode(toolAttentionJson) as Map<String, dynamic>;
      toolAttentionPerNamespace = decoded.map(
        (namespaceId, stateJson) => MapEntry(
          namespaceId,
          ToolSelectionAdaptationState.fromJson(
              stateJson as Map<String, dynamic>),
        ),
      );
    }
  }

  void _saveToolAttention() {
    toolAttentionJson = jsonEncode(
      toolAttentionPerNamespace.map(
        (namespaceId, state) => MapEntry(namespaceId, state.toJson()),
      ),
    );
  }

  // ============ Serialization ============

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'syncId': syncId,
      'name': name,
      'description': description,
      'isActive': isActive,
      'systemPrompt': systemPrompt,
      'userPromptTemplate': userPromptTemplate,
      'temperature': temperature,
      'baseModel': baseModel,
      'namespaceAttention': namespaceAttention.toJson(),
      'toolAttentionPerNamespace': toolAttentionPerNamespace.map(
        (k, v) => MapEntry(k, v.toJson()),
      ),
    };
  }

  factory Personality.fromJson(Map<String, dynamic> json) {
    final personality = Personality(
      name: json['name'] as String,
      systemPrompt: json['systemPrompt'] as String,
      description: json['description'] as String?,
    );

    personality.id = json['id'] as int? ?? 0;
    personality.uuid = json['uuid'] as String? ?? '';
    personality.createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
    personality.updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.now();
    personality.syncId = json['syncId'] as String?;
    personality.isActive = json['isActive'] as bool? ?? false;
    personality.userPromptTemplate =
        json['userPromptTemplate'] as String? ?? '{input}';
    personality.temperature = (json['temperature'] as num?)?.toDouble() ?? 0.7;
    personality.baseModel =
        json['baseModel'] as String? ?? 'llama-3.3-70b-versatile';

    if (json['namespaceAttention'] != null) {
      personality.namespaceAttention = NamespaceAdaptationState.fromJson(
          json['namespaceAttention'] as Map<String, dynamic>);
      personality._saveNamespaceAttention();
    }

    if (json['toolAttentionPerNamespace'] != null) {
      personality.toolAttentionPerNamespace =
          (json['toolAttentionPerNamespace'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k,
            ToolSelectionAdaptationState.fromJson(v as Map<String, dynamic>)),
      );
      personality._saveToolAttention();
    }

    return personality;
  }
}
