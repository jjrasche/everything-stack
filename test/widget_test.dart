/// Widget tests for Everything Stack application UI.
///
/// Tests verify that the application loads and renders correctly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:everything_stack_template/main.dart';

void main() {
  testWidgets('App loads without crashing', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the app contains a MaterialApp.
    expect(find.byType(MaterialApp), findsWidgets);

    // Verify that app title is set correctly.
    final MaterialApp app =
        find.byType(MaterialApp).evaluate().first.widget as MaterialApp;
    expect(app.title, 'Everything Stack Demo');
  });
}
