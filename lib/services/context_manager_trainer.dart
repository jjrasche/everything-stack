/// # ContextManagerTrainer
///
/// ## What it does
/// Implements training feedback loop for namespace and tool selection.
/// When user corrects a wrong decision, updates the personality's
/// adaptation states to improve future decisions.
///
/// ## Key insight
/// Training operates at two levels:
/// 1. Namespace selection (hop 1): Adjust thresholds and centroids
/// 2. Tool selection (hop 2): Adjust success rates and keyword weights
///
/// A single correction trains BOTH levels:
/// - Raise threshold for wrongly-selected namespace
/// - Lower threshold for correct namespace
/// - Update centroid toward the utterance embedding
/// - Adjust tool success rates and keyword associations
///
/// ## Usage
/// ```dart
/// final trainer = ContextManagerTrainer(
///   personalityRepo: personalityRepo,
///   invocationRepo: invocationRepo,
///   embeddingService: embeddingService,
/// );
///
/// // After user says "No, that should be a timer task"
/// await trainer.trainNamespace(
///   invocationId: invocation.uuid,
///   correctNamespace: 'timer',
/// );
///
/// // After user says "No, I wanted 'complete', not 'create'"
/// await trainer.trainToolSelection(
///   invocationId: invocation.uuid,
///   correctTool: 'timer.cancel',
///   keywords: ['stop', 'cancel', 'timer'],
/// );
/// ```

import 'package:everything_stack_template/domain/personality_repository.dart';
import 'package:everything_stack_template/domain/context_manager_invocation_repository.dart';
import 'package:everything_stack_template/services/embedding_service.dart';

class ContextManagerTrainer {
  final PersonalityRepository personalityRepo;
  final ContextManagerInvocationRepository invocationRepo;
  final EmbeddingService embeddingService;

  ContextManagerTrainer({
    required this.personalityRepo,
    required this.invocationRepo,
    required this.embeddingService,
  });

  /// Train namespace selection based on user feedback
  ///
  /// When user feedback indicates namespace was wrong:
  /// 1. Raise threshold for wrongly-selected namespace (make it harder to trigger)
  /// 2. Lower threshold for correct namespace (make it easier to trigger)
  /// 3. Update correct namespace's centroid toward the utterance embedding
  ///
  /// Returns true if training was successful, false if invocation not found
  Future<bool> trainNamespace({
    required String invocationId,
    required String correctNamespace,
  }) async {
    // Load the invocation that needs training
    final invocation = await invocationRepo.findByUuid(invocationId);
    if (invocation == null) {
      print('ERROR: Invocation $invocationId not found for training');
      return false;
    }

    // Load the personality that made the wrong decision
    final personality = await personalityRepo.getActive();
    if (personality == null) {
      print('ERROR: No active personality for training');
      return false;
    }

    final wrongNamespace = invocation.selectedNamespace;
    if (wrongNamespace == null) {
      print('WARNING: Invocation had no selected namespace');
      return false;
    }

    // Only train if it was actually wrong
    if (wrongNamespace == correctNamespace) {
      print('INFO: Selected namespace was correct, skipping training');
      return true;
    }

    print('Training: $wrongNamespace → $correctNamespace');

    // Raise threshold for wrongly-selected namespace
    // This makes it harder to select that namespace in the future
    personality.namespaceAttention.raiseThreshold(wrongNamespace);
    print('  Raised threshold for $wrongNamespace');

    // Lower threshold for correct namespace
    // This makes it easier to select the correct namespace in the future
    personality.namespaceAttention.lowerThreshold(correctNamespace);
    print('  Lowered threshold for $correctNamespace');

    // Update centroid for correct namespace toward the utterance embedding
    // This makes the semantic center of the namespace more similar to this utterance
    if (invocation.eventEmbedding.isNotEmpty) {
      personality.namespaceAttention.updateCentroid(
        correctNamespace,
        invocation.eventEmbedding,
      );
      print('  Updated centroid for $correctNamespace');
    }

    // Record training event
    personality.namespaceAttention.recordTraining();

    // Save the updated personality (saves all embedded adaptation states)
    await personalityRepo.save(personality);
    print('  Saved updated personality');

    return true;
  }

  /// Train tool selection based on user feedback
  ///
  /// When user feedback indicates tool was wrong within a namespace:
  /// 1. Decrease success rate for wrongly-selected tool
  /// 2. Increase success rate for correct tool
  /// 3. Update keyword weights to associate keywords with correct tool
  ///
  /// Returns true if training was successful, false if invocation/tool not found
  Future<bool> trainToolSelection({
    required String invocationId,
    required String correctTool,
    List<String> keywords = const [],
  }) async {
    // Load the invocation that needs training
    final invocation = await invocationRepo.findByUuid(invocationId);
    if (invocation == null) {
      print('ERROR: Invocation $invocationId not found for training');
      return false;
    }

    // Load the personality that made the wrong decision
    final personality = await personalityRepo.getActive();
    if (personality == null) {
      print('ERROR: No active personality for training');
      return false;
    }

    final namespace = invocation.selectedNamespace;
    if (namespace == null) {
      print('WARNING: Invocation had no selected namespace');
      return false;
    }

    // Get tool attention state for this namespace
    final toolState = personality.getToolAttention(namespace);

    // Find which tool was actually selected
    final selectedTool = invocation.toolsCalled.isNotEmpty
        ? invocation.toolsCalled.first
        : null;

    if (selectedTool == null) {
      print('WARNING: Invocation had no tools called');
      return false;
    }

    // Only train if it was actually wrong
    if (selectedTool == correctTool) {
      print('INFO: Selected tool was correct, skipping training');
      return true;
    }

    print('Training: $selectedTool → $correctTool in namespace $namespace');

    // Apply feedback to the tool attention state
    // This adjusts success rates and keyword weights
    toolState.applyFeedback(
      selectedTool: selectedTool,
      correctTool: correctTool,
      keywords: keywords.isNotEmpty
          ? keywords
          : _extractKeywords(invocation.eventPayloadJson),
    );
    print('  Applied feedback: penalized $selectedTool, boosted $correctTool');

    // Record training event
    toolState.recordTraining();

    // Save the updated personality
    await personalityRepo.save(personality);
    print('  Saved updated personality');

    return true;
  }

  /// Extract keywords from utterance for training
  /// Simple extraction: split by whitespace, filter short words
  static List<String> _extractKeywords(String utteranceJson) {
    try {
      // For now, just return empty list
      // A real implementation would parse the JSON and extract utterance,
      // then split into words and filter for meaningful keywords
      return [];
    } catch (e) {
      return [];
    }
  }
}
