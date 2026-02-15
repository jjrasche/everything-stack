class UiSchema {
  final String screenName;
  final String description;
  final List<WidgetDescriptor> widgets;

  const UiSchema({
    required this.screenName,
    required this.description,
    required this.widgets,
  });

  /// Get schema for a known screen
  static UiSchema? forScreen(String screenName) {
    return _schemas[screenName];
  }

  /// List all known screen schemas
  static List<String> get knownScreens => _schemas.keys.toList();

  /// Convert schema to VLM prompt context
  String toPrompt(String userQuery) {
    final widgetDescs = widgets
        .map((w) => '- ${w.name}: ${w.description} (shows: ${w.dataShown})')
        .join('\n');

    return '''
You are analyzing a screenshot of the "$screenName" screen.

SCREEN DESCRIPTION:
$description

UI ELEMENTS:
$widgetDescs

BADGE MEANINGS:
- S:XX% = Similarity (cosine similarity to search query, 0-100%)
- D:XX% = Decay (time-based relevance, 100%=fresh, lower=older)
- F:XX% = Fused score (S * D, overall relevance)
- Age badge (e.g., "3.2h" or "1.5d") = How old the item is

USER QUERY:
$userQuery

Provide a focused analysis addressing the user's query.
''';
  }

  /// Known screen schemas
  static final Map<String, UiSchema> _schemas = {
    'voice_assistant': UiSchema(
      screenName: 'Voice Assistant',
      description:
          'Main screen with search/context panel on left, conversation on right. '
          'Users can search semantic index, view context matches, and have voice conversations.',
      widgets: [
        WidgetDescriptor(
          name: 'Search Bar',
          description: 'Text input for semantic search queries',
          dataShown: 'Current search query text',
        ),
        WidgetDescriptor(
          name: 'Context Panel (Left)',
          description:
              'Shows search results or context matches. Each item has score badges and preview.',
          dataShown:
              'List of semantic matches with S/D/F scores, age, entity type, text preview',
        ),
        WidgetDescriptor(
          name: 'Conversation Panel (Right)',
          description: 'Chat-style conversation with AI assistant',
          dataShown: 'Message bubbles with user/assistant turns',
        ),
        WidgetDescriptor(
          name: 'Microphone Button',
          description: 'Blue button to start voice input',
          dataShown: 'Recording state (blue=ready, red=recording)',
        ),
        WidgetDescriptor(
          name: 'Similarity Slider',
          description:
              'Adjusts minimum similarity threshold for context filtering',
          dataShown: 'Current threshold value (0.0 - 1.0)',
        ),
      ],
    ),
    'search_results': UiSchema(
      screenName: 'Search Results',
      description: 'Showing semantic search results from the index.',
      widgets: [
        WidgetDescriptor(
          name: 'Result Card',
          description: 'Individual search result with metadata',
          dataShown:
              'S:XX% (similarity), D:XX% (decay), F:XX% (fused), age badge, entity type, text preview',
        ),
        WidgetDescriptor(
          name: 'Result Count',
          description: 'Header showing number of results',
          dataShown: '"Search Results (N)"',
        ),
      ],
    ),
  };
}

class WidgetDescriptor {
  final String name;
  final String description;
  final String dataShown;

  const WidgetDescriptor({
    required this.name,
    required this.description,
    required this.dataShown,
  });
}
