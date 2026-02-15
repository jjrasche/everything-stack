import 'dart:convert';
import 'vlm_analyzer.dart';

/// Describes what actions can be performed on a widget
class WidgetAffordance {
  final String widgetName;
  final String action;
  final String description;
  final bool requiresInput;

  const WidgetAffordance({
    required this.widgetName,
    required this.action,
    required this.description,
    this.requiresInput = false,
  });

  Map<String, dynamic> toJson() => {
        'widget': widgetName,
        'action': action,
        'description': description,
        'requiresInput': requiresInput,
      };
}

/// Describes a piece of data that can be extracted from the screen
class DataExtractor {
  final String field;
  final String description;
  final String type; // 'string', 'number', 'boolean', 'list'
  final String? location; // Where on screen to find this

  const DataExtractor({
    required this.field,
    required this.description,
    required this.type,
    this.location,
  });

  Map<String, dynamic> toJson() => {
        'field': field,
        'description': description,
        'type': type,
        if (location != null) 'location': location,
      };
}

/// Describes visual indicators for different states
class StateIndicator {
  final String state;
  final String visualCue;
  final String meaning;

  const StateIndicator({
    required this.state,
    required this.visualCue,
    required this.meaning,
  });

  String toDescription() => '$state: $visualCue → $meaning';
}

/// Structured response from VLM analysis
class VlmAnalysisResult {
  final String screenIdentified;
  final String screenState;
  final Map<String, dynamic> data;
  final List<String> availableActions;
  final List<String> errors;
  final List<String> warnings;
  final String? rawAnalysis;

  VlmAnalysisResult({
    required this.screenIdentified,
    required this.screenState,
    required this.data,
    required this.availableActions,
    required this.errors,
    required this.warnings,
    this.rawAnalysis,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
  bool get canInteract => availableActions.isNotEmpty;

  /// Check if a specific action is available
  bool canDo(String action) =>
      availableActions.any((a) => a.toLowerCase().contains(action.toLowerCase()));

  /// Get a data value with type safety
  T? getValue<T>(String field) {
    final value = data[field];
    if (value is T) return value;
    return null;
  }

  @override
  String toString() => '''
VlmAnalysisResult(
  screen: $screenIdentified,
  state: $screenState,
  data: $data,
  actions: $availableActions,
  errors: $errors,
  warnings: $warnings,
)''';
}

/// Enhanced UI schema with interaction capabilities
class UiInteractionSchema {
  final String screenName;
  final String description;
  final List<WidgetAffordance> affordances;
  final List<DataExtractor> dataExtractors;
  final List<StateIndicator> stateIndicators;

  const UiInteractionSchema({
    required this.screenName,
    required this.description,
    required this.affordances,
    required this.dataExtractors,
    required this.stateIndicators,
  });

  /// Get schema for a known screen
  static UiInteractionSchema? forScreen(String screenName) {
    return _schemas[screenName];
  }

  /// List all known screen schemas
  static List<String> get knownScreens => _schemas.keys.toList();

  /// Generate prompt that asks VLM for structured JSON response
  String toStructuredPrompt(String query) {
    final affordanceList =
        affordances.map((a) => '  - ${a.action}: ${a.description}').join('\n');

    final dataFields =
        dataExtractors.map((d) => '  "${d.field}": <${d.type}> // ${d.description}').join('\n');

    final stateList = stateIndicators.map((s) => '  - ${s.toDescription()}').join('\n');

    return '''
You are analyzing a screenshot of the "$screenName" screen.

SCREEN DESCRIPTION:
$description

AVAILABLE USER ACTIONS (affordances):
$affordanceList

VISUAL STATE INDICATORS:
$stateList

YOUR TASK:
Analyze the screenshot and return a JSON object with the following structure:

{
  "screenIdentified": "$screenName",
  "screenState": "<current state based on visual indicators>",
  "data": {
$dataFields
  },
  "availableActions": ["<list of actions that appear possible based on current state>"],
  "errors": ["<any error messages or error states visible>"],
  "warnings": ["<any warning indicators visible>"]
}

USER QUERY:
$query

IMPORTANT:
- Return ONLY valid JSON, no other text
- Use null for unknown/not visible values
- Base "availableActions" on what the UI currently allows (disabled buttons = not available)
- Extract actual values visible on screen, don't guess
''';
  }

  /// Analyze a screenshot and return structured result
  Future<VlmAnalysisResult> analyzeWithVlm({
    required VlmAnalyzer vlm,
    required String screenshotPath,
    String query = 'Describe the current state',
  }) async {
    final prompt = toStructuredPrompt(query);
    final response = await vlm.analyzeScreenshot(
      imagePath: screenshotPath,
      prompt: prompt,
    );

    return parseResponse(response);
  }

  /// Parse VLM response into structured result
  VlmAnalysisResult parseResponse(String response) {
    try {
      // Try to extract JSON from response (VLM might add extra text)
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(response);
      if (jsonMatch == null) {
        return _fallbackResult(response, 'No JSON found in response');
      }

      final json = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;

      return VlmAnalysisResult(
        screenIdentified: json['screenIdentified'] as String? ?? screenName,
        screenState: json['screenState'] as String? ?? 'unknown',
        data: (json['data'] as Map<String, dynamic>?) ?? {},
        availableActions:
            (json['availableActions'] as List<dynamic>?)?.cast<String>() ?? [],
        errors: (json['errors'] as List<dynamic>?)?.cast<String>() ?? [],
        warnings: (json['warnings'] as List<dynamic>?)?.cast<String>() ?? [],
        rawAnalysis: response,
      );
    } catch (e) {
      return _fallbackResult(response, 'JSON parse error: $e');
    }
  }

  VlmAnalysisResult _fallbackResult(String response, String error) {
    return VlmAnalysisResult(
      screenIdentified: screenName,
      screenState: 'parse_error',
      data: {},
      availableActions: [],
      errors: [error],
      warnings: [],
      rawAnalysis: response,
    );
  }

  /// Known screen schemas with interaction capabilities
  static final Map<String, UiInteractionSchema> _schemas = {
    'voice_assistant': UiInteractionSchema(
      screenName: 'Voice Assistant',
      description:
          'Main screen with search/context panel on left, conversation on right. '
          'Users can search semantic index, view context matches, and have voice conversations.',
      affordances: [
        WidgetAffordance(
          widgetName: 'Search Bar',
          action: 'search',
          description: 'Type a search query to find semantically similar content',
          requiresInput: true,
        ),
        WidgetAffordance(
          widgetName: 'Search Bar',
          action: 'clear_search',
          description: 'Clear the search query',
        ),
        WidgetAffordance(
          widgetName: 'Result Card',
          action: 'select_result',
          description: 'Click a search result to expand or view details',
        ),
        WidgetAffordance(
          widgetName: 'Microphone Button',
          action: 'start_voice_input',
          description: 'Start recording voice input (button must be blue/ready)',
        ),
        WidgetAffordance(
          widgetName: 'Microphone Button',
          action: 'stop_voice_input',
          description: 'Stop recording (button must be red/recording)',
        ),
        WidgetAffordance(
          widgetName: 'Similarity Slider',
          action: 'adjust_threshold',
          description: 'Drag slider to change minimum similarity threshold',
          requiresInput: true,
        ),
      ],
      dataExtractors: [
        DataExtractor(
          field: 'searchQuery',
          description: 'Current text in search bar',
          type: 'string',
          location: 'Search Bar',
        ),
        DataExtractor(
          field: 'resultsCount',
          description: 'Number of search results shown',
          type: 'number',
          location: 'Context Panel header or count of result cards',
        ),
        DataExtractor(
          field: 'topResultSimilarity',
          description: 'Similarity score of first result (S:XX%)',
          type: 'number',
          location: 'First result card S badge',
        ),
        DataExtractor(
          field: 'thresholdValue',
          description: 'Current similarity threshold from slider',
          type: 'number',
          location: 'Slider label or position',
        ),
        DataExtractor(
          field: 'isRecording',
          description: 'Whether microphone is actively recording',
          type: 'boolean',
          location: 'Microphone button color (red=recording)',
        ),
        DataExtractor(
          field: 'conversationTurns',
          description: 'Number of message bubbles in conversation',
          type: 'number',
          location: 'Conversation Panel',
        ),
        DataExtractor(
          field: 'lastAssistantMessage',
          description: 'Text of most recent assistant response',
          type: 'string',
          location: 'Last assistant bubble in Conversation Panel',
        ),
      ],
      stateIndicators: [
        StateIndicator(
          state: 'idle',
          visualCue: 'Empty search bar, no results, blue mic button',
          meaning: 'Ready for user input',
        ),
        StateIndicator(
          state: 'searching',
          visualCue: 'Loading spinner or "Searching..." text',
          meaning: 'Search in progress',
        ),
        StateIndicator(
          state: 'results_shown',
          visualCue: 'List of result cards with S/D/F badges',
          meaning: 'Search completed with results',
        ),
        StateIndicator(
          state: 'no_results',
          visualCue: '"No results" message or empty list',
          meaning: 'Search completed but nothing matched',
        ),
        StateIndicator(
          state: 'recording',
          visualCue: 'Red microphone button, possibly waveform',
          meaning: 'Capturing voice input',
        ),
        StateIndicator(
          state: 'processing',
          visualCue: 'Loading indicator in conversation area',
          meaning: 'AI is generating response',
        ),
        StateIndicator(
          state: 'error',
          visualCue: 'Red text, error icon, or error banner',
          meaning: 'Something went wrong',
        ),
      ],
    ),
  };
}
