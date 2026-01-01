import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/services/coordinator.dart';
import 'package:everything_stack_template/services/tts_service.dart';
import 'package:everything_stack_template/services/stt_service.dart';
import 'package:everything_stack_template/services/audio_recording_service.dart';

/// Voice Assistant Screen
///
/// UI for voice input/output interaction:
/// 1. User speaks
/// 2. STT converts speech to text
/// 3. Coordinator processes text with LLM
/// 4. TTS speaks response
class VoiceAssistantScreen extends StatefulWidget {
  const VoiceAssistantScreen({Key? key}) : super(key: key);

  @override
  State<VoiceAssistantScreen> createState() => _VoiceAssistantScreenState();
}

// Conversation session states
enum ConversationState {
  idle,        // Not in conversation
  listening,   // Capturing user speech
  thinking,    // Processing with LLM
  speaking,    // Playing TTS response
}

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen> {
  late Coordinator _coordinator;
  late TTSService _ttsService;
  late STTService _sttService;
  late AudioRecordingService _audioService;

  String _recognizedText = '';
  String _responseText = '';
  ConversationState _conversationState = ConversationState.idle;

  StreamSubscription<String>? _sttSubscription;
  Timer? _sessionIdleTimer;

  static const int SESSION_TIMEOUT_MS = 30000;

  @override
  void initState() {
    super.initState();

    // Get services from GetIt/singletons
    debugPrint('🔍 [initState] Getting Coordinator from GetIt...');
    try {
      _coordinator = GetIt.instance<Coordinator>();
      debugPrint('✅ [initState] Coordinator successfully retrieved');
    } catch (e) {
      debugPrint('❌ [initState] FAILED TO GET COORDINATOR: $e');
      debugPrint('This error means setupServiceLocator() was not called or failed in main()');
      rethrow;
    }
    _ttsService = TTSService.instance;
    _sttService = STTService.instance;
    _audioService = AudioRecordingService.instance;

    debugPrint('✅ [initState] All services initialized');
    debugPrint('  - Coordinator: OK');
    debugPrint('  - TTS: ${_ttsService.isReady ? "ready" : "not ready"}');
    debugPrint('  - STT: ${_sttService.isReady ? "ready" : "not ready"}');
    debugPrint('  - Audio: initialized');
  }

  /// Start conversation session (continuous listening)
  Future<void> _startConversation() async {
    if (_conversationState != ConversationState.idle) return;

    debugPrint(
        '🎤 [_startConversation] Starting conversation session...');

    // Request microphone permission
    try {
      final hasPermission = await _audioService.requestPermission();
      if (!hasPermission) {
        debugPrint('❌ Microphone permission denied');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission required')),
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('⚠️ Permission error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Permission error: $e')),
        );
      }
      return;
    }

    setState(() {
      _conversationState = ConversationState.listening;
      _recognizedText = '';
      _responseText = '';
    });

    _startSessionIdleTimer();
    await _startListeningPhase();
  }

  /// Start a listening phase (can be called multiple times in a session)
  Future<void> _startListeningPhase() async {
    if (_conversationState == ConversationState.idle) {
      debugPrint('Session ended, not starting new listening phase');
      return;
    }

    debugPrint('🎤 [_startListeningPhase] Getting audio stream...');

    try {
      // Get audio stream from microphone
      final audioStream = _audioService.startRecording();

      debugPrint('🎤 [_startListeningPhase] Starting STT transcription...');

      if (mounted) {
        setState(() => _conversationState = ConversationState.listening);
      }

      // Pass audio to STT service
      _sttSubscription = _sttService.transcribe(
        audio: audioStream,
        onTranscript: (transcript) {
          debugPrint('📝 [STT] Interim transcript: "$transcript"');
          if (mounted) {
            setState(() => _recognizedText = transcript);
          }
          // Reset idle timer on new speech
          _resetSessionIdleTimer();
        },
        onUtteranceEnd: () {
          debugPrint('✅ [STT] Utterance ended - user stopped talking');
          // Don't stop listening, instead process this utterance
          if (_conversationState == ConversationState.listening &&
              _recognizedText.isNotEmpty) {
            _processUtterance(_recognizedText);
          }
        },
        onError: (error) {
          debugPrint('❌ [STT] Error: $error');
          if (mounted) {
            setState(() => _conversationState = ConversationState.idle);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('STT error: $error')),
            );
          }
          _cancelSessionIdleTimer();
        },
        onDone: () {
          debugPrint('🏁 [STT] Transcription stream closed');
          // If we're still in conversation, this might be an error
          if (_conversationState != ConversationState.idle) {
            debugPrint('⚠️ STT stream closed unexpectedly during conversation');
          }
        },
      );

      debugPrint('✅ [_startListeningPhase] Listening phase started');
    } catch (e) {
      debugPrint('❌ Error in listening phase: $e');
      if (mounted) {
        setState(() => _conversationState = ConversationState.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      _cancelSessionIdleTimer();
    }
  }

  /// Process one utterance and generate response (stays in conversation)
  Future<void> _processUtterance(String text) async {
    if (_conversationState != ConversationState.listening) return;

    debugPrint('💬 [_processUtterance] Processing: "$text"');

    // Stop STT and pause listening
    await _sttSubscription?.cancel();
    _sttSubscription = null;
    await _audioService.stopRecording();

    // Move to thinking state
    setState(() => _conversationState = ConversationState.thinking);

    await _processRecognizedText(text);

    // After processing, speak response
    if (_responseText.isNotEmpty) {
      setState(() => _conversationState = ConversationState.speaking);
      await _speakResponse(_responseText);
    }

    // After speaking, go back to listening (not idle!)
    setState(() => _conversationState = ConversationState.listening);
    debugPrint('↻ [_processUtterance] Returning to listening phase...');

    // Resume listening for next turn
    await _startListeningPhase();
  }

  /// Stop the entire conversation session
  Future<void> _endConversation() async {
    debugPrint('⏹️ [_endConversation] Ending conversation session...');

    _cancelSessionIdleTimer();

    // Stop STT
    await _sttSubscription?.cancel();
    _sttSubscription = null;

    // Stop audio recording
    await _audioService.stopRecording();

    setState(() => _conversationState = ConversationState.idle);

    debugPrint('✅ [_endConversation] Conversation ended');
  }

  /// Session idle timer - 30 seconds of silence closes conversation
  void _startSessionIdleTimer() {
    _sessionIdleTimer = Timer(const Duration(milliseconds: SESSION_TIMEOUT_MS),
        () {
      debugPrint(
          '⏲️ [Session Timeout] 30 seconds of idle time - ending conversation');
      _endConversation();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Session ended due to 30 seconds of silence')),
        );
      }
    });
  }

  void _resetSessionIdleTimer() {
    _cancelSessionIdleTimer();
    _startSessionIdleTimer();
  }

  void _cancelSessionIdleTimer() {
    _sessionIdleTimer?.cancel();
    _sessionIdleTimer = null;
  }

  /// Process recognized text through Coordinator
  Future<void> _processRecognizedText(String text) async {
    debugPrint('\n=== VOICE ASSISTANT: _processRecognizedText START ===');
    debugPrint('📥 Input text: "$text"');

    if (text.isEmpty) {
      debugPrint('❌ Text is empty, returning');
      return;
    }

    try {
      final correlationId = '${DateTime.now().millisecondsSinceEpoch}';
      debugPrint('🔗 Correlation ID: $correlationId');
      debugPrint('📞 Calling coordinator.orchestrate()...');

      final result = await _coordinator.orchestrate(
        correlationId: correlationId,
        utterance: text,
        availableNamespaces: ['general'],
        toolsByNamespace: {
          'general': [],
        },
      );

      debugPrint('✅ Coordinator returned!');
      debugPrint('📊 Result: success=${result.success}, finalResponse="${result.finalResponse}"');
      debugPrint('⏱️ Latency: ${result.latencyMs}ms');

      if (!result.success) {
        debugPrint('❌ Coordinator failed: ${result.errorMessage}');
      }

      if (mounted) {
        debugPrint('📱 Widget mounted, updating UI...');
        setState(() {
          _responseText = result.finalResponse;
        });
        debugPrint('💬 Updated response text: "${result.finalResponse}"');

        // Speak the response
        if (result.finalResponse.isNotEmpty) {
          debugPrint('🔊 Calling _speakResponse()...');
          await _speakResponse(result.finalResponse);
          debugPrint('✅ TTS complete');
        } else {
          debugPrint('⚠️ No response text to speak');
        }
      } else {
        debugPrint('⚠️ Widget not mounted, skipping UI update');
      }

      debugPrint('=== VOICE ASSISTANT: _processRecognizedText END (success) ===\n');
    } catch (e) {
      debugPrint('❌ EXCEPTION in _processRecognizedText: $e');
      debugPrint('Stack trace: ${StackTrace.current}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      debugPrint('=== VOICE ASSISTANT: _processRecognizedText END (error) ===\n');
    }
  }

  /// Speak the response using TTS
  Future<void> _speakResponse(String text) async {
    if (text.isEmpty) return;

    try {
      await for (final _ in _ttsService.synthesize(text)) {
        // Stream completes when speech is done
      }
    } catch (e) {
      debugPrint('TTS error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('TTS error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    debugPrint('🧹 [dispose] Cleaning up VoiceAssistantScreen...');
    _cancelSessionIdleTimer();
    _sttSubscription?.cancel();
    _audioService.stopRecording();
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
                  const SizedBox(height: 56), // Placeholder when not listening

                const SizedBox(height: 24),

                // Recognized text
                if (_recognizedText.isNotEmpty) ...[
                  Text(
                    'You said:',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _recognizedText,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

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

                // LLM Response
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
                  const SizedBox(height: 24),
                  if (_conversationState == ConversationState.speaking)
                    const Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 8),
                        Text('Speaking...'),
                      ],
                    ),
                ],

                const SizedBox(height: 32),

                // Start/Stop conversation button
                FloatingActionButton.extended(
                  onPressed: _conversationState == ConversationState.idle
                      ? _startConversation
                      : _endConversation,
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

                // New request button
                if (_responseText.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _recognizedText = '';
                        _responseText = '';
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('New Request'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
