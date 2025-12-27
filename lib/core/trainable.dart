/// # Trainable
///
/// ## What it does
/// Mixin class enabling any service to participate in trainable system.
/// Handles invocation recording, adaptation state management, and feedback training.
///
/// ## Trainable Pattern
/// Each trainable component (STT, LLM, TTS, NamespaceSelector, etc.) defines:
/// 1. Component-specific AdaptationData subclass (e.g., STTAdaptationData)
/// 2. Mix into service class: `class STTService with Trainable<STTAdaptationData>`
/// 3. Implement abstract properties: componentType, deserializeData(), createDefaultData()
/// 4. trainFromFeedback() is a shared stub (no learning logic yet)
///
/// ## Usage Example
/// ```dart
/// class STTAdaptationData extends AdaptationData {
///   double confidenceThreshold = 0.65;
///   int minFeedbackCount = 10;
///
///   @override
///   String toJson() => jsonEncode({
///     'confidenceThreshold': confidenceThreshold,
///     'minFeedbackCount': minFeedbackCount,
///   });
///
///   factory STTAdaptationData.fromJson(String json) {
///     final map = jsonDecode(json) as Map<String, dynamic>;
///     return STTAdaptationData()
///       ..confidenceThreshold = map['confidenceThreshold'] as double? ?? 0.65
///       ..minFeedbackCount = map['minFeedbackCount'] as int? ?? 10;
///   }
/// }
///
/// class STTService with Trainable<STTAdaptationData> {
///   @override
///   String get componentType => 'stt';
///
///   @override
///   STTAdaptationData createDefaultData() => STTAdaptationData();
///
///   @override
///   STTAdaptationData deserializeData(String json) =>
///       STTAdaptationData.fromJson(json);
///
///   Future<String> transcribe(String audioId) async {
///     // ... transcription logic ...
///
///     // Record invocation for training
///     await recordInvocation(correlationId, Invocation(
///       correlationId: correlationId,
///       componentType: componentType,
///       success: true,
///       confidence: 0.95,
///       output: {'transcription': result},
///     ));
///   }
/// }
/// ```
///
/// ## Adaptation Scope (User vs Global)
/// Each component has adaptive state at two levels:
/// - **Global**: Baseline settings for all users (shared improvement)
/// - **User**: Per-user overrides (personalization)
///
/// Example:
/// ```dart
/// // Get user-scoped adaptation (falls back to global if not set)
/// final userAdaptation = await getAdaptationState(userId: 'user_123');
/// userAdaptation.data['confidenceThreshold']; // User-specific or global
///
/// // Get global adaptation
/// final globalAdaptation = await getAdaptationState();
/// ```

import 'package:get_it/get_it.dart';

import 'adaptation_data.dart';
import 'adaptation_state.dart';
import '../domain/invocation.dart';
import 'invocation_repository.dart';
import 'adaptation_state_repository.dart';

mixin class Trainable<D extends AdaptationData> {
  // ============ Abstract Properties (must be implemented by subclass) ============

  /// Component identifier: 'stt', 'llm', 'tts', 'namespace_selector', etc.
  /// Must be overridden by implementing classes
  String get componentType => throw UnimplementedError('componentType must be implemented');

  /// Create default adaptation data (new component with no training)
  /// Must be overridden by implementing classes
  D createDefaultData() => throw UnimplementedError('createDefaultData must be implemented');

  /// Deserialize adaptation data from JSON string
  /// Must be overridden by implementing classes
  D deserializeData(String json) => throw UnimplementedError('deserializeData must be implemented');

  /// Retrieve or create adaptation state for this component.
  /// userId: if provided, get user-scoped state; if null, get global state
  /// Returns: Fallback chain: user-scoped → global → default
  Future<AdaptationState> getAdaptationState({String? userId}) async {
    return _adaptationStateRepo.getForComponent(componentType, userId: userId);
  }

  // ============ Repository Access (GetIt) ============

  InvocationRepository get _invocationRepo =>
      GetIt.instance<InvocationRepository>();

  AdaptationStateRepository get _adaptationStateRepo =>
      GetIt.instance<AdaptationStateRepository>();

  // ============ Shared Trainable Methods ============

  /// Record an invocation for later feedback/training.
  /// Called immediately after component executes.
  /// Invocation is stored with input/output for semantic search and training.
  Future<void> recordInvocation(
    String correlationId,
    Invocation invocation,
  ) async {
    final inv = Invocation(
      correlationId: correlationId,
      componentType: componentType,
      success: invocation.success,
      confidence: invocation.confidence,
      input: invocation.input,
      output: invocation.output,
      metadata: invocation.metadata,
    );

    // Generate embedding if Invocation has text output (STT/LLM)
    await inv.generateEmbedding();

    // Save to repository for semantic search and training
    await _invocationRepo.save(inv);
  }

  /// Train component from user feedback.
  /// Stub implementation: no learning logic yet.
  /// Future phase will implement learning from feedback patterns.
  /// Called after user provides corrections/ratings for a turn.
  Future<void> trainFromFeedback(String turnId) async {
    // Placeholder: learning logic deferred to Phase 2.
    // When implemented, this will:
    // 1. Fetch all Feedback for this turnId with action=correct or action=rating
    // 2. For each Feedback, fetch the corresponding Invocation
    // 3. Update AdaptationState based on feedback patterns
    // 4. Save updated AdaptationState
  }

  /// Get context for feedback UI builder.
  /// Helper to pass invocation details to feedback collection UI.
  Future<FeedbackWithContext> buildFeedbackContext(
    Invocation invocation,
  ) async {
    final adaptationState = await getAdaptationState();
    return FeedbackWithContext(
      invocation: invocation,
      componentType: componentType,
      currentAdaptationState: adaptationState,
    );
  }
}

/// Helper class to pass context to feedback UI builders
class FeedbackWithContext {
  final Invocation invocation;
  final String componentType;
  final AdaptationState currentAdaptationState;

  FeedbackWithContext({
    required this.invocation,
    required this.componentType,
    required this.currentAdaptationState,
  });
}
