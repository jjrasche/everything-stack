/// # PersonalityService
///
/// ## What it does
/// Manages active personality lifecycle and switching.
/// Wraps PersonalityRepository with higher-level operations.
///
/// ## Key Behavior
/// - Only one personality is active at a time (enforced by setActive)
/// - ensureDefault() creates default personality if none exists
/// - Provides convenient accessors for LLMConfig
///
/// ## Usage
/// ```dart
/// final service = PersonalityService(personalityRepo);
///
/// // Get active personality
/// final personality = await service.getActive();
///
/// // Ensure default exists
/// final default = await service.ensureDefault();
///
/// // Switch personality
/// await service.switchTo(personalityUuid);
/// ```

import 'package:everything_stack_template/domain/personality.dart';
import 'package:everything_stack_template/domain/personality_repository.dart';

class PersonalityService {
  final PersonalityRepository personalityRepo;

  PersonalityService({required this.personalityRepo});

  /// Get the currently active personality
  /// Returns null if no personality exists
  Future<Personality?> getActive() async {
    return personalityRepo.getActive();
  }

  /// Switch to a personality by UUID
  /// Deactivates all others and activates the target
  Future<void> switchTo(String personalityUuid) async {
    await personalityRepo.setActive(personalityUuid);
  }

  /// Ensure a default personality exists
  /// If no active personality exists, creates and activates default
  /// Returns the active (or newly created) personality
  Future<Personality> ensureDefault() async {
    final active = await personalityRepo.getActive();
    if (active != null) {
      return active;
    }

    // No active personality - check if any exist
    final all = await personalityRepo.findAll();
    if (all.isNotEmpty) {
      // Activate the first one
      final first = all.first;
      await personalityRepo.setActive(first.uuid);
      return first;
    }

    // No personalities exist - create default
    final defaultPersonality = Personality(
      name: 'Default Assistant',
      systemPrompt:
          '''You are a helpful voice assistant designed to help with tasks and time management.
Your role is to understand natural language requests and execute them accurately.
Be concise in responses, especially for voice interaction.
Ask clarifying questions if needed, but keep them brief.''',
    )
      ..baseModel = 'grok-2-1212'
      ..temperature = 0.7
      ..userPromptTemplate = '{input}'
      ..isActive = true;

    await personalityRepo.save(defaultPersonality);
    return defaultPersonality;
  }

  /// Get LLM configuration from active personality
  /// Includes model, temperature, and prompt template
  Future<Map<String, dynamic>> getLLMConfig() async {
    final personality = await getActive();
    if (personality == null) {
      throw StateError('No active personality');
    }

    return {
      'model': personality.baseModel,
      'temperature': personality.temperature,
      'systemPrompt': personality.systemPrompt,
      'userPromptTemplate': personality.userPromptTemplate,
    };
  }

  /// List all available personalities
  Future<List<Personality>> listAll() async {
    return personalityRepo.findAllOrdered();
  }

  /// Find personality by name
  Future<Personality?> findByName(String name) async {
    return personalityRepo.findByName(name);
  }
}
