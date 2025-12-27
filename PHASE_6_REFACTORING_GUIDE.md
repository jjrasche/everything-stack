# Phase 6: Trainable Component Refactoring Guide

## Overview
Transition 9 trainable components from the old `services/trainable.dart` interface-based pattern to the new `lib/core/trainable.dart` mixin-based pattern.

## Old vs New Pattern

### Old Pattern (services/trainable.dart)
```dart
abstract class Trainable {
  Future<String> recordInvocation(dynamic invocation);
  Future<void> trainFromFeedback(String turnId, {String? userId});
  Future<Map<String, dynamic>> getAdaptationState({String? userId});
  Widget buildFeedbackUI(String invocationId);
}

class STTService extends StreamingService implements Trainable {
  @override
  Future<String> recordInvocation(dynamic invocation) async {
    // Manual implementation
  }

  @override
  Future<void> trainFromFeedback(String turnId, {String? userId}) async {
    // Manual stub - learning logic goes here
  }
}
```

### New Pattern (lib/core/trainable.dart)
```dart
// 1. Define adaptation data class
class STTAdaptationData extends AdaptationData {
  double confidenceThreshold = 0.65;
  int minFeedbackCount = 10;

  @override
  String toJson() => jsonEncode({
    'confidenceThreshold': confidenceThreshold,
    'minFeedbackCount': minFeedbackCount,
  });

  factory STTAdaptationData.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return STTAdaptationData()
      ..confidenceThreshold = map['confidenceThreshold'] as double? ?? 0.65
      ..minFeedbackCount = map['minFeedbackCount'] as int? ?? 10;
  }
}

// 2. Mix Trainable into service
class STTService extends StreamingService
    with Trainable<STTAdaptationData> {

  @override
  String get componentType => 'stt';

  @override
  STTAdaptationData createDefaultData() => STTAdaptationData();

  @override
  STTAdaptationData deserializeData(String json) =>
      STTAdaptationData.fromJson(json);

  Future<void> transcribe(...) async {
    // After transcription completes:
    await recordInvocation(correlationId, Invocation(
      correlationId: correlationId,
      componentType: componentType,
      success: true,
      confidence: 0.95,
      output: {'transcription': result},
    ));
  }
}
```

## Key Changes

### 1. Remove Interface Inheritance
**Before:**
```dart
class STTService extends StreamingService implements Trainable
```

**After:**
```dart
class STTService extends StreamingService with Trainable<STTAdaptationData>
```

### 2. Add Component-Specific AdaptationData
Create class in same file as service:
```dart
class STTAdaptationData extends AdaptationData {
  // Component-specific fields
  double confidenceThreshold = 0.65;
  int minFeedbackCount = 10;

  // Required: toJson() and fromJson()
}
```

### 3. Implement Abstract Properties
```dart
@override
String get componentType => 'stt';

@override
STTAdaptationData createDefaultData() => STTAdaptationData();

@override
STTAdaptationData deserializeData(String json) =>
    STTAdaptationData.fromJson(json);
```

### 4. Delete Manual recordInvocation Implementation
**Delete this:**
```dart
@override
Future<String> recordInvocation(dynamic invocation) async {
  if (invocation is! Invocation) throw ArgumentError(...);
  await _invocationRepository.save(invocation);
  return invocation.uuid;
}
```

**Use mixin implementation instead** - just call:
```dart
await recordInvocation(correlationId, Invocation(...));
```

### 5. Replace trainFromFeedback with Stub
**Delete the old TODO stub:**
```dart
@override
Future<void> trainFromFeedback(String turnId, {String? userId}) async {
  // TODO: Implement STT learning...
}
```

**Mixin provides stub automatically** - no manual override needed. The mixin's `trainFromFeedback()` is already a no-op placeholder.

### 6. Remove getAdaptationState and buildFeedbackUI
Delete the manual implementations - these are replaced by mixin methods that will be implemented later.

## Components to Refactor

1. **lib/services/stt_service.dart** (DeepgramSTTService)
   - Create STTAdaptationData class
   - Add: componentType = 'stt'
   - Delete: recordInvocation(), trainFromFeedback(), getAdaptationState(), buildFeedbackUI()

2. **lib/services/llm_service.dart** (ChatGPTLLMService or similar)
   - Create LLMAdaptationData class
   - Add: componentType = 'llm'
   - Delete old method implementations

3. **lib/services/tts_service.dart** (FlutterTTSService)
   - Create TTSAdaptationData class
   - Add: componentType = 'tts'
   - Delete old method implementations

4. **lib/services/trainables/namespace_selector.dart**
   - Create NamespaceSelectorData class
   - Add: componentType = 'namespace_selector'
   - Lines to delete: learning logic around line 115-167

5. **lib/services/trainables/tool_selector.dart**
   - Create ToolSelectorData class
   - Add: componentType = 'tool_selector'
   - Lines to delete: learning logic around line 93-149

6. **lib/services/trainables/context_injector.dart**
   - Create ContextInjectorData class
   - Add: componentType = 'context_injector'
   - Delete learning logic

7. **lib/services/trainables/llm_config_selector.dart**
   - Create LLMConfigSelectorData class
   - Add: componentType = 'llm_config_selector'
   - Lines to delete: learning logic around line 89-150

8. **lib/services/trainables/llm_orchestrator.dart**
   - Create LLMOrchestratorData class
   - Add: componentType = 'llm_orchestrator'
   - Lines to delete: learning logic around line 88-144

9. **lib/services/trainables/response_renderer.dart**
   - Create ResponseRendererData class
   - Add: componentType = 'response_renderer'
   - Lines to delete: learning logic around line 89-155

## Null Implementations

For NullSTTService, NullLLMService, etc., update to remove manual Trainable methods:
```dart
class NullSTTService extends STTService {
  // No need to override Trainable methods anymore
  // Just ensure componentType is set correctly
}
```

## Import Changes

Add to each refactored component:
```dart
import 'package:everything_stack_template/core/trainable.dart';
import 'package:everything_stack_template/core/adaptation_data.dart';
```

Remove or no longer need:
```dart
import 'trainable.dart';  // from services/
```

## Verification Checklist

After refactoring each component:
- [ ] Component extends/mixes Trainable<ComponentData>
- [ ] componentType property defined
- [ ] createDefaultData() implemented
- [ ] deserializeData() implemented
- [ ] No manual recordInvocation() method
- [ ] No manual trainFromFeedback() method (uses mixin stub)
- [ ] No manual getAdaptationState() method
- [ ] No manual buildFeedbackUI() method
- [ ] Component-specific AdaptationData class created
- [ ] Compilation succeeds

## Notes

- The mixin provides working implementations of recordInvocation() and trainFromFeedback()
- trainFromFeedback() is a stub that returns immediately - learning logic is deferred
- Each component's AdaptationData can be extended later as learning logic is designed
- The mixin handles repository access via GetIt, so components don't need to inject them manually
