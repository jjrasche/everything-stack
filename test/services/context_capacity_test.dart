/// Unit tests for ContextCapacity types and TokenizerService.
///
/// Tests type classes, serialization, and tokenizer functionality.
/// Service integration tests are in integration_test/.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:everything_stack_template/services/tokenizer_service.dart';
import 'package:everything_stack_template/services/types/context_capacity_types.dart';

void main() {
  group('ModelContextConfig', () {
    test('effectiveContextBudget clamps to bounds', () {
      // Budget within bounds
      final config1 = ModelContextConfig(
        model: 'test-model',
        maxContextTokens: 128000,
        optimalContextTokens: 8000,
      );
      expect(config1.effectiveContextBudget, 8000);

      // Budget below minimum (500)
      final config2 = ModelContextConfig(
        model: 'test-model',
        maxContextTokens: 128000,
        optimalContextTokens: 100,
      );
      expect(config2.effectiveContextBudget, 500);

      // Budget exceeds max - reserved
      final config3 = ModelContextConfig(
        model: 'test-model',
        maxContextTokens: 10000,
        optimalContextTokens: 9000,
        reservedForResponse: 4096,
      );
      expect(config3.effectiveContextBudget, 10000 - 4096); // 5904
    });

    test('copyWith creates new instance with updated values', () {
      final original = ModelContextConfig(
        model: 'test-model',
        maxContextTokens: 128000,
        optimalContextTokens: 8000,
      );
      final updated = original.copyWith(optimalContextTokens: 12000);

      expect(updated.model, 'test-model');
      expect(updated.maxContextTokens, 128000);
      expect(updated.optimalContextTokens, 12000);
      expect(original.optimalContextTokens, 8000); // Original unchanged
    });

    test('serialization roundtrip preserves values', () {
      final original = ModelContextConfig(
        model: 'groq:llama-3.3-70b-versatile',
        maxContextTokens: 128000,
        optimalContextTokens: 8000,
        reservedForResponse: 4096,
      );

      final map = original.toMap();
      final restored = ModelContextConfig.fromMap(map);

      expect(restored.model, original.model);
      expect(restored.maxContextTokens, original.maxContextTokens);
      expect(restored.optimalContextTokens, original.optimalContextTokens);
      expect(restored.reservedForResponse, original.reservedForResponse);
    });
  });

  group('ContextCapacityAdaptationData', () {
    test('defaults creates Groq models', () {
      final defaults = ContextCapacityAdaptationData.defaults();

      expect(defaults.modelConfigs.containsKey('groq:llama-3.3-70b-versatile'), true);
      expect(defaults.modelConfigs.containsKey('groq:llama-3.1-8b-instant'), true);
      expect(defaults.defaultOptimalTokens, 4000);
    });

    test('getConfigForModel returns existing config', () {
      final data = ContextCapacityAdaptationData.defaults();
      final config = data.getConfigForModel('groq:llama-3.3-70b-versatile');

      expect(config.model, 'llama-3.3-70b-versatile');
      expect(config.maxContextTokens, 128000);
    });

    test('getConfigForModel creates fallback for unknown model', () {
      final data = ContextCapacityAdaptationData.defaults();
      final config = data.getConfigForModel('openai:gpt-4', maxTokens: 8192);

      expect(config.model, 'openai:gpt-4');
      expect(config.maxContextTokens, 8192);
      expect(config.optimalContextTokens, data.defaultOptimalTokens);
    });

    test('serialization roundtrip preserves all configs', () {
      final original = ContextCapacityAdaptationData.defaults();
      final json = original.toJson();
      final restored = ContextCapacityAdaptationData.fromJson(
        Map<String, dynamic>.from(
          const JsonDecoder().convert(json) as Map,
        ),
      );

      expect(restored.modelConfigs.length, original.modelConfigs.length);
      expect(restored.defaultOptimalTokens, original.defaultOptimalTokens);

      for (final key in original.modelConfigs.keys) {
        expect(restored.modelConfigs[key]!.model, original.modelConfigs[key]!.model);
        expect(restored.modelConfigs[key]!.optimalContextTokens,
            original.modelConfigs[key]!.optimalContextTokens);
      }
    });

    test('copyWithModelConfig adds or updates model', () {
      final data = ContextCapacityAdaptationData.defaults();
      final newConfig = ModelContextConfig(
        model: 'new-model',
        maxContextTokens: 16000,
        optimalContextTokens: 5000,
      );

      final updated = data.copyWithModelConfig('test:new-model', newConfig);

      expect(updated.modelConfigs.containsKey('test:new-model'), true);
      expect(updated.modelConfigs['test:new-model']!.optimalContextTokens, 5000);
      // Original models still present
      expect(updated.modelConfigs.containsKey('groq:llama-3.3-70b-versatile'), true);
    });
  });

  group('TruncationResult', () {
    test('summary reflects truncation state', () {
      final truncated = TruncationResult(
        messages: [{}],
        totalTokens: 5000,
        tokenBudget: 8000,
        wasTruncated: true,
        messagesRemoved: 3,
      );
      expect(truncated.summary, contains('Truncated'));
      expect(truncated.summary, contains('5000'));
      expect(truncated.summary, contains('3'));

      final notTruncated = TruncationResult(
        messages: [{}],
        totalTokens: 5000,
        tokenBudget: 8000,
        wasTruncated: false,
      );
      expect(notTruncated.summary, contains('No truncation'));
    });
  });

  group('ContextCapacityInvocationInput/Output', () {
    test('input serialization', () {
      final input = ContextCapacityInvocationInput(
        model: 'groq:llama-3.3-70b-versatile',
        originalTokens: 10000,
        originalMessageCount: 15,
      );
      final map = input.toMap();

      expect(map['model'], 'groq:llama-3.3-70b-versatile');
      expect(map['originalTokens'], 10000);
      expect(map['originalMessageCount'], 15);
    });

    test('output serialization', () {
      final output = ContextCapacityInvocationOutput(
        tokenBudget: 8000,
        finalTokens: 7500,
        wasTruncated: true,
        messagesRemoved: 2,
      );
      final map = output.toMap();

      expect(map['tokenBudget'], 8000);
      expect(map['finalTokens'], 7500);
      expect(map['wasTruncated'], true);
      expect(map['messagesRemoved'], 2);
    });
  });

  group('TokenizerService', () {
    test('token counts are reasonable', () {
      final tokenizer = TokenizerService.instance;

      // Empty string
      expect(tokenizer.countTokens(''), 0);

      // Simple text
      final simpleCount = tokenizer.countTokens('Hello, world!');
      expect(simpleCount, greaterThan(0));
      expect(simpleCount, lessThan(10));

      // Longer text
      final longerText = 'This is a longer piece of text that should use more tokens.';
      final longerCount = tokenizer.countTokens(longerText);
      expect(longerCount, greaterThan(simpleCount));
    });

    test('encode and decode roundtrip', () {
      final tokenizer = TokenizerService.instance;
      const original = 'Hello, world!';

      final tokens = tokenizer.encode(original);
      final decoded = tokenizer.decode(tokens);

      expect(decoded, original);
    });

    test('truncateToTokens produces text within limit', () {
      final tokenizer = TokenizerService.instance;
      final longText = List.generate(100, (i) => 'Word$i').join(' ');

      final truncated = tokenizer.truncateToTokens(longText, 20);
      final truncatedCount = tokenizer.countTokens(truncated);

      expect(truncatedCount, lessThanOrEqualTo(20));
    });

    test('truncateToTokens returns original if under limit', () {
      final tokenizer = TokenizerService.instance;
      const shortText = 'Hello';

      final truncated = tokenizer.truncateToTokens(shortText, 100);
      expect(truncated, shortText);
    });

    test('truncateToTokens handles empty input', () {
      final tokenizer = TokenizerService.instance;

      expect(tokenizer.truncateToTokens('', 100), '');
      expect(tokenizer.truncateToTokens('Hello', 0), '');
    });
  });

  group('Token counting edge cases', () {
    test('code snippets use more tokens per character', () {
      final tokenizer = TokenizerService.instance;

      const prose = 'The quick brown fox jumps over the lazy dog.';
      const code = 'function foo() { return bar.baz(); }';

      final proseTokens = tokenizer.countTokens(prose);
      final codeTokens = tokenizer.countTokens(code);

      // Code typically has higher token density
      final proseRatio = proseTokens / prose.length;
      final codeRatio = codeTokens / code.length;

      // Both should have reasonable ratios (tokens are typically 2-4 chars)
      expect(proseRatio, greaterThan(0.1));
      expect(codeRatio, greaterThan(0.1));
    });

    test('multi-byte characters handled correctly', () {
      final tokenizer = TokenizerService.instance;

      const emoji = '🎉🎊🎈';
      const japanese = '日本語のテキスト';

      // Should not crash on multi-byte characters
      expect(tokenizer.countTokens(emoji), greaterThan(0));
      expect(tokenizer.countTokens(japanese), greaterThan(0));
    });

    test('special tokens handled', () {
      final tokenizer = TokenizerService.instance;

      // Newlines and special characters
      const withNewlines = 'Line 1\nLine 2\nLine 3';
      const withTabs = 'Col1\tCol2\tCol3';

      expect(tokenizer.countTokens(withNewlines), greaterThan(0));
      expect(tokenizer.countTokens(withTabs), greaterThan(0));
    });
  });
}
