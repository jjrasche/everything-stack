import 'package:flutter/material.dart';

import 'bootstrap.dart';
import 'domain/event.dart';
import 'services/coordinator.dart';
import 'ui/screens/voice_assistant_screen.dart';

enum InputModality { text, voice }
enum OutputModality { text, voice }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize all Everything Stack services
  // Configure via --dart-define or pass EverythingStackConfig
  await initializeEverythingStack();

  // Setup GetIt service locator with all application services
  setupServiceLocator();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Everything Stack Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const VoiceAssistantScreen(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late TextEditingController _inputController;
  bool _isRecording = false;
  String _recordingTime = '0:00';
  InputModality _inputModality = InputModality.text;
  OutputModality _outputModality = OutputModality.text;
  late Coordinator _coordinator;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _initializeCoordinator();
  }

  /// Initialize Coordinator with all trainable services
  void _initializeCoordinator() {
    // TODO: Wire up actual repositories and services when initialized in bootstrap
    // For now, this will fail if actually called, but the structure is ready
    try {
      // _coordinator = Coordinator(...);
      print('Coordinator initialization not yet implemented - awaiting bootstrap setup');
    } catch (e) {
      print('Failed to initialize Coordinator: $e');
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _submitPrompt(String input) {
    if (input.trim().isEmpty) return;

    try {
      // Create event and send to ContextManager
      final event = Event(
        correlationId: 'user_${DateTime.now().millisecondsSinceEpoch}',
        source: 'user',
        payload: {
          'prompt': input,
          'input_modality': _inputModality.toString(),
          'output_modality': _outputModality.toString(),
        },
      );

      // Publish event for async processing
      // TODO: Uncomment when Coordinator is initialized
      // _coordinator.orchestrate(...);
      print('Would publish event: ${event.payload}');

      _inputController.clear();
      if (mounted) setState(() {});

      // Show feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Event created (processing not yet wired): $input'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // Show error feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _startRecording() {
    setState(() {
      _isRecording = true;
      _recordingTime = '0:00';
    });
    // TODO: Initialize voice recording
  }

  void _stopRecording() {
    setState(() {
      _isRecording = false;
    });
    // TODO: Process voice input
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  const Text('Everything Stack'),
                  const SizedBox(height: 8),
                  Text(
                    'Ask what you need',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),

          // Input area with mode toggles
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Mode toggles
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => setState(() {
                        _inputModality = _inputModality == InputModality.text
                            ? InputModality.voice
                            : InputModality.text;
                      }),
                      icon: Text(_inputModality == InputModality.text ? '⌨️' : '🎤'),
                      label: Text(_inputModality == InputModality.text ? 'Type' : 'Speak'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _inputModality == InputModality.voice
                                ? Colors.red
                                : Colors.grey[700],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => setState(() {
                        _outputModality = _outputModality == OutputModality.text
                            ? OutputModality.voice
                            : OutputModality.text;
                      }),
                      icon: Text(_outputModality == OutputModality.text ? '📝' : '🔊'),
                      label: Text(_outputModality == OutputModality.text ? 'Read' : 'Listen'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _outputModality == OutputModality.voice
                                ? Colors.blue
                                : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Text input or voice recording UI
                if (_inputModality == InputModality.text)
                  TextField(
                    controller: _inputController,
                    decoration: InputDecoration(
                      hintText: 'What would you like to do?',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      suffixIcon: _inputController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.send),
                              onPressed: () =>
                                  _submitPrompt(_inputController.text),
                            )
                          : null,
                    ),
                    maxLines: null,
                    onChanged: (value) => setState(() {}),
                    onSubmitted: _submitPrompt,
                  )
                else
                  // Voice recording UI
                  Column(
                    children: [
                      if (_isRecording)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Recording: $_recordingTime',
                                style: const TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ElevatedButton.icon(
                        onPressed:
                            _isRecording ? _stopRecording : _startRecording,
                        icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                        label: Text(_isRecording ? 'Stop Recording' : 'Click to Record'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isRecording ? Colors.red : Colors.blue,
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
