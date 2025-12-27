import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/services/coordinator.dart';
import 'package:everything_stack_template/services/tts_service.dart';
import 'package:everything_stack_template/services/stt_service.dart';
import 'package:everything_stack_template/services/audio_recording_service.dart';
import 'package:everything_stack_template/services/embedding_service.dart';

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

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen> {
  late Coordinator _coordinator;
  late TTSService _ttsService;
  late STTService _sttService;
  late AudioRecordingService _audioService;

  String _recognizedText = '';
  String _responseText = '';
  bool _isListening = false;
  bool _isProcessing = false;
  bool _isSpeaking = false;

  StreamSubscription<String>? _sttSubscription;

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

  /// Start listening for voice input via microphone
  Future<void> _startListening() async {
    if (_isListening) return;

    debugPrint('🎤 [_startListening] Starting audio capture...');

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
      _isListening = true;
      _recognizedText = '';
    });

    try {
      debugPrint('🎤 [_startListening] Getting audio stream from microphone...');

      // Get audio stream from microphone (PCM/16kHz/mono)
      final audioStream = _audioService.startRecording();

      debugPrint('🎤 [_startListening] Starting STT transcription via Deepgram...');

      // Pass audio to STT service and handle transcripts
      _sttSubscription = _sttService.transcribe(
        audio: audioStream,
        onTranscript: (transcript) {
          debugPrint('📝 [STT] Interim transcript: "$transcript"');
          if (mounted) {
            setState(() {
              _recognizedText = transcript;
            });
          }
        },
        onUtteranceEnd: () {
          debugPrint('✅ [STT] Speech ended (utterance_end)');
          // Speech has ended, process the transcript
          if (_isListening && _recognizedText.isNotEmpty) {
            _stopListening();
          }
        },
        onError: (error) {
          debugPrint('❌ [STT] Error: $error');
          if (mounted) {
            setState(() => _isListening = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('STT error: $error')),
            );
          }
        },
        onDone: () {
          debugPrint('🏁 [STT] Transcription stream closed');
          if (mounted) {
            setState(() => _isListening = false);
          }
        },
      );

      debugPrint('✅ [_startListening] Listening started');
    } catch (e) {
      debugPrint('❌ Error starting listening: $e');
      setState(() => _isListening = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  /// Stop listening and process recognized text
  Future<void> _stopListening() async {
    if (!_isListening) return;

    debugPrint('🛑 [_stopListening] Stopping audio capture and STT...');

    // Cancel STT subscription
    await _sttSubscription?.cancel();
    _sttSubscription = null;

    // Stop audio recording
    await _audioService.stopRecording();

    setState(() => _isListening = false);

    debugPrint('✅ [_stopListening] Stopped. Text: "$_recognizedText"');

    // Process the recognized text
    if (_recognizedText.isNotEmpty) {
      await _processRecognizedText(_recognizedText);
    }
  }

  /// Process recognized text through Coordinator
  Future<void> _processRecognizedText(String text) async {
    debugPrint('\n=== VOICE ASSISTANT: _processRecognizedText START ===');
    debugPrint('📥 Input text: "$text"');

    if (text.isEmpty) {
      debugPrint('❌ Text is empty, returning');
      return;
    }

    setState(() => _isProcessing = true);
    debugPrint('🔄 Set _isProcessing = true');

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
          _isProcessing = false;
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
        setState(() => _isProcessing = false);
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

    setState(() => _isSpeaking = true);

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

    if (mounted) {
      setState(() => _isSpeaking = false);
    }
  }

  @override
  void dispose() {
    debugPrint('🧹 [dispose] Cleaning up VoiceAssistantScreen...');
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
                if (_isListening)
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
                if (_isProcessing)
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
                  if (_isSpeaking)
                    const Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 8),
                        Text('Speaking...'),
                      ],
                    ),
                ],

                const SizedBox(height: 32),

                // Record/Stop button
                FloatingActionButton.extended(
                  onPressed: _isListening ? _stopListening : _startListening,
                  label: Text(_isListening ? 'Stop Listening' : 'Start Listening'),
                  icon: Icon(_isListening ? Icons.stop : Icons.mic),
                  backgroundColor: _isListening ? Colors.red : Colors.blue,
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
