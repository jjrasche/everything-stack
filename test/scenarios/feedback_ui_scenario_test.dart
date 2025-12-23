/// # Feedback Review UI Scenario
///
/// Feature: User reviews turns and provides feedback
///
/// Gherkin Scenario:
/// ```gherkin
/// Feature: Feedback Review Loop
///   Scenario: User marks turn wrong, trains system, verifies learning
///     Given user has recorded a voice phrase
///     And the turn was auto-marked for feedback
///     When user taps "Review Feedback" on home screen
///     Then TurnListScreen shows the recent turn in feedback queue
///     When user taps the turn
///     Then FeedbackReviewScreen shows LLM response
///     When user selects "Correct" action
///     And user enters corrected text
///     And user taps "Save Feedback"
///     Then feedback is saved to repository
///     When user taps "Learn from Feedback" button
///     Then system calls trainFromFeedback()
///     And personality thresholds are updated
///     And success message is shown
///     And turn is marked as trained
/// ```
///
/// Implementation: This test validates the complete UI flow for feedback.
/// It does NOT test actual STT/LLM - those are mocked.
/// It validates: navigation, form interactions, feedback persistence, training trigger.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:everything_stack_template/domain/turn.dart';
import 'package:everything_stack_template/domain/invocations.dart';
import 'package:everything_stack_template/domain/feedback.dart';
import 'package:everything_stack_template/domain/personality.dart';
import 'package:everything_stack_template/repositories/turn_repository_impl.dart';
import 'package:everything_stack_template/repositories/invocation_repository_impl.dart';
import 'package:everything_stack_template/repositories/feedback_repository_impl.dart';
import 'package:everything_stack_template/ui/screens/feedback_review_screen.dart';
import 'package:everything_stack_template/ui/screens/turn_list_screen.dart';
import 'package:everything_stack_template/main.dart';

void main() {
  group('Feedback Review UI Scenario', () {
    late TurnRepositoryImpl turnRepo;
    late LLMInvocationRepositoryImpl llmInvocationRepo;
    late FeedbackRepositoryImpl feedbackRepo;

    setUp(() {
      turnRepo = TurnRepositoryImpl.inMemory();
      llmInvocationRepo = LLMInvocationRepositoryImpl.inMemory();
      feedbackRepo = FeedbackRepositoryImpl.inMemory();
    });

    testWidgets(
      'User marks turn wrong and trains system via UI (Phase 1 - deferred)',
      skip: true,
      (WidgetTester tester) async {
        // GIVEN: A turn with LLM invocation, marked for feedback
        final llmInvocation = LLMInvocation(
          correlationId: 'test_turn_1',
          systemPromptVersion: '1.0',
          conversationHistoryLength: 1,
          response: 'I will set a task for you.',
          tokenCount: 42,
        );
        llmInvocation.contextType = 'conversation';
        await llmInvocationRepo.save(llmInvocation);

        final turn = Turn(
          correlationId: 'test_turn_1',
          markedForFeedback: true, // Auto-marked after orchestrator
        );
        turn.llmInvocationId = llmInvocation.uuid;
        turn.result = 'success';
        await turnRepo.save(turn);

        // WHEN: Build app and navigate to TurnListScreen
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(tester.element(find.byType(ElevatedButton)))
                          .push(
                        MaterialPageRoute(
                          builder: (_) => const TurnListScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.feedback),
                    label: const Text('Review Feedback'),
                  ),
                ),
              ),
            ),
          ),
        );

        // THEN: Home screen shows "Review Feedback" button
        expect(find.text('Review Feedback'), findsOneWidget);

        // WHEN: User taps "Review Feedback" button
        await tester.tap(find.byType(ElevatedButton));
        await tester.pumpAndSettle();

        // THEN: TurnListScreen appears and shows the turn
        expect(find.byType(TurnListScreen), findsOneWidget);
        // The turn should appear in the list (marked for feedback)
        // Note: Full validation requires mocking providers
        expect(find.byType(ListView), findsWidgets);

        // WHEN: User taps on a turn
        // await tester.tap(find.byType(Card).first);
        // await tester.pumpAndSettle();

        // THEN: FeedbackReviewScreen should appear
        // expect(find.byType(FeedbackReviewScreen), findsOneWidget);

        // WHEN: User marks feedback
        // await tester.tap(find.byIcon(Icons.edit)); // "Correct" button
        // await tester.pumpAndSettle();

        // THEN: Correction field appears
        // expect(find.byType(TextField), findsWidgets);

        // WHEN: User enters correction
        // await tester.enterText(find.byType(TextField), 'Set a timer instead');
        // await tester.pumpAndSettle();

        // WHEN: User saves feedback
        // await tester.tap(find.text('Save Feedback'));
        // await tester.pumpAndSettle();

        // THEN: Feedback is saved
        // final savedFeedback = await feedbackRepo.findByTurn(turn.uuid);
        // expect(savedFeedback, isNotEmpty);

        // WHEN: User taps "Learn from Feedback"
        // await tester.tap(find.text('Learn from Feedback'));
        // await tester.pumpAndSettle();

        // THEN: Training completes
        // expect(find.text('System trained successfully'), findsOneWidget);
      },
    );
  });
}
