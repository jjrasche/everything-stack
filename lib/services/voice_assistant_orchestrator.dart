/// # VoiceAssistantOrchestrator (DEPRECATED - Being refactored)
///
/// ## Status
/// This orchestrator is being refactored to use the new Coordinator pattern
/// with separate Trainable components.
///
/// Will be replaced in Phase 5 of the architectural redesign.
///
/// ## Usage
/// ```dart
/// final orchestrator = VoiceAssistantOrchestrator(
///   sttService: sttService,
///   contextManager: contextManager,
///   llmService: llmService,
///   ttsService: ttsService,
///   turnRepo: turnRepo,
///   // ...other repos
/// );
///
/// final result = await orchestrator.processAudio(
///   audioBytes: recordedAudio,
///   correlationId: 'user_123_turn_1',
/// );
///
/// print('Transcript: ${result.transcript}');
/// print('Response: ${result.response}');
/// // Play result.audioBytes to user
/// ```

import 'dart:async';
import 'dart:typed_data';

import '../domain/event.dart';
import '../domain/turn.dart';
import '../domain/turn_repository.dart';
import '../domain/invocations.dart';
import '../domain/stt_invocation_repository.dart';
import '../domain/llm_invocation_repository.dart';
import '../domain/tts_invocation_repository.dart';
import 'coordinator.dart';
import 'llm_service.dart';
import 'stt_service.dart';
import 'tts_service.dart';

/// Result of processing user audio through the full pipeline
class VoiceAssistantResult {
  /// Unique identifier for this interaction
  final String turnId;

  /// User's spoken text (from STT)
  final String transcript;

  /// LLM's response text
  final String response;

  /// Audio bytes for TTS response (wav/pcm)
  final Uint8List audioBytes;

  /// Tools that were called and their results
  final List<MCPToolResult> toolResults;

  /// Did the entire pipeline succeed?
  final bool success;

  /// Error message if !success
  final String? errorMessage;

  /// Which component failed (if any)
  final String? failureComponent;

  /// Total latency for the turn (ms)
  final int latencyMs;

  VoiceAssistantResult({
    required this.turnId,
    required this.transcript,
    required this.response,
    required this.audioBytes,
    required this.toolResults,
    required this.success,
    this.errorMessage,
    this.failureComponent,
    required this.latencyMs,
  });
}

/// Orchestrates the complete voice assistant pipeline
class VoiceAssistantOrchestrator {
  final STTService sttService;
  final ContextManager contextManager;
  final LLMService llmService;
  final TTSService ttsService;

  final TurnRepository turnRepo;
  final STTInvocationRepository sttInvocationRepo;
  final LLMInvocationRepository llmInvocationRepo;
  final TTSInvocationRepository ttsInvocationRepo;

  VoiceAssistantOrchestrator({
    required this.sttService,
    required this.contextManager,
    required this.llmService,
    required this.ttsService,
    required this.turnRepo,
    required this.sttInvocationRepo,
    required this.llmInvocationRepo,
    required this.ttsInvocationRepo,
  });

  /// Process audio through the complete pipeline
  ///
  /// Handles all 5 stages: STT → CM → LLM → Tool → TTS
  /// Records invocations at each stage.
  /// Returns Turn with all invocation IDs linked.
  Future<VoiceAssistantResult> processAudio({
    required Uint8List audioBytes,
    required String correlationId,
  }) async {
    final startTime = DateTime.now();

    // Create Turn to link all invocations
    final turn = Turn(
      correlationId: correlationId,
    );

    try {
      // ====================================================================
      // STAGE 1: STT (Audio → Text)
      // ====================================================================
      String transcript = '';
      try {
        // TODO: processAudio is deprecated - use processAudioStream instead
        transcript = 'TODO: implement STT for non-streaming audio';

        // Record STT invocation
        final sttInvocation = STTInvocation(
          correlationId: correlationId,
          audioId: correlationId,
          output: transcript,
          confidence: 0.95, // Stub: would get from STT response
        );
        sttInvocation.contextType = 'conversation';

        // Save and link
        await sttInvocationRepo.save(sttInvocation);
        turn.sttInvocationId = sttInvocation.uuid;
      } catch (e) {
        turn.result = 'error';
        turn.failureComponent = 'stt';
        turn.errorMessage = 'STT failed: $e';
        await turnRepo.save(turn);
        return _errorResult(turn, 'STT transcription failed: $e', 'stt');
      }

      // ====================================================================
      // STAGE 2: ContextManager (Text → Namespace/Tools)
      // ====================================================================
      ContextManagerResult cmResult;
      try {
        final event = Event(
          correlationId: correlationId,
          source: 'user',
          payload: {'transcription': transcript},
        );
        cmResult = await contextManager.handleEvent(event);

        // Link invocation
        turn.contextManagerInvocationId = cmResult.invocationId;

        if (cmResult.hasError) {
          throw Exception('ContextManager failed: ${cmResult.error}');
        }
      } catch (e) {
        turn.result = 'error';
        turn.failureComponent = 'context_manager';
        turn.errorMessage = 'ContextManager failed: $e';
        await turnRepo.save(turn);
        return _errorResult(
          turn,
          'ContextManager failed: $e',
          'context_manager',
        );
      }

      // ====================================================================
      // STAGE 3: LLM (Context → Response + Tool Calls)
      // ====================================================================
      String llmResponse = '';
      List<MCPToolResult> toolResults = [];
      try {
        // Call LLM with tool definitions
        final llmResult = await llmService.chatWithTools(
          model: 'gpt-4', // Stub: would come from personality
          messages: [
            {
              'role': 'user',
              'content': transcript,
            }
          ],
          tools: [], // Stub: would come from ContextManager
          temperature: 0.7,
        );

        llmResponse = llmResult.content ?? 'No response';

        // Record LLM invocation
        final llmInvocation = LLMInvocation(
          correlationId: correlationId,
          systemPromptVersion: '1.0',
          conversationHistoryLength: 1,
          response: llmResponse,
          tokenCount: llmResult.tokensUsed,
        );
        llmInvocation.contextType = 'conversation';

        await llmInvocationRepo.save(llmInvocation);
        turn.llmInvocationId = llmInvocation.uuid;

        // ====================================================================
        // STAGE 4: Tool Execution (LLM calls → Tool results)
        // ====================================================================
        if (llmResult.toolCalls.isNotEmpty) {
          try {
            // TODO: Implement tool execution with MCPExecutor
            // For now, tools are handled by the LLM response itself
          } catch (e) {
            // Tools failed but LLM response still valid - log and continue
            print('Tool execution failed: $e');
          }
        }
      } catch (e) {
        turn.result =
            'partial'; // LLM worked, but response generation had issues
        turn.failureComponent = 'llm';
        turn.errorMessage = 'LLM generation failed: $e';
        llmResponse = 'I encountered an error processing your request.';
      }

      // ====================================================================
      // STAGE 5: TTS (Response → Audio)
      // ====================================================================
      Uint8List audioResponse = Uint8List(0);
      try {
        final audioStream = ttsService.synthesize(llmResponse);
        final chunks = <Uint8List>[];

        await for (final chunk in audioStream) {
          chunks.add(chunk);
        }

        // Concatenate audio chunks
        final totalLength =
            chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
        final buffer = Uint8List(totalLength);
        int offset = 0;
        for (final chunk in chunks) {
          buffer.setRange(offset, offset + chunk.length, chunk);
          offset += chunk.length;
        }
        audioResponse = buffer;

        // Record TTS invocation
        final ttsInvocation = TTSInvocation(
          correlationId: correlationId,
          text: llmResponse,
          audioId: 'response_$correlationId',
        );
        ttsInvocation.contextType = 'conversation';

        await ttsInvocationRepo.save(ttsInvocation);
        turn.ttsInvocationId = ttsInvocation.uuid;
      } catch (e) {
        // TTS failed - but we have text response
        print('TTS failed: $e');
        turn.result = 'partial';
        turn.failureComponent = 'tts';
        // Continue - user will at least see text response
      }

      // ====================================================================
      // SUCCESS: Save Turn and return result
      // ====================================================================
      turn.result = 'success';
      turn.latencyMs = DateTime.now().difference(startTime).inMilliseconds;

      // AUTO-MARK FOR FEEDBACK
      // Mark this turn so it appears in feedback review queue
      turn.markedForFeedback = true;

      await turnRepo.save(turn);

      return VoiceAssistantResult(
        turnId: turn.uuid,
        transcript: transcript,
        response: llmResponse,
        audioBytes: audioResponse,
        toolResults: toolResults,
        success: true,
        latencyMs: turn.latencyMs,
      );
    } catch (e) {
      // Catastrophic failure
      turn.result = 'error';
      turn.errorMessage = 'Orchestrator failed: $e';
      turn.latencyMs = DateTime.now().difference(startTime).inMilliseconds;
      await turnRepo.save(turn);

      return _errorResult(turn, 'Orchestrator failed: $e', 'orchestrator');
    }
  }

  /// Process audio stream with turn detection (Deepgram UtteranceEnd)
  ///
  /// Streams audio to STT which handles turn detection.
  /// When Deepgram detects silence (UtteranceEnd), processes transcript.
  ///
  /// Returns result when turn ends (no waiting for explicit stop).
  Future<VoiceAssistantResult> processAudioStream({
    required Stream<Uint8List> audioStream,
    required String correlationId,
  }) {
    final startTime = DateTime.now();
    final transcriptBuffer = StringBuffer();
    final completer = Completer<VoiceAssistantResult>();

    // Create Turn to link all invocations
    final turn = Turn(
      correlationId: correlationId,
    );

    // Start STT with turn detection
    sttService.transcribe(
      audio: audioStream,
      onTranscript: (transcript) {
        transcriptBuffer.write(transcript);
        transcriptBuffer.write(' ');
      },
      onUtteranceEnd: () async {
        // User finished speaking - process the complete transcript
        final fullTranscript = transcriptBuffer.toString().trim();

        if (fullTranscript.isEmpty) {
          completer.complete(_errorResult(turn, "Didn't hear anything", 'stt'));
          return;
        }

        try {
          // Record STT invocation
          final sttInvocation = STTInvocation(
            correlationId: correlationId,
            audioId: correlationId,
            output: fullTranscript,
            confidence: 0.95,
          );
          sttInvocation.contextType = 'conversation';

          await sttInvocationRepo.save(sttInvocation);
          turn.sttInvocationId = sttInvocation.uuid;

          // ====================================================================
          // STAGE 2: ContextManager (Text → Namespace/Tools)
          // ====================================================================
          ContextManagerResult cmResult;
          try {
            final event = Event(
              correlationId: correlationId,
              source: 'user',
              payload: {'transcription': fullTranscript},
            );
            cmResult = await contextManager.handleEvent(event);

            turn.contextManagerInvocationId = cmResult.invocationId;

            if (cmResult.hasError) {
              throw Exception('ContextManager failed: ${cmResult.error}');
            }
          } catch (e) {
            turn.result = 'error';
            turn.failureComponent = 'context_manager';
            turn.errorMessage = 'ContextManager failed: $e';
            await turnRepo.save(turn);
            completer.complete(_errorResult(
              turn,
              'ContextManager failed: $e',
              'context_manager',
            ));
            return;
          }

          // ====================================================================
          // STAGE 3: LLM (Context → Response + Tool Calls)
          // ====================================================================
          String llmResponse = '';
          List<MCPToolResult> toolResults = [];
          try {
            final llmResult = await llmService.chatWithTools(
              model: 'gpt-4',
              messages: [
                {
                  'role': 'user',
                  'content': fullTranscript,
                }
              ],
              tools: [],
              temperature: 0.7,
            );

            llmResponse = llmResult.content ?? 'No response';

            // Record LLM invocation
            final llmInvocation = LLMInvocation(
              correlationId: correlationId,
              systemPromptVersion: '1.0',
              conversationHistoryLength: 1,
              response: llmResponse,
              tokenCount: llmResult.tokensUsed,
            );
            llmInvocation.contextType = 'conversation';

            await llmInvocationRepo.save(llmInvocation);
            turn.llmInvocationId = llmInvocation.uuid;

            // ====================================================================
            // STAGE 4: Tool Execution (LLM calls → Tool results)
            // ====================================================================
            if (llmResult.toolCalls.isNotEmpty) {
              try {
                // TODO: Implement tool execution with MCPExecutor
                // For now, tools are handled by the LLM response itself
              } catch (e) {
                print('Tool execution failed: $e');
              }
            }
          } catch (e) {
            turn.result = 'partial';
            turn.failureComponent = 'llm';
            turn.errorMessage = 'LLM generation failed: $e';
            llmResponse = 'I encountered an error processing your request.';
          }

          // ====================================================================
          // STAGE 5: TTS (Response → Audio)
          // ====================================================================
          Uint8List audioResponse = Uint8List(0);
          try {
            final audioStreamResult = ttsService.synthesize(llmResponse);
            final chunks = <Uint8List>[];

            await for (final chunk in audioStreamResult) {
              chunks.add(chunk);
            }

            final totalLength =
                chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
            final buffer = Uint8List(totalLength);
            int offset = 0;
            for (final chunk in chunks) {
              buffer.setRange(offset, offset + chunk.length, chunk);
              offset += chunk.length;
            }
            audioResponse = buffer;

            // Record TTS invocation
            final ttsInvocation = TTSInvocation(
              correlationId: correlationId,
              text: llmResponse,
              audioId: 'response_$correlationId',
            );
            ttsInvocation.contextType = 'conversation';

            await ttsInvocationRepo.save(ttsInvocation);
            turn.ttsInvocationId = ttsInvocation.uuid;
          } catch (e) {
            print('TTS failed: $e');
            turn.result = 'partial';
            turn.failureComponent = 'tts';
          }

          // ====================================================================
          // SUCCESS: Save Turn and return result
          // ====================================================================
          turn.result = 'success';
          turn.latencyMs = DateTime.now().difference(startTime).inMilliseconds;

          // AUTO-MARK FOR FEEDBACK
          // Mark this turn so it appears in feedback review queue
          turn.markedForFeedback = true;

          await turnRepo.save(turn);

          completer.complete(VoiceAssistantResult(
            turnId: turn.uuid,
            transcript: fullTranscript,
            response: llmResponse,
            audioBytes: audioResponse,
            toolResults: toolResults,
            success: true,
            latencyMs: turn.latencyMs,
          ));
        } catch (e) {
          turn.result = 'error';
          turn.errorMessage = 'Orchestrator failed: $e';
          turn.latencyMs = DateTime.now().difference(startTime).inMilliseconds;
          await turnRepo.save(turn);

          completer.complete(
              _errorResult(turn, 'Orchestrator failed: $e', 'orchestrator'));
        }
      },
      onError: (error) {
        turn.result = 'error';
        turn.failureComponent = 'stt';
        turn.errorMessage = 'STT failed: $error';
        turn.latencyMs = DateTime.now().difference(startTime).inMilliseconds;
        turnRepo.save(turn).then((_) {
          completer.complete(_errorResult(turn, 'STT failed: $error', 'stt'));
        });
      },
    );

    return completer.future;
  }

  /// Helper to create error result
  VoiceAssistantResult _errorResult(
    Turn turn,
    String message,
    String component,
  ) {
    return VoiceAssistantResult(
      turnId: turn.uuid,
      transcript: 'ERROR',
      response: message,
      audioBytes: Uint8List(0),
      toolResults: [],
      success: false,
      errorMessage: message,
      failureComponent: component,
      latencyMs: turn.latencyMs,
    );
  }
}

/// Result of MCPExecutor tool execution
class MCPToolResult {
  final String toolName;
  final bool success;
  final dynamic result;

  MCPToolResult({
    required this.toolName,
    required this.success,
    required this.result,
  });
}
