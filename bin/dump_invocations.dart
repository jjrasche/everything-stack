#!/usr/bin/env dart
// Utility to dump invocations from ObjectBox database
// Run with: dart bin/dump_invocations.dart

import 'dart:convert';
import 'package:everything_stack_template/core/invocation_repository.dart';
import 'package:everything_stack_template/domain/invocation.dart';
import 'package:get_it/get_it.dart';
import 'package:objectbox/objectbox.dart';

void main() async {
  print('🔍 Querying ObjectBox Invocation Database...\n');

  // Initialize ObjectBox the same way the app does
  final store = await openStore();

  try {
    final invocationBox = store.box<Invocation>();
    final allInvocations = invocationBox.getAll();

    print('📊 Total invocations in database: ${allInvocations.length}\n');

    // Group by correlationId (most recent first)
    final grouped = <String, List<Invocation>>{};
    for (final inv in allInvocations) {
      grouped.putIfAbsent(inv.correlationId, () => []).add(inv);
    }

    // Sort groups by most recent
    final sortedGroups = grouped.entries.toList()
      ..sort((a, b) => b.value.first.createdAt.compareTo(a.value.first.createdAt));

    // Show top 3 correlation groups
    for (var i = 0; i < (sortedGroups.length > 3 ? 3 : sortedGroups.length); i++) {
      final entry = sortedGroups[i];
      final correlationId = entry.key;
      final invs = entry.value;

      print('═' * 100);
      print('Correlation ID: $correlationId');
      print('Invocation Count: ${invs.length}');
      print('═' * 100);

      // Sort by component order
      final componentOrder = {
        'namespace_selector': 1,
        'tool_selector': 2,
        'context_injector': 3,
        'llm_config_selector': 4,
        'llm_orchestrator': 5,
        'response_renderer': 6,
        'tts': 7,
      };

      invs.sort((a, b) {
        final orderA = componentOrder[a.componentType] ?? 999;
        final orderB = componentOrder[b.componentType] ?? 999;
        return orderA.compareTo(orderB);
      });

      for (final inv in invs) {
        print('\n📋 Component: ${inv.componentType}');
        print('   Success: ${inv.success}');
        print('   Confidence: ${inv.confidence}');
        print('   Created: ${inv.createdAt}');

        if (inv.input != null && inv.input!.isNotEmpty) {
          print('   INPUT:');
          print('   ${const JsonEncoder.withIndent('     ').convert(inv.input)}');
        } else {
          print('   INPUT: (empty)');
        }

        if (inv.output != null && inv.output!.isNotEmpty) {
          print('   OUTPUT:');
          print('   ${const JsonEncoder.withIndent('     ').convert(inv.output)}');
        } else {
          print('   OUTPUT: (empty)');
        }

        if (inv.metadata != null && inv.metadata!.isNotEmpty) {
          print('   METADATA:');
          print('   ${const JsonEncoder.withIndent('     ').convert(inv.metadata)}');
        }
      }
    }

    // Summary statistics
    print('\n${'═' * 100}');
    print('📈 COMPONENT STATISTICS');
    print('═' * 100);

    final componentCounts = <String, int>{};
    for (final inv in allInvocations) {
      componentCounts[inv.componentType] = (componentCounts[inv.componentType] ?? 0) + 1;
    }

    final sortedComponents = componentCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (final entry in sortedComponents) {
      print('${entry.key}: ${entry.value} invocations');
    }

    print('\n✅ Query complete\n');
  } finally {
    store.close();
  }
}
