/// # Narrative Prompt Definitions
///
/// System prompts for:
/// 1. NarrativeThinker - Extract narrative entries with dedup
/// 2. NarrativeCheckpoint - Suggest Project/Life themes
///
/// **CRITICAL**: Rubrics (test/framework/narrative_rubric.dart) must stay aligned with these prompts.
/// When updating a prompt, update the corresponding rubric criteria.

// ============================================================================
// NARRATIVE THINKER EXTRACTION PROMPT
// ============================================================================

/// System prompt for narrative entry extraction.
/// Used by NarrativeThinker to extract new insights from conversation.
String getNarrativeThinkerSystemPrompt() =>
    '''You are the system's self-model extractor. Your job is to identify new insights about the user's identity, goals, and reasoning from conversation.

CRITICAL RULES:
1. Extract NEW narrative entries ONLY. Skip if redundant with existing narratives.
2. Format EXACTLY: "[Atomic idea]. Because [reasoning]."
3. Be concise. One sentence per entry. No multi-sentence entries.
4. Identify entry type: 'learning', 'project', or 'exploration'
5. Assign CORRECT scope based on context:
   - 'session': Current conversation, always fresh insights
   - 'day': Multi-conversation pattern within a day (only if user shows persistence)
   - 'week': Weekly themes (rarely used, only explicit)
   - 'project': User-defined project context (ONLY if user explicitly names/owns a project)
   - 'life': Identity-level patterns (ONLY if fundamental/core - rare)
6. Return VALID JSON array ONLY. No markdown, no explanations, no preamble.
7. Return empty array [] if nothing new.
8. NEVER invent projects or life insights. Only surface what's evident.
9. DEDUPLICATION CHECK: Compare input against existing narratives. If 90%+ match in meaning, skip.

RESPONSE FORMAT:
[
  {
    "content": "[idea]. Because [reason].",
    "scope": "session|day|week|project|life",
    "type": "learning|project|exploration"
  }
]

EXAMPLE (correct):
[
  {
    "content": "Distributed systems enable resilience. Because centralized systems fail at scale.",
    "scope": "session",
    "type": "learning"
  }
]

EXAMPLE (incorrect - don't do this):
[
  {
    "content": "The user talked about distributed systems and how they are resilient and scalable and useful. Because they help with many things.",
    "scope": "life",
    "type": "learning"
  }
]
Why incorrect: Too long, vague reasoning, premature scope elevation to "life"
''';

// ============================================================================
// NARRATIVE CHECKPOINT REFINEMENT PROMPT
// ============================================================================

/// System prompt for Project/Life theme suggestion.
/// Used by NarrativeCheckpoint to drive conversational refinement.
String getNarrativeCheckpointSystemPrompt() =>
    '''You are helping the user identify deeper project and life narratives.
Based on their session and day narratives, suggest any emerging projects or life identity patterns.

RULES:
1. ONLY suggest if evident from context. Be conservative.
2. Projects: Multi-turn endeavors ("Building X", "Learning Y", "Exploring Z")
3. Life: Core identity/values ("Decentralized systems matter", "Rapid iteration > planning")
4. Return VALID JSON array ONLY. No markdown.
5. Return empty [] if nothing new.
6. Format EXACTLY: "[idea]. Because [reason]."
7. Each entry must have clear atomic idea + reasoning.

RESPONSE FORMAT:
[
  {
    "content": "[idea]. Because [reason].",
    "scope": "project|life",
    "type": "learning|project|exploration"
  }
]

EXAMPLE (correct):
[
  {
    "content": "Building conversational AI. Because friction between thought and execution kills potential.",
    "scope": "project",
    "type": "project"
  },
  {
    "content": "Distributed systems are core. Because centralization always optimizes for the center, not edges.",
    "scope": "life",
    "type": "learning"
  }
]

EXAMPLE (incorrect - don't do this):
[
  {
    "content": "User seems to like AI and distributed systems",
    "scope": "life",
    "type": "learning"
  }
]
Why incorrect: Not atomic, no clear reasoning, vague observation
''';

// ============================================================================
// TEST CASE DEFINITIONS (for Prompt Testing)
// ============================================================================

/// Test case for NarrativeThinker extraction prompt
class NarrativeThinkerTestCase {
  final String id;
  final String name;
  final String description;
  final String utterance;
  final Map<String, dynamic> intent;
  final List<Map<String, dynamic>> chatHistory;
  final List<String> existingNarratives; // For dedup test
  final String expectedBehavior;

  NarrativeThinkerTestCase({
    required this.id,
    required this.name,
    required this.description,
    required this.utterance,
    required this.intent,
    required this.chatHistory,
    this.existingNarratives = const [],
    required this.expectedBehavior,
  });
}

/// Test cases for NarrativeThinker prompt
List<NarrativeThinkerTestCase> getNarrativeThinkerTestCases() => [
      NarrativeThinkerTestCase(
        id: 'extract-clear-learning',
        name: 'Extract Clear Learning Insight',
        description: 'User explicitly states learning goal',
        utterance:
            'I want to learn Rust because it teaches ownership and memory safety',
        intent: {
          'classification': 'intent:learning',
          'confidence': 0.95,
          'reasoning': 'User expressing learning goal',
        },
        chatHistory: [
          {
            'role': 'user',
            'content':
                'I want to learn Rust because it teaches ownership and memory safety'
          },
        ],
        existingNarratives: [],
        expectedBehavior: '''Should extract:
- Content: "[Atomic idea about Rust]. Because [reasoning about memory/ownership]."
- Scope: "session" (current conversation)
- Type: "learning"
- NOT life scope (specific tech skill, not identity)
- Format: Valid JSON array with single entry
- No hallucinations or invented reasoning''',
      ),
      NarrativeThinkerTestCase(
        id: 'dedup-redundant-entry',
        name: 'Skip Redundant Entry',
        description: 'Similar content exists, should detect and skip',
        utterance:
            'Rust is really good for memory safety. That\'s why I like learning it.',
        intent: {
          'classification': 'intent:learning',
          'confidence': 0.90,
          'reasoning': 'Reinforcing previous learning goal',
        },
        chatHistory: [
          {'role': 'user', 'content': 'I want to learn Rust for memory safety'},
          {'role': 'assistant', 'content': 'Great, Rust is powerful for that.'},
          {
            'role': 'user',
            'content':
                'Rust is really good for memory safety. That\'s why I like learning it.'
          },
        ],
        existingNarratives: [
          'Rust teaches memory safety. Because explicit control prevents bugs.',
        ],
        expectedBehavior: '''Should detect dedup:
- NEW utterance is ~90% semantically similar to existing narrative
- Prompt should check: "If redundant with existing, skip"
- Return: [] (empty array)
- Explanation: Same idea already captured, avoid duplication''',
      ),
      NarrativeThinkerTestCase(
        id: 'extract-project-explicit',
        name: 'Extract Project When Explicitly Named',
        description: 'User names a specific project/endeavor',
        utterance: 'I\'m building a chatbot that learns from user corrections',
        intent: {
          'classification': 'intent:project',
          'confidence': 0.92,
          'reasoning': 'User describing active project',
        },
        chatHistory: [
          {
            'role': 'user',
            'content':
                'I\'m building a chatbot that learns from user corrections'
          },
        ],
        existingNarratives: [],
        expectedBehavior: '''Should extract:
- Content: "Building a chatbot that learns from feedback. Because [reason about learning/iteration]."
- Scope: "session" (first mention - not promoted to 'project' scope until training)
- Type: "project"
- NOT promote to 'project' scope automatically (requires training checkpoint)
- Reason: Groq should NOT invent 'project' scope - only surface what's evident at session level''',
      ),
      NarrativeThinkerTestCase(
        id: 'no-false-positives',
        name: 'Avoid False Positives',
        description: 'Casual mention, not a real insight',
        utterance: 'By the way, I had coffee this morning',
        intent: {
          'classification': 'small-talk',
          'confidence': 0.88,
          'reasoning': 'Casual statement, no insight',
        },
        chatHistory: [
          {'role': 'user', 'content': 'By the way, I had coffee this morning'},
        ],
        existingNarratives: [],
        expectedBehavior: '''Should skip:
- Not an insight about user's identity/goals/reasoning
- Return: [] (empty array)
- Groq should recognize: "This is noise, not a narrative insight"''',
      ),
      NarrativeThinkerTestCase(
        id: 'format-validation',
        name: 'Valid JSON Format Only',
        description: 'Verify response is valid JSON, not markdown',
        utterance: 'I believe strongly in decentralized systems',
        intent: {
          'classification': 'intent:belief',
          'confidence': 0.85,
          'reasoning': 'User expressing core value',
        },
        chatHistory: [
          {
            'role': 'user',
            'content': 'I believe strongly in decentralized systems'
          },
        ],
        existingNarratives: [],
        expectedBehavior: '''Should return VALID JSON:
- Not markdown with code fences
- Not explanatory text before/after JSON
- Exactly: [{"content": "...", "scope": "...", "type": "..."}]
- If extracted: scope should be "session" (identity conviction, but not 'life' without more evidence)''',
      ),
    ];

/// Test case for NarrativeCheckpoint refinement prompt
class NarrativeCheckpointTestCase {
  final String id;
  final String name;
  final String description;
  final List<String> sessionNarratives;
  final List<String> dayNarratives;
  final String expectedBehavior;

  NarrativeCheckpointTestCase({
    required this.id,
    required this.name,
    required this.description,
    required this.sessionNarratives,
    required this.dayNarratives,
    required this.expectedBehavior,
  });
}

/// Test cases for NarrativeCheckpoint prompt
List<NarrativeCheckpointTestCase> getNarrativeCheckpointTestCases() => [
      NarrativeCheckpointTestCase(
        id: 'suggest-emerging-project',
        name: 'Suggest Emerging Project Theme',
        description: 'Session narratives point to a recurring project',
        sessionNarratives: [
          'Building conversational AI. Because friction between thought and execution kills potential.',
          'Implementing intent extraction. Because understanding user goals is foundational.',
          'Exploring prompt engineering. Because tuning the model is critical.',
        ],
        dayNarratives: [
          'Learned about semantic search. Because relevance matters for AI systems.',
        ],
        expectedBehavior: '''Should suggest:
- Content: "Building an intent-driven AI system. Because [reasoning about iterative improvement]."
- Scope: "project"
- Type: "project"
- Conservative: Only suggest if pattern is clear (3+ related entries)
- Format: Valid JSON, one entry max for projects in a day''',
      ),
      NarrativeCheckpointTestCase(
        id: 'suggest-life-identity',
        name: 'Suggest Life Identity Pattern',
        description: 'Multiple days show consistent values/beliefs',
        sessionNarratives: [
          'Distributed systems enable resilience. Because centralized systems optimize for the center.',
          'Decentralization reduces single points of failure. Because redundancy is strength.',
        ],
        dayNarratives: [
          'Off-chain computation improves privacy. Because centralized control is dangerous.',
          'Blockchain enables trust without authority. Because decentralization matters.',
        ],
        expectedBehavior: '''Should suggest:
- Content: "Decentralization is core. Because centralized systems fail users."
- Scope: "life"
- Type: "learning"
- CONSERVATIVE: Only suggest if pattern spans multiple days AND multiple entries
- This is RARE. Groq should be careful not to over-generalize''',
      ),
      NarrativeCheckpointTestCase(
        id: 'skip-insufficient-evidence',
        name: 'Skip Project Without Enough Evidence',
        description: 'Single mention is not a project',
        sessionNarratives: [
          'Mentioned wanting to try painting. Because it sounds relaxing.',
        ],
        dayNarratives: [],
        expectedBehavior: '''Should return empty:
- Return: [] (empty array)
- Single mention is not a project unless user explicitly commits
- Need: Multi-turn engagement, repeated mentions, clear ownership''',
      ),
      NarrativeCheckpointTestCase(
        id: 'format-json-only',
        name: 'Return Valid JSON Only',
        description: 'No markdown, no explanations',
        sessionNarratives: [
          'Building something. Because learning through creation matters.',
        ],
        dayNarratives: [],
        expectedBehavior: '''Should return:
- Valid JSON array (may be empty [])
- No markdown code fences
- No explanatory text
- If returning suggestions: exactly the format specified''',
      ),
    ];
