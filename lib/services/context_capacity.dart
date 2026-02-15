/// ## Why Trainable?
/// Different models perform optimally with different amounts of context.
/// The optimal point varies by model and use case - too much context
/// degrades quality, too little misses relevant information.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../core/trainable.dart';
import '../core/invocation.dart';
import '../core/adaptation_state_repository.dart';
import '../domain/feedback.dart' as domain_feedback;
import 'tokenizer_service.dart';
import 'types/context_capacity_types.dart';

/// Token budget management service.
///
/// Learns optimal context size per model from feedback.
/// Truncates messages to fit within learned budgets.
class ContextCapacity with Trainable<ContextCapacityAdaptationData> {
  /// Tokenizer for counting tokens.
  final TokenizerService _tokenizer;

  /// Tokens added per message for structure overhead.
  ///
  /// Each message in the conversation has structural overhead:
  /// - Role marker (e.g., "user:", "assistant:")
  /// - Message delimiters
  /// - Special tokens for message boundaries
  ///
  /// This is approximately 4 tokens per message for most models.
  /// Reference: OpenAI tokenizer documentation.
  static const int tokensPerMessageOverhead = 4;

  ContextCapacity({
    TokenizerService? tokenizer,
  }) : _tokenizer = tokenizer ?? TokenizerService.instance;

  // ============ Trainable Implementation ============

  @override
  String get componentType => 'context_capacity';

  @override
  ContextCapacityAdaptationData createDefaultData() =>
      ContextCapacityAdaptationData.defaults();

  @override
  ContextCapacityAdaptationData deserializeData(String json) {
    if (json.isEmpty || json == '{}') {
      return createDefaultData();
    }
    return ContextCapacityAdaptationData.fromJson(
      Map<String, dynamic>.from(
        const JsonDecoder().convert(json) as Map,
      ),
    );
  }

  @override
  Map<String, (double, double)> getParameterBounds() {
    // GP optimization bounds for optimal token counts
    // These apply per-model but we return generic bounds
    return {
      'optimalContextTokens': (500.0, 32000.0),
    };
  }

  @override
  Widget buildFeedbackUI(BuildContext context, Invocation invocation) {
    final output = ContextCapacityInvocationOutput(
      tokenBudget: invocation.output?['tokenBudget'] as int? ?? 0,
      finalTokens: invocation.output?['finalTokens'] as int? ?? 0,
      wasTruncated: invocation.output?['wasTruncated'] as bool? ?? false,
      messagesRemoved: invocation.output?['messagesRemoved'] as int? ?? 0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Context Capacity:',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Token budget: ${output.tokenBudget}'),
              Text('Final tokens: ${output.finalTokens}'),
              Text('Truncated: ${output.wasTruncated ? "Yes" : "No"}'),
              if (output.wasTruncated)
                Text('Messages removed: ${output.messagesRemoved}'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Was the context appropriate?',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ElevatedButton(
              onPressed: () {
                // TODO: Record "just right" feedback
              },
              child: const Text('Just right'),
            ),
            OutlinedButton(
              onPressed: () {
                // TODO: Record "too little" feedback (increase budget)
              },
              child: const Text('Missing context'),
            ),
            OutlinedButton(
              onPressed: () {
                // TODO: Record "too much" feedback (decrease budget)
              },
              child: const Text('Too verbose'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<void> trainFromFeedback(
    Invocation invocation,
    domain_feedback.Feedback feedback,
  ) async {
    // 1. Extract model from invocation
    final input = invocation.input;
    if (input == null) {
      print('⚠️ [ContextCapacity] Cannot train: invocation has no input');
      return;
    }

    final model = input['model'] as String?;
    if (model == null || model.isEmpty) {
      print('⚠️ [ContextCapacity] Cannot train: no model in input');
      return;
    }

    // 2. Get current adaptation state
    final adaptationStateRepo = GetIt.instance<AdaptationStateRepository>();
    final state = await getAdaptationState();
    final params = state.dataJson.isNotEmpty
        ? deserializeData(state.dataJson)
        : createDefaultData();

    // 3. Get current config for model
    final config = params.getConfigForModel(model);
    final currentOptimal = config.optimalContextTokens;

    // 4. Adjust based on feedback
    // This is a simple heuristic - GP optimizer would do better
    int newOptimal = currentOptimal;
    final feedbackText = feedback.correctedData?.toLowerCase() ?? '';

    if (feedback.action == domain_feedback.FeedbackAction.confirm) {
      // Positive feedback - current setting is good
      print('📊 [ContextCapacity] Positive feedback for $model at $currentOptimal tokens');
    } else if (feedback.action == domain_feedback.FeedbackAction.deny) {
      // Negative feedback - adjust based on correction text
      if (feedbackText.contains('missing') || feedbackText.contains('little')) {
        // Increase context
        newOptimal = (currentOptimal * 1.2).round().clamp(500, config.maxContextTokens - config.reservedForResponse);
        print('📊 [ContextCapacity] Increasing $model budget: $currentOptimal → $newOptimal');
      } else if (feedbackText.contains('verbose') || feedbackText.contains('much')) {
        // Decrease context
        newOptimal = (currentOptimal * 0.8).round().clamp(500, config.maxContextTokens - config.reservedForResponse);
        print('📊 [ContextCapacity] Decreasing $model budget: $currentOptimal → $newOptimal');
      } else {
        // Generic negative - small decrease (too much context is more common issue)
        newOptimal = (currentOptimal * 0.95).round().clamp(500, config.maxContextTokens - config.reservedForResponse);
        print('📊 [ContextCapacity] Small decrease for $model: $currentOptimal → $newOptimal');
      }
    }

    // 5. Save updated state if changed
    if (newOptimal != currentOptimal) {
      final newConfig = config.copyWith(optimalContextTokens: newOptimal);
      final newParams = params.copyWithModelConfig(model, newConfig);

      state.dataJson = newParams.toJson();
      state.version++;
      state.lastUpdatedAt = DateTime.now();
      state.lastUpdateReason = 'trainFromFeedback';
      state.feedbackCountApplied++;

      await adaptationStateRepo.save(state);
      print('✅ [ContextCapacity] Adaptation state saved');
    }
  }

  // ============ Context Truncation ============

  /// Truncate messages to fit within model's token budget.
  ///
  /// Preserves:
  /// 1. System message (always)
  /// 2. Most recent user/assistant turns
  ///
  /// Removes oldest turns first when over budget.
  Future<TruncationResult> truncateMessages({
    required List<Map<String, dynamic>> messages,
    required String model,
    required String eventId,
    String? userId,
    int? customTokenBudget, // Optional: override learned budget (for testing)
  }) async {
    // 1. Get adaptation state
    final state = await getAdaptationState(userId: userId);
    final params = state.dataJson.isNotEmpty
        ? deserializeData(state.dataJson)
        : createDefaultData();

    // 2. Get config for this model
    final config = params.getConfigForModel(model);
    final tokenBudget = customTokenBudget ?? config.effectiveContextBudget;

    print('\n📏 [ContextCapacity] Truncating for $model');
    print('   Budget: $tokenBudget tokens');

    // 3. Count tokens in current messages
    final originalTokens = _countMessagesTokens(messages);
    print('   Original: $originalTokens tokens, ${messages.length} messages');

    // 4. Check if truncation needed
    if (originalTokens <= tokenBudget) {
      print('   ✅ No truncation needed');

      // Record invocation
      await _recordInvocationData(
        eventId: eventId,
        model: model,
        originalTokens: originalTokens,
        originalMessageCount: messages.length,
        tokenBudget: tokenBudget,
        finalTokens: originalTokens,
        wasTruncated: false,
        messagesRemoved: 0,
      );

      return TruncationResult(
        messages: messages,
        totalTokens: originalTokens,
        tokenBudget: tokenBudget,
        wasTruncated: false,
      );
    }

    // 5. Truncate by removing oldest non-system messages
    final truncated = _truncateToFit(messages, tokenBudget);
    final finalTokens = _countMessagesTokens(truncated);
    final messagesRemoved = messages.length - truncated.length;
    final tokensRemoved = originalTokens - finalTokens;

    print('   ✂️ Truncated: $finalTokens tokens, ${truncated.length} messages');
    print('   Removed: $messagesRemoved messages, $tokensRemoved tokens');

    // 6. Record invocation
    await _recordInvocationData(
      eventId: eventId,
      model: model,
      originalTokens: originalTokens,
      originalMessageCount: messages.length,
      tokenBudget: tokenBudget,
      finalTokens: finalTokens,
      wasTruncated: true,
      messagesRemoved: messagesRemoved,
    );

    return TruncationResult(
      messages: truncated,
      totalTokens: finalTokens,
      tokenBudget: tokenBudget,
      wasTruncated: true,
      messagesRemoved: messagesRemoved,
      tokensRemoved: tokensRemoved,
    );
  }

  /// Count total tokens in a list of messages.
  int _countMessagesTokens(List<Map<String, dynamic>> messages) {
    int total = 0;
    for (final msg in messages) {
      final content = msg['content'];
      if (content is String) {
        total += _tokenizer.countTokens(content);
      } else if (content is List) {
        // Multi-part content (text + images)
        for (final part in content) {
          if (part is Map && part['type'] == 'text') {
            total += _tokenizer.countTokens(part['text'] as String? ?? '');
          }
        }
      }
      // Add overhead for message structure (role markers, delimiters, etc.)
      total += tokensPerMessageOverhead;
    }
    return total;
  }

  /// Truncate messages to fit within token budget.
  ///
  /// Strategy:
  /// 1. Always keep system message
  /// 2. Keep most recent turns, remove oldest
  List<Map<String, dynamic>> _truncateToFit(
    List<Map<String, dynamic>> messages,
    int tokenBudget,
  ) {
    // Separate system message from conversation
    final systemMessages = <Map<String, dynamic>>[];
    final conversationMessages = <Map<String, dynamic>>[];

    for (final msg in messages) {
      if (msg['role'] == 'system') {
        systemMessages.add(msg);
      } else {
        conversationMessages.add(msg);
      }
    }

    // Start with system messages (must keep)
    final result = List<Map<String, dynamic>>.from(systemMessages);
    int currentTokens = _countMessagesTokens(result);

    // If system messages alone exceed budget, we have a problem
    // Just return system messages in that case
    if (currentTokens >= tokenBudget) {
      print('⚠️ [ContextCapacity] System messages exceed budget!');
      return result;
    }

    // Add conversation messages from most recent backwards
    final toAdd = <Map<String, dynamic>>[];
    for (int i = conversationMessages.length - 1; i >= 0; i--) {
      final msg = conversationMessages[i];
      final msgTokens = _countMessageTokens(msg);

      if (currentTokens + msgTokens <= tokenBudget) {
        toAdd.insert(0, msg); // Insert at front to maintain order
        currentTokens += msgTokens;
      } else {
        // No more room
        break;
      }
    }

    result.addAll(toAdd);
    return result;
  }

  /// Count tokens in a single message.
  int _countMessageTokens(Map<String, dynamic> msg) {
    int tokens = 4; // Overhead for message structure
    final content = msg['content'];
    if (content is String) {
      tokens += _tokenizer.countTokens(content);
    } else if (content is List) {
      for (final part in content) {
        if (part is Map && part['type'] == 'text') {
          tokens += _tokenizer.countTokens(part['text'] as String? ?? '');
        }
      }
    }
    return tokens;
  }

  /// Record invocation for training.
  Future<void> _recordInvocationData({
    required String eventId,
    required String model,
    required int originalTokens,
    required int originalMessageCount,
    required int tokenBudget,
    required int finalTokens,
    required bool wasTruncated,
    required int messagesRemoved,
  }) async {
    await recordInvocation(
      eventId,
      Invocation(
        eventId: eventId,
        componentType: componentType,
        implementer: null,
        success: true,
        confidence: 1.0,
        input: ContextCapacityInvocationInput(
          model: model,
          originalTokens: originalTokens,
          originalMessageCount: originalMessageCount,
        ).toMap(),
        output: ContextCapacityInvocationOutput(
          tokenBudget: tokenBudget,
          finalTokens: finalTokens,
          wasTruncated: wasTruncated,
          messagesRemoved: messagesRemoved,
        ).toMap(),
      ),
    );
  }

  /// Get current token budget for a model.
  ///
  /// Useful for UI display or debugging.
  Future<int> getTokenBudget(String model, {String? userId}) async {
    final state = await getAdaptationState(userId: userId);
    final params = state.dataJson.isNotEmpty
        ? deserializeData(state.dataJson)
        : createDefaultData();
    return params.getConfigForModel(model).effectiveContextBudget;
  }

  /// Update token budget for a model directly.
  ///
  /// For manual adjustment outside of feedback training.
  Future<void> setTokenBudget(String model, int budget) async {
    final adaptationStateRepo = GetIt.instance<AdaptationStateRepository>();
    final state = await getAdaptationState();
    final params = state.dataJson.isNotEmpty
        ? deserializeData(state.dataJson)
        : createDefaultData();

    final config = params.getConfigForModel(model);
    final newConfig = config.copyWith(
      optimalContextTokens: budget.clamp(500, config.maxContextTokens - config.reservedForResponse),
    );
    final newParams = params.copyWithModelConfig(model, newConfig);

    state.dataJson = newParams.toJson();
    state.version++;
    await adaptationStateRepo.save(state);

    print('✅ [ContextCapacity] Set $model budget to $budget tokens');
  }
}
