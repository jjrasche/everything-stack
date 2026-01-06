import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/services/stt_service.dart';
import 'package:everything_stack_template/services/audio_recording_service.dart';
import 'package:everything_stack_template/services/event_bus.dart';
import 'package:everything_stack_template/core/event.dart';

/// Voice Assistant Screen
///
/// PASSIVE OBSERVER - displays state from events, never calls orchestrate().
///
/// ## What it does:
/// - Start/Stop button controls STT listening
/// - Displays interim transcription (left side - what user is saying)
/// - Displays LLM response (right side - AI response)
///
/// ## Event Flow:
/// 1. User presses Start → STT begins listening
/// 2. STT interim callbacks → update interim text display
/// 3. STT detects utterance end → publishes Event(eventType: transcription_complete)
/// 4. Coordinator receives event → LLM → TTS → publishes Event(eventType: orchestration_complete)
/// 5. Screen receives orchestration_complete event → displays response
/// 6. STT continues listening for next turn (even during TTS)
class VoiceAssistantScreen extends StatefulWidget {
  const VoiceAssistantScreen({Key? key}) : super(key: key);

  @override
  State<VoiceAssistantScreen> createState() => _VoiceAssistantScreenState();
}

// Conversation session states
enum ConversationState {
  idle, // Not in conversation
  listening, // Capturing user speech
  thinking, // Processing with LLM (after utterance end, before response)
  speaking, // Playing TTS response
}

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen> {
  // TODO: Restore STT/Audio service integration when services are fully implemented
  // late EventBus _eventBus;
  // late STTService _sttService;
  // late AudioRecordingService _audioService;

  String _interimText = ''; // Gray, updating text (what user is currently saying)
  String _finalText = ''; // Black, locked text (last complete utterance)
  String _responseText = ''; // AI response
  ConversationState _conversationState = ConversationState.idle;

  // StreamSubscription<String>? _sttSubscription;
  // StreamSubscription<Event>? _eventSubscription;
  // Timer? _sessionIdleTimer;

  static const int SESSION_TIMEOUT_MS = 30000;

  @override
  void initState() {
    super.initState();

    // TODO: Restore service initialization when STTService, AudioRecordingService, and EventBus are fully implemented
    // Get services from GetIt
    // debugPrint('🔍 [initState] Getting services from GetIt...');
    // _eventBus = GetIt.instance<EventBus>();
    // _sttService = GetIt.instance<STTService>();
    // _audioService = GetIt.instance<AudioRecordingService>();
    //
    // // Subscribe to OrchestrationComplete events
    // _subscribeToEvents();
    //
    // debugPrint('✅ [initState] Services initialized, event subscriptions active');
  }

  /// Subscribe to events from EventBus
  // TODO: Restore when EventBus and services are implemented
  // void _subscribeToEvents() {
  //   debugPrint('📡 [_subscribeToEvents] Subscribing to orchestration_complete events...');
  //
  //   _eventSubscription = _eventBus.subscribe().listen(
  //     (event) {
  //       // Filter for orchestration_complete events
  //       if (event.eventType != 'orchestration_complete') {
  //         return;
  //       }
  //
  //       try {
  //         // Format event for display
  //         final displayText = event.getDisplayString();
  //
  //         debugPrint('📡 [Event] orchestration_complete received');
  //         debugPrint('   Response: "$displayText"');
  //
  //         if (mounted) {
  //           setState(() {
  //             _responseText = displayText;
  //             // TTS is playing, but STT continues listening
  //             // State goes back to listening (STT never stopped)
  //             _conversationState = ConversationState.listening;
  //           });
  //         }
  //
  //         // Reset idle timer since we got a response
  //         _resetSessionIdleTimer();
  //       } catch (e) {
  //         debugPrint('❌ [Event] Error handling orchestration_complete: $e');
  //       }
  //     },
  //     onError: (error) {
  //       debugPrint('❌ [Event] orchestration_complete subscription error: $error');
  //     },
  //   );
  //
  //   debugPrint('✅ [_subscribeToEvents] Event subscriptions active');
  // }

  /// Start conversation session (continuous listening)
  // TODO: Restore when STT, Audio, and EventBus services are implemented
  Future<void> _startConversation() async {
    debugPrint('⚠️ Voice assistant disabled - services not yet implemented');
    // if (_conversationState != ConversationState.idle) return;
    //
    // debugPrint('🎤 [_startConversation] Starting conversation session...');
    //
    // // Request microphone permission
    // try {
    //   final hasPermission = await _audioService.requestPermission();
    //   if (!hasPermission) {
    //     debugPrint('❌ Microphone permission denied');
    //     if (mounted) {
    //       ScaffoldMessenger.of(context).showSnackBar(
    //         const SnackBar(content: Text('Microphone permission required')),
    //       );
    //     }
    //     return;
    //   }
    // } catch (e) {
    //   debugPrint('⚠️ Permission error: $e');
    //   if (mounted) {
    //     ScaffoldMessenger.of(context).showSnackBar(
    //       SnackBar(content: Text('Permission error: $e')),
    //     );
    //   }
    //   return;
    // }
    //
    // setState(() {
    //   _conversationState = ConversationState.listening;
    //   _interimText = '';
    //   _finalText = '';
    //   _responseText = '';
    // });
    //
    // _startSessionIdleTimer();
    // await _startListening();
  }

  /// Start STT listening
  ///
  /// STT runs continuously until session ends.
  /// When utterance ends, STT publishes Event(eventType: transcription_complete).
  /// Coordinator handles the event → LLM → TTS.
  /// STT keeps listening for next utterance (even during TTS).
  // TODO: Restore when STT and Audio services are implemented
  // Future<void> _startListening() async {
  //   if (_conversationState == ConversationState.idle) {
  //     debugPrint('Session ended, not starting STT');
  //     return;
  //   }
  //
  //   debugPrint('🎤 [_startListening] Starting continuous STT...');
  //
  //   try {
  //     // Get audio stream from microphone
  //     final audioStream = _audioService.startRecording();
  //
  //     // Pass audio to STT service
  //     // STT will publish Event(eventType: transcription_complete) when utterance ends
  //     _sttSubscription = _sttService.transcribe(
  //       audio: audioStream,
  //       onTranscript: (transcript) {
  //         // Interim transcript - update display
  //         debugPrint('📝 [STT] Interim: "$transcript"');
  //         if (mounted) {
  //           setState(() => _interimText = transcript);
  //         }
  //         // Reset idle timer on speech activity
  //         _resetSessionIdleTimer();
  //       },
  //       onUtteranceEnd: () {
  //         // Utterance complete - lock text, show thinking state
  //         debugPrint('✅ [STT] Utterance ended');
  //         if (mounted) {
  //           setState(() {
  //             _finalText = _interimText;
  //             _interimText = '';
  //             _conversationState = ConversationState.thinking;
  //           });
  //         }
  //         // NOTE: STT publishes Event(eventType: transcription_complete) internally
  //         // Coordinator receives it via EventBus and handles orchestration
  //         // STT continues listening for next utterance
  //       },
  //       onError: (error) {
  //         debugPrint('❌ [STT] Error: $error');
  //         if (mounted) {
  //           ScaffoldMessenger.of(context).showSnackBar(
  //             SnackBar(content: Text('STT error: $error')),
  //           );
  //         }
  //       },
  //       onDone: () {
  //         debugPrint('🏁 [STT] Stream closed');
  //         // STT stream closed - restart if still in conversation
  //         if (_conversationState != ConversationState.idle && mounted) {
  //           debugPrint('↻ [STT] Restarting listening...');
  //           _startListening();
  //         }
  //       },
  //     );
  //
  //     debugPrint('✅ [_startListening] STT active');
  //   } catch (e) {
  //     debugPrint('❌ Error starting STT: $e');
  //     if (mounted) {
  //       setState(() => _conversationState = ConversationState.idle);
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(content: Text('Error: $e')),
  //       );
  //     }
  //     _cancelSessionIdleTimer();
  //   }
  // }

  /// Stop the entire conversation session
  // TODO: Restore when services are implemented
  Future<void> _stopConversation() async {
    debugPrint('⚠️ Stop conversation - services not yet implemented');
    // debugPrint('⏹️ [_stopConversation] Stopping conversation...');
    //
    // _cancelSessionIdleTimer();
    //
    // // Stop STT
    // await _sttSubscription?.cancel();
    // _sttSubscription = null;
    //
    // // Stop audio recording
    // await _audioService.stopRecording();
    //
    // setState(() {
    //   _conversationState = ConversationState.idle;
    //   _interimText = '';
    // });
    //
    // debugPrint('✅ [_stopConversation] Conversation stopped');
  }

  /// Session idle timer - 30 seconds of silence closes conversation
  // TODO: Restore when services are implemented
  // void _startSessionIdleTimer() {
  //   _sessionIdleTimer = Timer(
  //     const Duration(milliseconds: SESSION_TIMEOUT_MS),
  //     () {
  //       debugPrint('⏲️ [Session Timeout] 30 seconds idle - ending conversation');
  //       _stopConversation();
  //       if (mounted) {
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           const SnackBar(content: Text('Session ended due to 30 seconds of silence')),
  //         );
  //       }
  //     },
  //   );
  // }
  //
  // void _resetSessionIdleTimer() {
  //   _cancelSessionIdleTimer();
  //   _startSessionIdleTimer();
  // }
  //
  // void _cancelSessionIdleTimer() {
  //   _sessionIdleTimer?.cancel();
  //   _sessionIdleTimer = null;
  // }

  @override
  void dispose() {
    debugPrint('🧹 [dispose] Cleaning up VoiceAssistantScreen...');
    // TODO: Restore cleanup when services are implemented
    // _cancelSessionIdleTimer();
    // _sttSubscription?.cancel();
    // _eventSubscription?.cancel();
    // _audioService.stopRecording();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Assistant'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Listening indicator
                if (_conversationState == ConversationState.listening)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Listening...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox(height: 56),

                const SizedBox(height: 24),

                // Final (locked) transcription - what user said
                if (_finalText.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'You said:',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _finalText,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),

                // Interim (updating) transcription - what user is currently saying
                if (_interimText.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _interimText,
                          style: TextStyle(
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),

                // Processing indicator
                if (_conversationState == ConversationState.thinking)
                  const Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Processing...'),
                    ],
                  )
                else
                  const SizedBox.shrink(),

                // AI Response
                if (_responseText.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'AI Response:',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _responseText,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // Start/Stop conversation button
                FloatingActionButton.extended(
                  onPressed: _conversationState == ConversationState.idle
                      ? _startConversation
                      : _stopConversation,
                  label: Text(_conversationState == ConversationState.idle
                      ? '🎤 Start Conversation'
                      : '⏹️ Stop'),
                  icon: Icon(_conversationState == ConversationState.idle
                      ? Icons.mic
                      : Icons.stop),
                  backgroundColor: _conversationState == ConversationState.idle
                      ? Colors.blue
                      : Colors.red,
                ),

                const SizedBox(height: 16),

                // Clear button
                if (_responseText.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _interimText = '';
                        _finalText = '';
                        _responseText = '';
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Clear'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
