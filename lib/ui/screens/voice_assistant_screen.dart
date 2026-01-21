/// # Voice Assistant Screen (v2 - Two-Panel Layout)
///
/// Responsive two-panel UI:
/// - Left panel: Context selection display
/// - Right panel: Chat conversation
///
/// Layout:
/// - Mobile (< 600px): Vertical stack (50% each)
/// - Desktop (>= 600px): Horizontal split (50% each)

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/services/event_bus.dart';
import 'package:everything_stack_template/services/context_selector.dart';
import 'package:everything_stack_template/services/inference_service.dart';
import 'package:everything_stack_template/services/stt_service.dart';
import 'package:everything_stack_template/services/audio_recording_service.dart';
import 'package:everything_stack_template/services/audio_storage.dart';
import 'package:everything_stack_template/core/event.dart';
import 'package:everything_stack_template/core/invocation.dart';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/domain/feedback.dart' as domain_feedback;
import 'package:everything_stack_template/core/feedback_repository.dart';
import 'package:everything_stack_template/services/types/context_selector_types.dart';
import '../widgets/context_panel.dart';
import '../widgets/chat_panel.dart';

class VoiceAssistantScreen extends StatefulWidget {
  const VoiceAssistantScreen({Key? key}) : super(key: key);

  @override
  State<VoiceAssistantScreen> createState() => _VoiceAssistantScreenState();
}

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen> {
  late EventBus _eventBus;
  late InvocationRepository<Invocation> _invocationRepo;
  late FeedbackRepository _feedbackRepo;
  late ContextSelector _contextSelector;
  late InferenceService _inferenceService;
  late STTService _sttService;
  late AudioStorage _audioStorage;

  // UI state
  List<ChatMessage> _messages = [];
  ContextBundle? _currentContextBundle;
  bool _contextFeedbackGiven = false;
  bool _isListening = false;
  String _liveTranscript = '';  // Real-time partial transcription

  // Audio recording state
  StreamSubscription<Uint8List>? _audioStreamSubscription;
  final List<int> _audioBuffer = [];
  DateTime? _recordingStartTime;

  // StreamSubscription
  StreamSubscription<Event>? _eventSubscription;

  @override
  void initState() {
    super.initState();

    // Get services from GetIt
    _eventBus = GetIt.instance<EventBus>();
    _invocationRepo = GetIt.instance<InvocationRepository<Invocation>>();
    _feedbackRepo = GetIt.instance<FeedbackRepository>();
    _contextSelector = GetIt.instance<ContextSelector>();
    _inferenceService = GetIt.instance<InferenceService>();
    _sttService = GetIt.instance<STTService>();
    _audioStorage = GetIt.instance<AudioStorage>();

    // Subscribe to events
    _subscribeToEvents();

    debugPrint('✅ [VoiceAssistantScreen] Initialized');
  }

  void _subscribeToEvents() {
    _eventSubscription = _eventBus.subscribe().listen(
      (event) {
        if (!mounted) return;

        debugPrint('📡 [Event] ${event.eventType}');

        // Live transcription (partial) → update live display
        if (event.eventType == 'transcription_partial') {
          final payload = jsonDecode(event.payloadJson ?? '{}');
          final transcript = payload['transcript'] as String? ?? '';
          setState(() {
            _liveTranscript = transcript;
          });
          return;  // Don't process further
        }

        // Transcription complete → add user message, clear live display
        if (event.eventType == 'transcription_complete') {
          setState(() {
            _liveTranscript = '';  // Clear live display
          });
          final utterance = event.toInputString();
          if (utterance.isNotEmpty) {
            setState(() {
              _messages.add(ChatMessage(
                id: '${event.uuid}_user',
                role: 'user',
                content: utterance,
                timestamp: DateTime.now(),
              ));
            });

            // Load context bundle for this turn
            _loadContextBundle(event.uuid);
          }
        }

        // Orchestration complete → add assistant message
        if (event.eventType == 'orchestration_complete') {
          final response = event.getDisplayString();
          if (response.isNotEmpty) {
            setState(() {
              _messages.add(ChatMessage(
                id: event.uuid, // Use eventId as messageId
                role: 'assistant',
                content: response,
                timestamp: DateTime.now(),
              ));
              _contextFeedbackGiven = false; // Reset for new turn
            });
          }
        }

        // Tool call executed → add tool call message
        if (event.eventType == 'tool_call_executed') {
          try {
            final payload = jsonDecode(event.payloadJson ?? '{}') as Map<String, dynamic>;
            setState(() {
              _messages.add(ChatMessage(
                id: '${event.uuid}_tool',
                role: 'tool',
                content: '',
                timestamp: DateTime.now(),
                toolName: payload['tool_name'] as String?,
                toolSuccess: payload['success'] as bool?,
                toolResult: payload['result'] as Map<String, dynamic>?,
                toolError: payload['error'] as String?,
              ));
            });
          } catch (e) {
            debugPrint('❌ [tool_call_executed] Failed to parse payload: $e');
          }
        }
      },
    );
  }

  /// Load the context bundle that was selected for this turn
  Future<void> _loadContextBundle(String eventId) async {
    try {
      // Find the context_selector invocation for this event
      final invocations = await _invocationRepo.findAll();
      final contextInvocation = invocations.firstWhere(
        (inv) => inv.eventId == eventId && inv.componentType == 'context_selector',
        orElse: () => throw Exception('Context invocation not found'),
      );

      // Reconstruct ContextBundle from invocation metadata
      // TODO: Store full bundle in metadata for exact reconstruction
      // For now, create a minimal bundle for display
      final bundle = ContextBundle(
        conversationThread: [], // Would load from metadata
        semanticContext: [], // Would load from metadata
        params: ContextSelectorAdaptationData.defaults(),
      );

      setState(() {
        _currentContextBundle = bundle;
      });
    } catch (e) {
      debugPrint('❌ [loadContextBundle] Error: $e');
    }
  }

  /// Handle context feedback (async, fire-and-forget)
  Future<void> _handleContextFeedback(bool isPositive) async {
    if (_contextFeedbackGiven || _currentContextBundle == null) return;

    setState(() => _contextFeedbackGiven = true);

    try {
      // Find most recent context_selector invocation
      final invocations = await _invocationRepo.findAll();
      final contextInvocation = invocations
          .where((inv) => inv.componentType == 'context_selector')
          .reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);

      // Create feedback
      final feedback = domain_feedback.Feedback(
        invocationId: contextInvocation.uuid,
        componentType: 'context_selector',
        action: isPositive
            ? domain_feedback.FeedbackAction.confirm
            : domain_feedback.FeedbackAction.deny,
      );

      await _feedbackRepo.save(feedback);

      // Fire-and-forget training (async, no blocking)
      unawaited(
        _contextSelector.trainFromFeedback(contextInvocation, feedback).catchError((e) {
          debugPrint('❌ [Training] Context training error: $e');
        }),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isPositive
                ? '👍 Context feedback recorded'
                : '👎 Context feedback recorded'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ [handleContextFeedback] Error: $e');
    }
  }

  /// Handle message feedback (async, fire-and-forget)
  Future<void> _handleMessageFeedback(String messageId, bool isPositive) async {
    try {
      // Find LLM invocation for this message
      final invocations = await _invocationRepo.findAll();
      final llmInvocation = invocations.firstWhere(
        (inv) => inv.eventId == messageId && inv.componentType == 'llm',
        orElse: () => throw Exception('LLM invocation not found for message: $messageId'),
      );

      // Create feedback
      final feedback = domain_feedback.Feedback(
        invocationId: llmInvocation.uuid,
        componentType: 'llm',
        action: isPositive
            ? domain_feedback.FeedbackAction.confirm
            : domain_feedback.FeedbackAction.deny,
      );

      await _feedbackRepo.save(feedback);

      // Fire-and-forget training (async, no blocking)
      unawaited(
        _inferenceService.trainFromFeedback(llmInvocation, feedback).catchError((e) {
          debugPrint('❌ [Training] Inference training error: $e');
        }),
      );

      // Update message to show feedback given
      setState(() {
        final index = _messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(feedbackGiven: true);
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isPositive
                ? '👍 Response feedback recorded'
                : '👎 Response feedback recorded'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ [handleMessageFeedback] Error: $e');
    }
  }

  void _toggleListening() async {
    if (!_isListening) {
      // Start recording
      try {
        debugPrint('🎤 Starting audio recording...');
        setState(() => _isListening = true);

        // Clear buffer
        _audioBuffer.clear();
        _recordingStartTime = DateTime.now();

        // Start recording stream
        final audioStream = AudioRecordingService.instance.startRecording();
        _audioStreamSubscription = audioStream.listen(
          (chunk) {
            _audioBuffer.addAll(chunk);
            debugPrint('   📊 Audio chunk received: ${chunk.length} bytes');
          },
          onError: (error) {
            debugPrint('❌ Audio recording error: $error');
            setState(() => _isListening = false);
          },
          onDone: () {
            debugPrint('   ✅ Audio stream closed');
          },
        );
      } catch (e) {
        debugPrint('❌ Failed to start recording: $e');
        setState(() => _isListening = false);
      }
    } else {
      // Stop recording and process
      try {
        debugPrint('⏹️  Stopping audio recording...');
        setState(() => _isListening = false);

        // Stop recording
        await AudioRecordingService.instance.stopRecording();
        await _audioStreamSubscription?.cancel();
        _audioStreamSubscription = null;

        // Calculate duration
        final duration = DateTime.now().difference(_recordingStartTime!).inMilliseconds / 1000.0;
        debugPrint('   📏 Recording duration: ${duration}s');
        debugPrint('   📦 Total bytes captured: ${_audioBuffer.length}');

        if (_audioBuffer.isEmpty) {
          debugPrint('⚠️  No audio data captured');
          return;
        }

        // Save audio to storage
        final audioBytes = Uint8List.fromList(_audioBuffer);
        final eventId = 'turn_${DateTime.now().millisecondsSinceEpoch}';
        final audioId = await _audioStorage.saveAudio(
          audioBytes: audioBytes,
          durationSeconds: duration,
          eventId: eventId,
        );
        debugPrint('   💾 Audio saved with ID: $audioId');

        // Transcribe using STT service
        // Note: STTService now publishes transcription_complete event itself (service owns domain events)
        debugPrint('   🎤 Calling STT service...');
        final transcription = await _sttService.recognize(
          eventId: eventId,
          audioId: audioId,
          durationSeconds: duration,
        );
        debugPrint('   📝 Transcription: "$transcription"');
      } catch (e, st) {
        debugPrint('❌ Failed to process recording: $e');
        debugPrint('   Stack trace: $st');
      }
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _audioStreamSubscription?.cancel();
    super.dispose();
  }

  /// Build chat panel with live transcription indicator below it.
  Widget _buildChatWithLiveTranscript() {
    return Column(
      children: [
        // Chat panel (expanded to fill available space)
        Expanded(
          child: ChatPanel(
            messages: _messages,
            onMessageFeedback: _handleMessageFeedback,
            onMicrophonePressed: _toggleListening,
            isListening: _isListening,
          ),
        ),

        // Live transcription indicator (appears below chat)
        if (_liveTranscript.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(
                top: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Row(
              children: [
                // Animated typing indicator
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[600]!),
                  ),
                ),
                const SizedBox(width: 8),
                // Live transcript text
                Expanded(
                  child: Text(
                    _liveTranscript,
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey[700],
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Assistant'),
        centerTitle: true,
        actions: [
          // Clear button
          if (_messages.isNotEmpty)
            IconButton(
              onPressed: () {
                setState(() {
                  _messages.clear();
                  _currentContextBundle = null;
                  _contextFeedbackGiven = false;
                });
              },
              icon: const Icon(Icons.refresh),
              tooltip: 'Clear conversation',
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: isMobile
            ? _buildMobileLayout()
            : _buildDesktopLayout(),
      ),
    );
  }

  /// Mobile: Vertical stack (50% height each)
  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Context panel (top 50%)
        Expanded(
          flex: 50,
          child: ContextPanel(
            contextBundle: _currentContextBundle,
            feedbackGiven: _contextFeedbackGiven,
            onFeedback: _handleContextFeedback,
          ),
        ),

        const SizedBox(height: 16),

        // Chat panel (bottom 50%)
        Expanded(
          flex: 50,
          child: _buildChatWithLiveTranscript(),
        ),
      ],
    );
  }

  /// Desktop: Side-by-side (50% width each)
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Context panel (left 50%)
        Expanded(
          flex: 50,
          child: ContextPanel(
            contextBundle: _currentContextBundle,
            feedbackGiven: _contextFeedbackGiven,
            onFeedback: _handleContextFeedback,
          ),
        ),

        const SizedBox(width: 16),

        // Chat panel (right 50%)
        Expanded(
          flex: 50,
          child: _buildChatWithLiveTranscript(),
        ),
      ],
    );
  }
}
