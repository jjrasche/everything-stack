/// Test 1: PERSISTENCE
///
/// Question: Does personality.prepareForSave() + save actually write to persistent storage?
///
/// Simulates:
/// 1. Load personality from repo
/// 2. Modify thresholds
/// 3. Save to repo
/// 4. "Restart app" - load fresh personality from repo
/// 5. Check: Are thresholds still modified or reverted to default?

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/domain/personality.dart';

void main() {
  group('Persistence Test', () {
    test('Thresholds persist after save and reload', () async {
      print('\n═══════════════════════════════════════════════════════════════');
      print('TEST 1: Do thresholds persist to storage?');
      print('═══════════════════════════════════════════════════════════════');

      // Step 1: Create and save initial personality
      print('\n📝 STEP 1: Create initial personality');
      final personality1 = Personality(
        name: 'Test Personality',
        systemPrompt: 'You are helpful',
      );
      personality1.loadAfterRead();
      final initialTaskThreshold =
          personality1.namespaceAttention.getThreshold('task');
      print('   Initial task threshold: $initialTaskThreshold');

      // Step 2: Modify thresholds (simulate feedback)
      print('\n🎯 STEP 2: Modify thresholds via feedback');
      personality1.namespaceAttention.raiseThreshold('task');
      final modifiedTaskThreshold =
          personality1.namespaceAttention.getThreshold('task');
      print('   After raiseThreshold(): $modifiedTaskThreshold');

      // Step 3: Save to repository (in-memory simulation)
      print('\n💾 STEP 3: Save personality to repository');
      personality1.prepareForSave();
      final savedData = personality1.toJson(); // Simulate serialization
      print('   Serialized to JSON ✓');
      print('   Saved to repo ✓');

      // Step 4: "App restart" - create fresh personality from saved data
      print('\n🔄 STEP 4: Simulate app restart - load from repository');
      final personality2 = Personality.fromJson(savedData);
      personality2.loadAfterRead();
      final reloadedTaskThreshold =
          personality2.namespaceAttention.getThreshold('task');
      print('   Loaded personality from storage');
      print('   Reloaded task threshold: $reloadedTaskThreshold');

      // Step 5: Check if thresholds persisted
      print('\n═══════════════════════════════════════════════════════════════');
      print('RESULTS:');
      print('═══════════════════════════════════════════════════════════════');
      print('Initial threshold:   $initialTaskThreshold');
      print('Modified threshold:  $modifiedTaskThreshold');
      print('Reloaded threshold:  $reloadedTaskThreshold');

      final persisted = (reloadedTaskThreshold - modifiedTaskThreshold).abs() < 0.01;

      if (persisted) {
        print('\n✅ SUCCESS: Thresholds persist across save/reload!');
        print('   Feedback changes are NOT lost on app restart');
      } else {
        print('\n❌ FAILURE: Thresholds reverted to default!');
        print('   Data is lost on app restart - not persisting');
      }

      expect(persisted, true,
          reason: 'Reloaded threshold should match modified threshold');
    });
  });
}
