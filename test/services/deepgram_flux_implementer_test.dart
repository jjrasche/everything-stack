/// # DeepgramFluxImplementer TurnInfo Handling Tests
///
/// Tests that verify the real DeepgramFluxImplementer code handles
/// TurnInfo messages correctly.
///
/// CRITICAL for continuous conversation mode:
/// - EndOfTurn events MUST be processed even with empty transcript
/// - Without this, `end_of_turn` event is never published
/// - UI's `_isListening` stays true → auto-restart never triggers

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeepgramFluxImplementer TurnInfo handling', () {
    late String implementerCode;

    setUpAll(() {
      final file = File('lib/services/implementations/deepgram_flux_implementer.dart');
      implementerCode = file.readAsStringSync();
    });

    test('Empty transcript must NOT skip EndOfTurn event handling', () {
      // The bug was: `if (transcript.isEmpty) return;`
      // This skipped ALL processing, including EndOfTurn event handling.
      //
      // The fix is: only skip STORAGE for empty transcripts, not event handling
      // `if (transcript.isNotEmpty) { _partialTranscripts.add(...) }`

      // Check for the BUGGY pattern (should NOT exist)
      final hasBuggyPattern = RegExp(
        r'if\s*\(\s*transcript\.isEmpty\s*\)\s*return\s*;',
      ).hasMatch(implementerCode);

      expect(
        hasBuggyPattern,
        isFalse,
        reason: '''
BUG DETECTED: `if (transcript.isEmpty) return;`

This skips EndOfTurn event handling when Deepgram sends EndOfTurn
with empty transcript (final text was in previous Update message).

Result: end_of_turn event never published → continuous mode broken.

Fix: Change to conditional storage only:
  if (transcript.isNotEmpty) {
    _partialTranscripts.add(transcript);
  }
  // Event handling continues...
''',
      );
    });

    test('EndOfTurn event triggers _handleEndOfTurn()', () {
      // Verify the code calls _handleEndOfTurn when event is EndOfTurn
      final handlesEndOfTurn = implementerCode.contains("event == 'EndOfTurn'") &&
          implementerCode.contains('_handleEndOfTurn');

      expect(
        handlesEndOfTurn,
        isTrue,
        reason: 'Code must call _handleEndOfTurn() when event is EndOfTurn',
      );
    });

    test('_handleEndOfTurn publishes end_of_turn event', () {
      // Verify _handleEndOfTurn publishes the event to EventBus
      final publishesEvent = implementerCode.contains("eventType: 'end_of_turn'");

      expect(
        publishesEvent,
        isTrue,
        reason: '_handleEndOfTurn must publish end_of_turn event to EventBus',
      );
    });

    test('StartOfTurn event publishes start_of_turn for barge-in', () {
      // Verify StartOfTurn detection works for barge-in
      final handlesStartOfTurn = implementerCode.contains("event == 'StartOfTurn'") ||
          implementerCode.contains("eventType: 'start_of_turn'");

      expect(
        handlesStartOfTurn,
        isTrue,
        reason: 'Code must handle StartOfTurn events for barge-in detection',
      );
    });
  });
}
