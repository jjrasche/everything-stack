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
    final invocationInput = invocation.input;
    if (invocationInput == null) {
      print('⚠️ [ContextCapacity] Cannot train: invocation has no input');
      return;
    }

    final model = invocationInput['model'] as String?;
    if (model == null || model.isEmpty) {
      print('⚠️ [ContextCapacity] Cannot train: no model in input');
      return;
    }

    final adaptationStateRepo = GetIt.instance<AdaptationStateRepository>();
    final state = await getAdaptationState();
    final params = state.dataJson.isNotEmpty
        ? deserializeData(state.dataJson)
        : createDefaultData();

    final config = params.getConfigForModel(model);
    final currentOptimal = config.optimalContextTokens;

    int newOptimal = currentOptimal;
    final feedbackText = feedback.correctedData?.toLowerCase() ?? '';

    if (feedback.action == domain_feedback.FeedbackAction.confirm) {
      print('📊 [ContextCapacity] Positive feedback for $model at $currentOptimal tokens');
    } else if (feedback.action == domain_feedback.FeedbackAction.deny) {
      if (feedbackText.contains('missing') || feedbackText.contains('little')) {
        newOptimal = (currentOptimal * 1.2).round().clamp(500, config.maxContextTokens - config.reservedForResponse);
        print('📊 [ContextCapacity] Increasing $model budget: $currentOptimal → $newOptimal');
      } else if (feedbackText.contains('verbose') || feedbackText.contains('much')) {
        newOptimal = (currentOptimal * 0.8).round().clamp(500, config.maxContextTokens - config.reservedForResponse);
        print('📊 [ContextCapacity] Decreasing $model budget: $currentOptimal → $newOptimal');
      } else {
        newOptimal = (currentOptimal * 0.95).round().clamp(500, config.maxContextTokens - config.reservedForResponse);
        print('📊 [ContextCapacity] Small decrease for $model: $currentOptimal → $newOptimal');
      }
    }

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
    final state = await getAdaptationState(userId: userId);
    final params = state.dataJson.isNotEmpty
        ? deserializeData(state.dataJson)
        : createDefaultData();

    final config = params.getConfigForModel(model);
    final tokenBudget = customTokenBudget ?? config.effectiveContextBudget;

    print('\n📏 [ContextCapacity] Truncating for $model');
    print('   Budget: $tokenBudget tokens');

    final originalTokens = _countMessagesTokens(messages);
    print('   Original: $originalTokens tokens, ${messages.length} messages');

    if (originalTokens <= tokenBudget) {
      print('   ✅ No truncation needed');

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

    final truncated = _truncateToFit(messages, tokenBudget);
    final finalTokens = _countMessagesTokens(truncated);
    final messagesRemoved = messages.length - truncated.length;
    final tokensRemoved = originalTokens - finalTokens;

    print('   ✂️ Truncated: $finalTokens tokens, ${truncated.length} messages');
    print('   Removed: $messagesRemoved messages, $tokensRemoved tokens');

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

  int _countMessagesTokens(List<Map<String, dynamic>> messages) {
    int totalTokenCount = 0;
    for (final message in messages) {
      final messageContent = message['content'];
      if (messageContent is String) {
        totalTokenCount += _tokenizer.countTokens(messageContent);
      } else if (messageContent is List) {
        for (final contentPart in messageContent) {
          if (contentPart is Map && contentPart['type'] == 'text') {
            totalTokenCount += _tokenizer.countTokens(contentPart['text'] as String? ?? '');
          }
        }
      }
      totalTokenCount += tokensPerMessageOverhead;
    }
    return totalTokenCount;
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
    final systemMessages = <Map<String, dynamic>>[];
    final conversationMessages = <Map<String, dynamic>>[];

    for (final message in messages) {
      if (message['role'] == 'system') {
        systemMessages.add(message);
      } else {
        conversationMessages.add(message);
      }
    }

    final truncatedMessages = List<Map<String, dynamic>>.from(systemMessages);
    int currentTokens = _countMessagesTokens(truncatedMessages);

    if (currentTokens >= tokenBudget) {
      print('⚠️ [ContextCapacity] System messages exceed budget!');
      return truncatedMessages;
    }

    final messagesToAdd = <Map<String, dynamic>>[];
    for (int i = conversationMessages.length - 1; i >= 0; i--) {
      final message = conversationMessages[i];
      final messageTokenCount = _countMessageTokens(message);

      if (currentTokens + messageTokenCount <= tokenBudget) {
        messagesToAdd.insert(0, message);
        currentTokens += messageTokenCount;
      } else {
        break;
      }
    }

    truncatedMessages.addAll(messagesToAdd);
    return truncatedMessages;
  }

  int _countMessageTokens(Map<String, dynamic> message) {
    int tokenCount = tokensPerMessageOverhead;
    final messageContent = message['content'];
    if (messageContent is String) {
      tokenCount += _tokenizer.countTokens(messageContent);
    } else if (messageContent is List) {
      for (final contentPart in messageContent) {
        if (contentPart is Map && contentPart['type'] == 'text') {
          tokenCount += _tokenizer.countTokens(contentPart['text'] as String? ?? '');
        }
      }
    }
    return tokenCount;
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
