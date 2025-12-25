import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:get_it/get_it.dart';
import 'package:everything_stack_template/services/coordinator.dart';
import 'package:everything_stack_template/services/tts_service.dart';

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
  late stt.SpeechToText _speechToText;
  late Coordinator _coordinator;
  late TTSService _ttsService;

  String _recognizedText = '';
  String _responseText = '';
  bool _isListening = false;
  bool _isProcessing = false;
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _speechToText = stt.SpeechToText();
    _coordinator = GetIt.instance<Coordinator>();
    _ttsService = TTSService.instance;
    _initializeSpeechToText();
  }

  /// Initialize speech-to-text service
  Future<void> _initializeSpeechToText() async {
    try {
      final available = await _speechToText.initialize(
        onError: (error) {
          print('STT Error: $error');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Speech recognition error: $error')),
          );
        },
        onStatus: (status) {
          print('STT Status: $status');
        },
      );

      if (!available) {
        print('Speech recognition not available');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Speech recognition not available on this device'),
            ),
          );
        }
      }
    } catch (e) {
      print('Failed to initialize speech recognition: $e');
    }
  }

  /// Start listening for voice input
  Future<void> _startListening() async {
    if (!_speechToText.isAvailable) {
      print('Speech recognition not available');
      return;
    }

    if (_isListening) return;

    setState(() {
      _isListening = true;
      _recognizedText = '';
    });

    try {
      await _speechToText.listen(
        onResult: (result) {
          setState(() {
            _recognizedText = result.recognizedWords;
          });

          // Auto-send when final result
          if (result.finalResult) {
            _isListening = false;
            _processRecognizedText(_recognizedText);
          }
        },
        localeId: 'en_US',
      );
    } catch (e) {
      print('Error starting speech recognition: $e');
      setState(() => _isListening = false);
    }
  }

  /// Stop listening
  Future<void> _stopListening() async {
    if (!_isListening) return;

    await _speechToText.stop();
    setState(() => _isListening = false);

    // Process the recognized text
    if (_recognizedText.isNotEmpty) {
      await _processRecognizedText(_recognizedText);
    }
  }

  /// Process recognized text through Coordinator
  Future<void> _processRecognizedText(String text) async {
    print('\n=== VOICE ASSISTANT: _processRecognizedText START ===');
    print('📥 Input text: "$text"');

    if (text.isEmpty) {
      print('❌ Text is empty, returning');
      return;
    }

    setState(() => _isProcessing = true);
    print('🔄 Set _isProcessing = true');

    try {
      final correlationId = '${DateTime.now().millisecondsSinceEpoch}';
      print('🔗 Correlation ID: $correlationId');
      print('📞 Calling coordinator.orchestrate()...');

      final result = await _coordinator.orchestrate(
        correlationId: correlationId,
        utterance: text,
        availableNamespaces: ['general'],
        toolsByNamespace: {
          'general': [],
        },
      );

      print('✅ Coordinator returned!');
      print('📊 Result: success=${result.success}, finalResponse="${result.finalResponse}"');
      print('⏱️ Latency: ${result.latencyMs}ms');

      if (!result.success) {
        print('❌ Coordinator failed: ${result.errorMessage}');
      }

      if (mounted) {
        print('📱 Widget mounted, updating UI...');
        setState(() {
          _responseText = result.finalResponse;
          _isProcessing = false;
        });
        print('💬 Updated response text: "${result.finalResponse}"');

        // Speak the response
        if (result.finalResponse.isNotEmpty) {
          print('🔊 Calling _speakResponse()...');
          await _speakResponse(result.finalResponse);
          print('✅ TTS complete');
        } else {
          print('⚠️ No response text to speak');
        }
      } else {
        print('⚠️ Widget not mounted, skipping UI update');
      }

      print('=== VOICE ASSISTANT: _processRecognizedText END (success) ===\n');
    } catch (e) {
      print('❌ EXCEPTION in _processRecognizedText: $e');
      print('Stack trace: ${StackTrace.current}');

      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      print('=== VOICE ASSISTANT: _processRecognizedText END (error) ===\n');
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
      print('TTS error: $e');
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
    _speechToText.cancel();
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
