import 'package:flutter/foundation.dart';

import '../../core/debug/debug_introspectable.dart';
import '../../domain/prompt_version.dart';
import '../../domain/prompt_version_repository.dart';

/// Manages versioned prompts for a single component type.
///
/// Each component (extraction, evaluation, etc.) gets its own registry
/// instance scoped by componentType. Backed by PromptVersionRepository
/// for proper entity persistence.
class PromptRegistry with DebugIntrospectable {
  final PromptVersionRepository _repo;
  final String componentType;
  final String _hardcodedDefault;

  int _activeVersion = 0;
  String? _cachedActivePrompt;

  PromptRegistry({
    required PromptVersionRepository repo,
    required this.componentType,
    required String hardcodedDefault,
  })  : _repo = repo,
        _hardcodedDefault = hardcodedDefault;

  int get activeVersion => _activeVersion;
  String get hardcodedDefault => _hardcodedDefault;

  Future<String> getActivePrompt() async {
    if (_cachedActivePrompt != null) return _cachedActivePrompt!;

    final active = await _repo.findActive(componentType);
    if (active == null) {
      _cachedActivePrompt = _hardcodedDefault;
      _activeVersion = 0;
      return _hardcodedDefault;
    }

    _cachedActivePrompt = active.promptText;
    _activeVersion = active.version;
    return active.promptText;
  }

  Future<List<PromptVersion>> getAllVersions() async {
    return _repo.findByComponent(componentType);
  }

  /// Save a new prompt version and activate it.
  Future<int> saveNewVersion({
    required String promptText,
    required String reason,
    Map<String, dynamic> metrics = const {},
  }) async {
    final nextVersion = await _repo.nextVersionNumber(componentType);

    final pv = PromptVersion(
      componentType: componentType,
      version: nextVersion,
      promptText: promptText,
      reason: reason,
      isActive: true,
      metrics: metrics,
    );
    await _repo.save(pv);

    // Deactivate previous active version
    final all = await _repo.findByComponent(componentType);
    for (final other in all) {
      if (other.uuid != pv.uuid && other.isActive) {
        other.isActive = false;
        await _repo.save(other);
      }
    }

    _cachedActivePrompt = promptText;
    _activeVersion = nextVersion;

    debugPrint('PromptRegistry[$componentType]: Saved version $nextVersion ($reason)');
    return nextVersion;
  }

  Future<bool> rollbackTo(int version) async {
    final versions = await getAllVersions();
    final target = versions.where((v) => v.version == version).firstOrNull;
    if (target == null) return false;

    await _repo.activateVersion(target.uuid);

    _cachedActivePrompt = target.promptText;
    _activeVersion = target.version;

    debugPrint('PromptRegistry[$componentType]: Rolled back to version $version');
    return true;
  }

  void invalidateCache() {
    _cachedActivePrompt = null;
  }

  // ============ DebugIntrospectable ============

  @override
  String get debugName => 'promptRegistry';

  @override
  Map<String, dynamic> getDebugState() => {
        'componentType': componentType,
        'activeVersion': _activeVersion,
        'hasCachedPrompt': _cachedActivePrompt != null,
        'cachedPromptLength': _cachedActivePrompt?.length ?? 0,
      };

  @override
  Map<String, DebugAction> getDebugActions() => {
        'getActivePrompt': DebugAction(
          description: 'Get the current active prompt',
          handler: (params) async {
            final prompt = await getActivePrompt();
            return {
              'version': _activeVersion,
              'promptLength': prompt.length,
              'prompt': prompt,
            };
          },
        ),
        'listVersions': DebugAction(
          description: 'List all prompt versions with metrics',
          handler: (params) async {
            final versions = await getAllVersions();
            return {
              'count': versions.length,
              'activeVersion': _activeVersion,
              'versions': versions
                  .map((v) => {
                        'version': v.version,
                        'reason': v.reason,
                        'metrics': v.metrics,
                        'createdAt': v.createdAt.toIso8601String(),
                        'promptLength': v.promptText.length,
                      })
                  .toList(),
            };
          },
        ),
        'rollback': DebugAction(
          description: 'Roll back to a specific prompt version',
          mutates: true,
          parameters: {'version': 'Version number to roll back to'},
          handler: (params) async {
            final version = int.tryParse(params['version'] ?? '');
            if (version == null) {
              return {'error': 'Missing or invalid version parameter'};
            }
            final success = await rollbackTo(version);
            return {
              'success': success,
              'activeVersion': _activeVersion,
            };
          },
        ),
      };
}
