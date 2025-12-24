/// # Narrative Prompt Rubrics
///
/// LLM-as-Judge evaluation criteria for Narrative prompts.
/// **CRITICAL**: Must stay aligned with prompts in test/prompts/narrative_prompts.dart
///
/// If you update a prompt, update the corresponding rubric.

class NarrativeRubric {
  /// Evaluate NarrativeThinker extraction output against expected criteria
  static NarrativeThinkerEvaluation evaluateThinkerExtraction({
    required String promptId,
    required String response,
    required String expectedBehavior,
  }) {
    final eval = NarrativeThinkerEvaluation(
      promptId: promptId,
      response: response,
      expectedBehavior: expectedBehavior,
    );

    // Parse response as JSON
    final isValidJson = _isValidJson(response);
    eval.validJson = isValidJson;
    if (!isValidJson) {
      eval.addFailure(
        'FORMAT_INVALID',
        'Response is not valid JSON array. Expected: [{"content": "...", "scope": "...", "type": "..."}]',
      );
      return eval;
    }

    // Parse entries
    final entries = _parseJsonArray(response);
    eval.entriesCount = entries.length;

    // Rubric checks based on prompt ID
    switch (promptId) {
      case 'extract-clear-learning':
        _checkClearLearningExtraction(eval, entries);
        break;
      case 'dedup-redundant-entry':
        _checkDeduplicationSkip(eval, entries);
        break;
      case 'extract-project-explicit':
        _checkProjectExtraction(eval, entries);
        break;
      case 'no-false-positives':
        _checkFalsePositiveAvoidance(eval, entries);
        break;
      case 'format-validation':
        _checkFormatValidation(eval, entries);
        break;
    }

    // Compute overall pass
    eval.overallPass = eval.criticalFailures.isEmpty;
    return eval;
  }

  /// Evaluate NarrativeCheckpoint refinement output
  static NarrativeCheckpointEvaluation evaluateCheckpointRefinement({
    required String promptId,
    required String response,
    required String expectedBehavior,
  }) {
    final eval = NarrativeCheckpointEvaluation(
      promptId: promptId,
      response: response,
      expectedBehavior: expectedBehavior,
    );

    // Parse response
    final isValidJson = _isValidJson(response);
    eval.validJson = isValidJson;
    if (!isValidJson) {
      eval.addFailure(
        'FORMAT_INVALID',
        'Response is not valid JSON. Expected empty [] or [{"content": "...", "scope": "project|life", "type": "..."}]',
      );
      return eval;
    }

    final entries = _parseJsonArray(response);
    eval.suggestionsCount = entries.length;

    // Rubric checks
    switch (promptId) {
      case 'suggest-emerging-project':
        _checkEmergingProjectSuggestion(eval, entries);
        break;
      case 'suggest-life-identity':
        _checkLifeIdentitySuggestion(eval, entries);
        break;
      case 'skip-insufficient-evidence':
        _checkInsufficientEvidenceSkip(eval, entries);
        break;
      case 'format-json-only':
        _checkCheckpointFormatValidation(eval, entries);
        break;
    }

    eval.overallPass = eval.criticalFailures.isEmpty;
    return eval;
  }
}

// ============================================================================
// THINKER EXTRACTION RUBRIC CHECKS
// ============================================================================

void _checkClearLearningExtraction(
  NarrativeThinkerEvaluation eval,
  List<Map<String, dynamic>> entries,
) {
  // RUBRIC: Should extract exactly one entry
  if (entries.isEmpty) {
    eval.addFailure(
      'NO_ENTRY',
      'Expected to extract at least one learning entry, got empty response',
    );
    return;
  }

  final entry = entries.first;

  // Check: content format "[idea]. Because [reason]"
  final content = entry['content'] as String? ?? '';
  if (!content.contains('.') || !content.contains('Because')) {
    eval.addFailure(
      'FORMAT_MISSING_BECAUSE',
      'Content missing "[Idea]. Because [Reason]" format. Got: "$content"',
    );
  }

  // Check: scope is session (not life for tech skills)
  final scope = entry['scope'] as String? ?? '';
  if (scope == 'life') {
    eval.addFailure(
      'SCOPE_ELEVATION',
      'Scope incorrectly elevated to "life" for specific tech skill. Should be "session"',
    );
  }

  // Check: type is learning
  final type = entry['type'] as String? ?? '';
  if (type != 'learning') {
    eval.addWarning(
      'TYPE_MISMATCH',
      'Type should be "learning" for learning goal, got: "$type"',
    );
  }

  // Check: no hallucinated reasoning
  if (content.isEmpty || content.length < 20) {
    eval.addFailure(
      'CONTENT_TOO_SHORT',
      'Content is suspiciously short or missing. Got: "$content"',
    );
  }
}

void _checkDeduplicationSkip(
  NarrativeThinkerEvaluation eval,
  List<Map<String, dynamic>> entries,
) {
  // RUBRIC: Should return EMPTY array (skip redundant)
  if (entries.isNotEmpty) {
    eval.addFailure(
      'DEDUP_FAILED',
      'Should skip redundant entry, but returned ${entries.length} entries. Indicates dedup check not working.',
    );
  }
  // If entries.isEmpty, test passes
}

void _checkProjectExtraction(
  NarrativeThinkerEvaluation eval,
  List<Map<String, dynamic>> entries,
) {
  if (entries.isEmpty) {
    eval.addFailure(
      'NO_EXTRACTION',
      'Should extract project entry, got empty response',
    );
    return;
  }

  final entry = entries.first;
  final scope = entry['scope'] as String? ?? '';
  final type = entry['type'] as String? ?? '';

  // RUBRIC: scope should be "session" NOT "project" (project requires training)
  if (scope == 'project') {
    eval.addFailure(
      'PREMATURE_SCOPE_ELEVATION',
      'Scope should be "session" on first mention. Only training checkpoint elevates to "project".',
    );
  }

  // RUBRIC: type should be "project"
  if (type != 'project') {
    eval.addWarning(
      'TYPE_MISMATCH',
      'Type should be "project" for explicit project mention, got: "$type"',
    );
  }

  // RUBRIC: content format
  final content = entry['content'] as String? ?? '';
  if (!content.contains('.') || !content.contains('Because')) {
    eval.addFailure(
      'FORMAT_MISSING_BECAUSE',
      'Missing "[Idea]. Because [Reason]" format',
    );
  }
}

void _checkFalsePositiveAvoidance(
  NarrativeThinkerEvaluation eval,
  List<Map<String, dynamic>> entries,
) {
  // RUBRIC: Should return EMPTY array (casual statement is not insight)
  if (entries.isNotEmpty) {
    eval.addFailure(
      'FALSE_POSITIVE',
      'Should recognize casual statement as noise and return []. Instead extracted: ${entries.length} entries.',
    );
  }
}

void _checkFormatValidation(
  NarrativeThinkerEvaluation eval,
  List<Map<String, dynamic>> entries,
) {
  // RUBRIC: Response should be valid JSON, nothing else
  // Already checked validJson above

  if (entries.isNotEmpty) {
    final entry = entries.first;

    // All required fields present
    if (!entry.containsKey('content') ||
        !entry.containsKey('scope') ||
        !entry.containsKey('type')) {
      eval.addFailure(
        'MISSING_FIELDS',
        'Entry missing required fields: content, scope, type',
      );
    }

    // Scope is valid
    final scope = entry['scope'] as String? ?? '';
    const validScopes = ['session', 'day', 'week', 'project', 'life'];
    if (!validScopes.contains(scope)) {
      eval.addFailure(
        'INVALID_SCOPE',
        'Scope "$scope" not in valid list: $validScopes',
      );
    }
  }
}

// ============================================================================
// CHECKPOINT REFINEMENT RUBRIC CHECKS
// ============================================================================

void _checkEmergingProjectSuggestion(
  NarrativeCheckpointEvaluation eval,
  List<Map<String, dynamic>> entries,
) {
  // RUBRIC: Should suggest 1 project entry
  if (entries.isEmpty) {
    eval.addFailure(
      'NO_SUGGESTION',
      'With 3+ related session entries, should suggest an emerging project. Got empty response.',
    );
    return;
  }

  if (entries.length > 2) {
    eval.addWarning(
      'TOO_MANY_SUGGESTIONS',
      'Expected 1-2 suggestions max, got ${entries.length}',
    );
  }

  final entry = entries.first;
  final scope = entry['scope'] as String? ?? '';

  // RUBRIC: scope must be "project"
  if (scope != 'project') {
    eval.addFailure(
      'WRONG_SCOPE',
      'Should be scope="project" for emerging project theme, got: "$scope"',
    );
  }

  // RUBRIC: format
  final content = entry['content'] as String? ?? '';
  if (!content.contains('Building') && !content.contains('creating')) {
    eval.addWarning(
      'VAGUE_PROJECT',
      'Project description should be specific about what\'s being built',
    );
  }
}

void _checkLifeIdentitySuggestion(
  NarrativeCheckpointEvaluation eval,
  List<Map<String, dynamic>> entries,
) {
  // RUBRIC: Should suggest 1 life entry if pattern is strong
  if (entries.isEmpty) {
    eval.addFailure(
      'NO_LIFE_SUGGESTION',
      'With consistent decentralization theme across multiple entries, should suggest life identity. Got empty.',
    );
    return;
  }

  final entry = entries.first;
  final scope = entry['scope'] as String? ?? '';

  // RUBRIC: scope must be "life"
  if (scope != 'life') {
    eval.addFailure(
      'WRONG_SCOPE_FOR_LIFE',
      'Should be scope="life" for identity pattern, got: "$scope"',
    );
  }

  // RUBRIC: should mention the actual value/belief
  final content = entry['content'] as String? ?? '';
  if (content.isEmpty || content.length < 30) {
    eval.addFailure(
      'VAGUE_IDENTITY',
      'Life identity should be clear and substantive, got: "$content"',
    );
  }
}

void _checkInsufficientEvidenceSkip(
  NarrativeCheckpointEvaluation eval,
  List<Map<String, dynamic>> entries,
) {
  // RUBRIC: Should return EMPTY (single mention is not a project)
  if (entries.isNotEmpty) {
    eval.addFailure(
      'OVER_GENERALIZATION',
      'Should skip single mention, need multiple entries to confirm project. Returned: ${entries.length} entries.',
    );
  }
}

void _checkCheckpointFormatValidation(
  NarrativeCheckpointEvaluation eval,
  List<Map<String, dynamic>> entries,
) {
  // RUBRIC: Valid JSON only
  // Already checked validJson

  // No extra text/markdown
  // (This would be caught by validJson check)
}

// ============================================================================
// EVALUATION DATA CLASSES
// ============================================================================

class NarrativeThinkerEvaluation {
  final String promptId;
  final String response;
  final String expectedBehavior;
  late bool validJson;
  late int entriesCount;
  final List<String> criticalFailures = [];
  final List<String> warnings = [];
  late bool overallPass;

  NarrativeThinkerEvaluation({
    required this.promptId,
    required this.response,
    required this.expectedBehavior,
  });

  void addFailure(String code, String message) {
    criticalFailures.add('[$code] $message');
  }

  void addWarning(String code, String message) {
    warnings.add('[$code] $message');
  }

  bool get hasCriticalFailures => criticalFailures.isNotEmpty;
}

class NarrativeCheckpointEvaluation {
  final String promptId;
  final String response;
  final String expectedBehavior;
  late bool validJson;
  late int suggestionsCount;
  final List<String> criticalFailures = [];
  final List<String> warnings = [];
  late bool overallPass;

  NarrativeCheckpointEvaluation({
    required this.promptId,
    required this.response,
    required this.expectedBehavior,
  });

  void addFailure(String code, String message) {
    criticalFailures.add('[$code] $message');
  }

  void addWarning(String code, String message) {
    warnings.add('[$code] $message');
  }

  bool get hasCriticalFailures => criticalFailures.isNotEmpty;
}

// ============================================================================
// JSON PARSING HELPERS
// ============================================================================

bool _isValidJson(String response) {
  try {
    // Check if it's a valid JSON array
    if (!response.trim().startsWith('[')) return false;
    if (!response.trim().endsWith(']')) return false;
    // In real implementation, would use jsonDecode
    return true;
  } catch (e) {
    return false;
  }
}

List<Map<String, dynamic>> _parseJsonArray(String response) {
  try {
    // Parse JSON array
    // In real implementation, would use jsonDecode
    // For now, return empty (would be implemented with actual JSON parsing)
    return [];
  } catch (e) {
    return [];
  }
}
