import 'package:flutter/foundation.dart';

import '../inference_service.dart';
import 'prompt_types.dart';

class MutationResult {
  final String mutatedPrompt;
  final String reasoning;
  final Map<String, int> failureDimensions;

  MutationResult({
    required this.mutatedPrompt,
    required this.reasoning,
    required this.failureDimensions,
  });
}

/// Generates improved prompts from evaluation failures.
///
/// Generic: works with any PromptFailure + DimensionSpec, not tied to extraction.
/// The dimension-specific guidance comes from DimensionSpec.failureGuidance,
/// not hardcoded in this class.
class PromptMutator {
  static const String _mutationModel = 'llama-3.3-70b-versatile';
  static const int _maxFailureExamples = 10;

  final InferenceService _inferenceService;

  PromptMutator({required InferenceService inferenceService})
      : _inferenceService = inferenceService;

  Future<MutationResult> mutate({
    required String currentPrompt,
    required List<PromptFailure> failures,
    required List<DimensionSpec> dimensions,
  }) async {
    final failureDimensions = _groupFailuresByDimension(failures);
    final failureExamples = _formatFailureExamples(failures);
    final mutationGuidance = _buildDimensionGuidance(dimensions, failureDimensions);

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt(mutationGuidance)},
      {
        'role': 'user',
        'content': _buildRequest(
          currentPrompt: currentPrompt,
          failureDimensions: failureDimensions,
          failureExamples: failureExamples,
          dimensions: dimensions,
        ),
      },
    ];

    final response = await _inferenceService.chatWithTools(
      model: _mutationModel,
      messages: messages,
      temperature: 0.4,
      maxTokens: 2000,
    );

    final responseText = response.content ?? '';
    return MutationResult(
      mutatedPrompt: _extractPrompt(responseText, currentPrompt),
      reasoning: _extractReasoning(responseText),
      failureDimensions: failureDimensions,
    );
  }

  Map<String, int> _groupFailuresByDimension(List<PromptFailure> failures) {
    final counts = <String, int>{};
    for (final f in failures) {
      for (final entry in f.dimensionScores.entries) {
        if (!entry.value) {
          counts[entry.key] = (counts[entry.key] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  String _formatFailureExamples(List<PromptFailure> failures) {
    final buffer = StringBuffer();
    for (final f in failures.take(_maxFailureExamples)) {
      buffer.writeln('---');
      buffer.writeln('Output: "${f.outputContent}"');
      final failedDimensions = f.dimensionScores.entries
          .where((e) => !e.value)
          .map((e) => e.key);
      buffer.writeln('Failed: ${failedDimensions.join(", ")}');
      if (f.reasoning.isNotEmpty) buffer.writeln('Reasoning: ${f.reasoning}');
      buffer.writeln();
    }
    return buffer.toString();
  }

  String _buildDimensionGuidance(
    List<DimensionSpec> dimensions,
    Map<String, int> failureCounts,
  ) {
    final buffer = StringBuffer();
    for (final dim in dimensions) {
      if (failureCounts.containsKey(dim.name)) {
        buffer.writeln(
          '- If ${dim.name} fails: ${dim.failureGuidance}',
        );
      }
    }
    return buffer.toString();
  }

  String _systemPrompt(String dimensionGuidance) =>
      '''You are a prompt engineering expert. Improve the given prompt based on evaluation failures.

Rules:
1. Return the COMPLETE prompt, not a diff.
2. Focus improvements on dimensions that fail most often.
3. Be specific — don't add vague guidance.
$dimensionGuidance

Return your response in this format:
REASONING: <brief explanation of changes>
PROMPT_START
<the complete improved prompt>
PROMPT_END''';

  String _buildRequest({
    required String currentPrompt,
    required Map<String, int> failureDimensions,
    required String failureExamples,
    required List<DimensionSpec> dimensions,
  }) {
    final sorted = failureDimensions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final dimensionSummary =
        sorted.map((e) => '${e.key}: ${e.value} failures').join(', ');

    final weightSummary = dimensions
        .map((d) => '- ${d.name}: ${d.weight} (weight)')
        .join('\n');

    return '''## Current prompt:
```
$currentPrompt
```

## Failure analysis:
Breakdown: $dimensionSummary

## Dimension weights:
$weightSummary

## Example failures:
$failureExamples

## Task:
Produce an improved prompt addressing these failures.
Focus on dimensions with most failures and highest weights.''';
  }

  String _extractPrompt(String response, String fallback) {
    const startMarker = 'PROMPT_START';
    const endMarker = 'PROMPT_END';

    final startIdx = response.indexOf(startMarker);
    final endIdx = response.indexOf(endMarker);

    if (startIdx == -1 || endIdx == -1 || endIdx <= startIdx) {
      debugPrint('PromptMutator: Could not find prompt markers in response');
      return fallback;
    }

    final prompt =
        response.substring(startIdx + startMarker.length, endIdx).trim();
    return prompt.isEmpty ? fallback : prompt;
  }

  String _extractReasoning(String response) {
    final match = RegExp(r'REASONING:\s*(.*?)(?=PROMPT_START)', dotAll: true)
        .firstMatch(response);
    return match?.group(1)?.trim() ?? 'No reasoning provided';
  }
}
