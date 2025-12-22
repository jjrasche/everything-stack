/// # ContextManager
///
/// ## What it does
/// Core orchestrator for Context Manager + MCP Tools architecture.
/// Handles two-hop tool selection + execution: LLM picks namespace → statistical classifier picks tool → MCPExecutor executes.
///
/// ## Flow
/// 1. Load active Personality (with learned attention patterns)
/// 2. Embed event payload
/// 3. Score namespaces via semantic similarity
/// 4. LLM picks namespace
/// 5. Get tools in namespace, score via statistical classifier
/// 6. Filter tools by threshold
/// 7. Inject namespace-specific context
/// 8. MCPExecutor executes tools (LLM orchestration + MCP execution)
/// 9. Log ContextManagerInvocation
/// 10. Return ContextManagerResult with execution results
///
/// ## Usage
/// ```dart
/// final cm = ContextManager(
///   personalityRepo: personalityRepo,
///   namespaceRepo: namespaceRepo,
///   toolRepo: toolRepo,
///   invocationRepo: invocationRepo,
///   taskRepo: taskRepo,
///   timerRepo: timerRepo,
///   llmService: groqService,
///   embeddingService: embeddingService,
///   mcpExecutor: mcpExecutor,
/// );
///
/// final result = await cm.handleEvent(event);
///
/// // Check execution results
/// for (final execResult in result.executionResults) {
///   if (execResult.success) {
///     print('Tool ${execResult.toolName} succeeded: ${execResult.data}');
///   }
/// }
/// ```

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';

import '../core/feedback_repository.dart';
import '../domain/event.dart';
import '../domain/feedback.dart';
import '../domain/personality.dart';
import '../domain/personality_repository.dart';
import '../domain/namespace.dart' as domain;
import '../domain/namespace_repository.dart';
import '../domain/tool.dart';
import '../domain/tool_repository.dart';
import '../domain/context_manager_invocation.dart';
import '../domain/context_manager_invocation_repository.dart';
import '../tools/task/repositories/task_repository.dart';
import '../tools/timer/repositories/timer_repository.dart';
import 'llm_service.dart';
import 'tts_service.dart';
import 'embedding_service.dart';
import 'context_manager_result.dart';
import 'mcp_executor.dart';
import 'trainable.dart';

class ContextManager implements Trainable {
  final PersonalityRepository personalityRepo;
  final NamespaceRepository namespaceRepo;
  final ToolRepository toolRepo;
  final ContextManagerInvocationRepository invocationRepo;
  final FeedbackRepository feedbackRepo;
  final TaskRepository taskRepo;
  final TimerRepository timerRepo;
  final LLMService llmService;
  final TTSService ttsService;
  final EmbeddingService embeddingService;
  final MCPExecutor mcpExecutor;

  // Event queue for async processing
  final List<Event> _eventQueue = [];
  bool _processingQueue = false;

  ContextManager({
    required this.personalityRepo,
    required this.namespaceRepo,
    required this.toolRepo,
    required this.invocationRepo,
    required this.feedbackRepo,
    required this.taskRepo,
    required this.timerRepo,
    required this.llmService,
    required this.ttsService,
    required this.embeddingService,
    required this.mcpExecutor,
  });

  /// Publish an event for async processing
  ///
  /// Queues event and starts queue processor if not already running.
  /// Returns immediately - processing happens asynchronously.
  Future<void> publishEvent(Event event) async {
    _eventQueue.add(event);
    // Start queue processing if not already running
    if (!_processingQueue) {
      _processQueue();
    }
  }

  /// Process queued events asynchronously
  ///
  /// Runs continuously, processing events one at a time from the queue.
  /// This is fire-and-forget - errors don't propagate to caller.
  void _processQueue() async {
    if (_processingQueue) return;
    _processingQueue = true;

    while (_eventQueue.isNotEmpty) {
      final event = _eventQueue.removeAt(0);
      try {
        await handleEvent(event);
      } catch (e) {
        // Log error but continue processing queue
        print('Error processing event ${event.correlationId}: $e');
      }
    }

    _processingQueue = false;
  }

  /// Handle an event - main entry point
  Future<ContextManagerResult> handleEvent(Event event) async {
    final startTime = DateTime.now();
    final invocation = ContextManagerInvocation(
      correlationId: event.correlationId,
      eventPayloadJson: jsonEncode(event.payload),
    );

    try {
      // 1. Load active personality
      final personality = await personalityRepo.getActive();
      if (personality == null) {
        return _errorResult(
          invocation,
          'No active personality',
          'no_personality',
        );
      }
      invocation.personalityId = personality.uuid;

      // 2. Embed event
      final utterance = event.payload['transcription'] as String? ?? '';
      if (utterance.isEmpty) {
        return _errorResult(invocation, 'Empty utterance', 'empty_input');
      }

      final embedding = await embeddingService.generate(utterance);
      invocation.eventEmbedding = embedding;

      // 3. Select namespace (two-hop: semantic + LLM)
      final namespaceResult = await _selectNamespace(
        personality,
        utterance,
        embedding,
        invocation,
      );

      if (namespaceResult == null) {
        invocation.confidence = 0.0;
        await _saveInvocation(invocation, startTime);
        return ContextManagerResult.noNamespace(
          invocationId: invocation.uuid,
        );
      }

      final selectedNamespace = namespaceResult['namespace'] as String;
      invocation.selectedNamespace = selectedNamespace;

      // 4. Filter tools in namespace
      final toolsResult = await _filterTools(
        personality,
        selectedNamespace,
        utterance,
        embedding,
        invocation,
      );

      if (toolsResult.isEmpty) {
        invocation.confidence = 0.0;
        await _saveInvocation(invocation, startTime);
        return ContextManagerResult.noTools(
          selectedNamespace: selectedNamespace,
          invocationId: invocation.uuid,
        );
      }

      // 5. Inject namespace context
      final context = await _injectContext(selectedNamespace);
      invocation.contextItemCounts = {
        'tasks': context['tasks']?.length ?? 0,
        'timers': context['timers']?.length ?? 0,
      };

      // 6. Execute tools via MCPExecutor (LLM orchestration + execution)
      final executionResult = await mcpExecutor.execute(
        personality: personality,
        utterance: utterance,
        tools: toolsResult,
        context: context,
        correlationId: event.correlationId,
      );

      if (!executionResult.success) {
        return _errorResult(
          invocation,
          executionResult.error ?? 'Tool execution failed',
          executionResult.errorType ?? 'execution_error',
        );
      }

      // 7. Synthesize LLM response via TTS (records TTSInvocation)
      if (executionResult.finalResponse != null &&
          executionResult.finalResponse!.isNotEmpty) {
        try {
          // Call TTS to synthesize the LLM response
          // This records a TTSInvocation with the same correlationId
          await for (final audioChunk
              in ttsService.synthesize(executionResult.finalResponse!)) {
            // Stream audio chunks (application layer handles playback)
          }
        } catch (e) {
          // TTS failure is non-fatal - log but continue
          print('TTS synthesis failed: $e');
        }
      }

      // 8. Extract tool calls and apply confidence scores
      final toolCalls = executionResult.toolCalls.map((tc) {
        // Use confidence from tool scoring, not default
        final confidence = invocation.toolScores[tc.toolName] ?? 0.5;
        return ToolCall(
          toolName: tc.toolName,
          params: tc.params,
          confidence: confidence,
          callId: tc.callId,
        );
      }).toList();

      invocation.toolsCalled = toolCalls.map((tc) => tc.toolName).toList();

      // 8. Calculate confidence (avg of tool selection scores)
      final confidence = toolCalls.isEmpty
          ? 0.0
          : toolCalls.fold<double>(0.0, (sum, tc) => sum + tc.confidence) /
              toolCalls.length;
      invocation.confidence = confidence;

      // 9. Save invocation
      await _saveInvocation(invocation, startTime);

      // 10. Return result with execution results
      return ContextManagerResult.success(
        selectedNamespace: selectedNamespace,
        toolCalls: toolCalls,
        confidence: confidence,
        invocationId: invocation.uuid,
        assembledContext: context,
        executionResults: executionResult.toolResults,
        llmResponse: executionResult.finalResponse,
      );
    } on LLMTimeoutException catch (e) {
      return _errorResult(invocation, e.message, 'llm_timeout');
    } on LLMRateLimitException catch (e) {
      return _errorResult(invocation, e.message, 'llm_rate_limit');
    } on LLMServerException catch (e) {
      return _errorResult(invocation, e.message, 'llm_server_error');
    } on LLMException catch (e) {
      return _errorResult(invocation, e.message, 'llm_error');
    } catch (e) {
      return _errorResult(invocation, e.toString(), 'unknown_error');
    }
  }

  /// Select namespace via semantic similarity + LLM confirmation
  Future<Map<String, dynamic>?> _selectNamespace(
    Personality personality,
    String utterance,
    List<double> embedding,
    ContextManagerInvocation invocation,
  ) async {
    // Get all namespaces
    final namespaces = await namespaceRepo.findAll();
    invocation.namespacesConsidered =
        namespaces.map((ns) => ns.name).toList();

    // Score each namespace
    final scores = <String, double>{};
    for (final ns in namespaces) {
      if (ns.semanticCentroid != null) {
        final similarity =
            _cosineSimilarity(embedding, ns.semanticCentroid!);
        scores[ns.name] = similarity;
      } else {
        scores[ns.name] = 0.0;
      }
    }
    invocation.namespaceScores = scores;

    // Filter by threshold (from personality's learned attention)
    final candidates = <domain.Namespace>[];
    for (final ns in namespaces) {
      final score = scores[ns.name] ?? 0.0;
      final threshold =
          personality.namespaceAttention.getThreshold(ns.name);
      if (score >= threshold) {
        candidates.add(ns);
      }
    }

    if (candidates.isEmpty) return null;

    // If only one candidate, use it
    if (candidates.length == 1) {
      return {'namespace': candidates.first.name};
    }

    // Multiple candidates - ask LLM to pick
    final namespaceNames = candidates.map((ns) => ns.name).toList();
    final llmResponse = await llmService.chatWithTools(
      model: personality.baseModel,
      messages: [
        {
          'role': 'system',
          'content':
              'Pick the most relevant namespace for this user request. Respond with ONLY the namespace name, nothing else.',
        },
        {
          'role': 'user',
          'content':
              'User request: "$utterance"\n\nAvailable namespaces: ${namespaceNames.join(", ")}\n\nWhich namespace?',
        },
      ],
      tools: null, // No tool calling needed for namespace selection
      temperature: 0.0, // Deterministic
    );

    final selected = llmResponse.content?.trim().toLowerCase();
    if (selected != null && namespaceNames.contains(selected)) {
      return {'namespace': selected};
    }

    // LLM picked invalid namespace - use highest scoring
    candidates.sort((a, b) {
      final scoreB = scores[b.name] ?? 0.0;
      final scoreA = scores[a.name] ?? 0.0;
      return scoreB.compareTo(scoreA);
    });
    return {'namespace': candidates.first.name};
  }

  /// Filter tools in namespace via statistical classifier
  Future<List<Tool>> _filterTools(
    Personality personality,
    String namespaceId,
    String utterance,
    List<double> embedding,
    ContextManagerInvocation invocation,
  ) async {
    // Get all tools in namespace
    final tools = await toolRepo.findByNamespace(namespaceId);
    invocation.toolsAvailable = tools.map((t) => t.fullName).toList();

    if (tools.isEmpty) return [];

    // Get tool attention state for this namespace
    final toolAttention = personality.getToolAttention(namespaceId);

    // Score each tool
    final scores = <String, double>{};
    final keywords = _extractKeywords(utterance);

    for (final tool in tools) {
      // Semantic score
      double semanticScore = 0.0;
      if (tool.semanticCentroid != null) {
        semanticScore =
            _cosineSimilarity(embedding, tool.semanticCentroid!);
      }

      // Statistical score (from training)
      final statisticalScore = toolAttention.scoreTool(tool.name, keywords);

      // Combined score (weighted average)
      final combinedScore = 0.6 * semanticScore + 0.4 * statisticalScore;
      scores[tool.fullName] = combinedScore;
    }
    invocation.toolScores = scores;

    // Filter by threshold (default 0.5 for MVP)
    const toolThreshold = 0.5;
    final passedTools = tools.where((tool) {
      final score = scores[tool.fullName] ?? 0.0;
      return score >= toolThreshold;
    }).toList();

    invocation.toolsFiltered = tools
        .where((t) => !passedTools.contains(t))
        .map((t) => t.fullName)
        .toList();
    invocation.toolsPassedToLLM =
        passedTools.map((t) => t.fullName).toList();

    return passedTools;
  }

  /// Inject namespace-specific context
  Future<Map<String, dynamic>> _injectContext(String namespaceId) async {
    final context = <String, dynamic>{};

    if (namespaceId == 'task') {
      // Inject incomplete tasks
      final incompleteTasks = await taskRepo.findIncomplete();
      context['tasks'] = incompleteTasks
          .map((t) => {
                'title': t.title,
                'priority': t.priority,
                'dueDate': t.dueDate?.toIso8601String(),
              })
          .toList();
    } else if (namespaceId == 'timer') {
      // Inject active timers
      final activeTimers = await timerRepo.findActive();
      context['timers'] = activeTimers
          .map((t) => {
                'label': t.label,
                'remainingSeconds': t.remainingSeconds,
              })
          .toList();
    }

    return context;
  }

  /// Save invocation with timing
  Future<void> _saveInvocation(
    ContextManagerInvocation invocation,
    DateTime startTime,
  ) async {
    invocation.latencyMs = DateTime.now().difference(startTime).inMilliseconds;
    invocation.timestamp = DateTime.now();
    await invocationRepo.save(invocation);
  }

  /// Create error result
  ContextManagerResult _errorResult(
    ContextManagerInvocation invocation,
    String error,
    String errorType,
  ) {
    invocation.errorType = errorType;
    invocation.errorMessage = error;
    invocation.timestamp = DateTime.now();
    invocationRepo.save(invocation); // Fire and forget
    return ContextManagerResult.error(
      invocationId: invocation.uuid,
      error: error,
      errorType: errorType,
    );
  }

  // ============ Utility functions ============

  /// Cosine similarity between two vectors
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    var dotProduct = 0.0;
    var normA = 0.0;
    var normB = 0.0;

    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0.0 || normB == 0.0) return 0.0;

    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  /// Extract keywords from utterance (simple tokenization for MVP)
  List<String> _extractKeywords(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 2)
        .toList();
  }

  // ============================================================================
  // Trainable Implementation
  // ============================================================================

  @override
  Future<String> recordInvocation(dynamic invocation) async {
    if (invocation is! ContextManagerInvocation) {
      throw ArgumentError('Expected ContextManagerInvocation');
    }
    invocation.prepareForSave();
    await invocationRepo.save(invocation);
    return invocation.uuid;
  }

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {
    // Query feedback for context manager on this turn
    final feedbackList = await feedbackRepo.findByTurnAndComponent(
      turnId,
      'context_manager',
    );

    if (feedbackList.isEmpty) return;

    // Load active personality
    final personality = await personalityRepo.getActive();
    if (personality == null) return;

    // Make sure personality is loaded
    personality.loadAfterRead();

    // Process each feedback
    for (final feedback in feedbackList) {
      if (!feedback.hasCorrection) continue;

      // Load the invocation
      final invocation = await invocationRepo.findByUuid(feedback.invocationId);
      if (invocation == null) continue;

      invocation.loadAfterRead();

      // Parse corrected data as JSON {namespace?, tool?}
      late final Map<String, dynamic> corrected;
      try {
        corrected = jsonDecode(feedback.correctedData!) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      // Train namespace if provided
      if (corrected['namespace'] is String) {
        final correctNamespace = corrected['namespace'] as String;

        // Raise threshold for wrong namespace
        if (invocation.selectedNamespace != null &&
            invocation.selectedNamespace != correctNamespace) {
          personality.namespaceAttention
              .raiseThreshold(invocation.selectedNamespace!);
        }

        // Lower threshold for correct namespace
        personality.namespaceAttention.lowerThreshold(correctNamespace);

        // Update centroid (extract utterance from eventPayloadJson)
        String utterance = '';
        try {
          final eventPayload =
              jsonDecode(invocation.eventPayloadJson) as Map<String, dynamic>?;
          utterance = eventPayload?['transcription'] as String? ?? '';
        } catch (_) {
          utterance = '';
        }

        if (utterance.isNotEmpty) {
          final newEmbedding =
              await embeddingService.generate(utterance);
          personality.namespaceAttention
              .updateCentroid(correctNamespace, newEmbedding);
        }
      }

      // Train tool selection if provided
      if (corrected['tool'] is String) {
        final correctTool = corrected['tool'] as String;
        final namespace = invocation.selectedNamespace;
        if (namespace == null) continue;

        final toolAttention = personality.getToolAttention(namespace);
        final correctToolName = correctTool.split('.').last;
        final selectedToolName = invocation.toolsCalled.isNotEmpty
            ? invocation.toolsCalled.first.split('.').last
            : null;

        // Adjust success rates
        if (selectedToolName != null && selectedToolName != correctToolName) {
          final currentSuccessRate =
              toolAttention.getSuccessRate(selectedToolName);
          toolAttention.setSuccessRate(
              selectedToolName,
              (currentSuccessRate - 0.1)
                  .clamp(0.0, 1.0));

          final correctSuccessRate =
              toolAttention.getSuccessRate(correctToolName);
          toolAttention.setSuccessRate(
              correctToolName,
              (correctSuccessRate + 0.1)
                  .clamp(0.0, 1.0));
        }

        // Update keyword weights
        String utterance = '';
        try {
          final eventPayload =
              jsonDecode(invocation.eventPayloadJson) as Map<String, dynamic>?;
          utterance = eventPayload?['transcription'] as String? ?? '';
        } catch (_) {
          utterance = '';
        }

        final keywords = _extractKeywords(utterance);
        for (final keyword in keywords) {
          if (keyword.isNotEmpty) {
            final currentWeight =
                toolAttention.getKeywordWeight(correctToolName, keyword);
            toolAttention.setKeywordWeight(
                correctToolName, keyword, currentWeight + 0.2);

            if (selectedToolName != null && selectedToolName != correctToolName) {
              final selectedWeight =
                  toolAttention.getKeywordWeight(selectedToolName, keyword);
              toolAttention.setKeywordWeight(selectedToolName, keyword,
                  (selectedWeight - 0.1).clamp(0.0, 1.0));
            }
          }
        }
      }
    }

    // Save updated personality
    personality.prepareForSave();
    await personalityRepo.save(personality);
  }

  @override
  Future<Map<String, dynamic>> getAdaptationState({String? userId}) async {
    final personality = await personalityRepo.getActive();
    if (personality == null) return {};

    personality.loadAfterRead();

    return {
      'namespaceAttention': {
        'thresholds': personality.namespaceAttention.namespaceThresholds,
        'trainingSampleCount':
            personality.namespaceAttention.trainingSampleCount,
      },
      'toolAttentionPerNamespace': personality.toolAttentionPerNamespace.map(
        (ns, state) => MapEntry(ns, {
          'successRates': state.toolSuccessRates,
          'trainingSampleCount': state.trainingSampleCount,
        }),
      ),
    };
  }

  @override
  Widget buildFeedbackUI(String invocationId) {
    // Build UI for user to review and provide feedback
    // This would typically show namespace/tool selection with ability to correct
    // For now, return a placeholder
    return Placeholder();
  }
}
