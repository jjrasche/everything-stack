/// # Tokenizer Integration Test
///
/// Tests that TokenizerService correctly counts tokens in text.
/// This is essential for ContextCapacity to know when to truncate context.
///
/// Uses tiktoken tokenizer for GPT-4 compatible token counting.
///
/// ## Test Philosophy
/// These tests use EXACT assertions where possible. Tiktoken is deterministic -
/// the same text always produces the same tokens. We verify exact counts to
/// catch any tokenizer version changes or encoding issues.

import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/services/tokenizer_service.dart';
import 'package:get_it/get_it.dart';
import 'shared/test_harness.dart';

final tokenizerTest = IntegrationTestConfig(
  name: 'Tokenizer Service',

  repos: [],

  utterances: {},

  mockImplementers: {},

  testLogic: (t) async {
    print('\n=== TEST: Tokenizer Service ===');

    // ===== SETUP: Get TokenizerService =====
    print('\n[Setup] Getting TokenizerService...');
    final tokenizer = GetIt.instance<TokenizerService>();

    // ===== TEST 1: Basic token counting with EXACT assertion =====
    print('\n[Test 1] Basic token counting (exact)...');
    const basicText = 'Hello, world!';
    final basicCount = tokenizer.countTokens(basicText);
    print('   Text: "$basicText"');
    print('   Tokens: $basicCount');

    // "Hello, world!" is exactly 4 tokens with GPT-4o encoding:
    // "Hello" (1) + "," (1) + " world" (1) + "!" (1)
    expect(
      basicCount,
      equals(4),
      reason: '"Hello, world!" should be exactly 4 tokens with GPT-4o encoding',
    );

    // ===== TEST 2: Longer text with exact count =====
    print('\n[Test 2] Longer text token counting (exact)...');
    const longerText = 'The quick brown fox jumps over the lazy dog.';
    final longerCount = tokenizer.countTokens(longerText);
    print('   Text: "$longerText"');
    print('   Tokens: $longerCount');

    // This pangram is exactly 10 tokens with GPT-4o encoding
    expect(
      longerCount,
      equals(10),
      reason: 'Pangram should be exactly 10 tokens',
    );

    // ===== TEST 3: Empty text =====
    print('\n[Test 3] Empty text...');
    final emptyCount = tokenizer.countTokens('');
    print('   Empty text tokens: $emptyCount');

    expect(
      emptyCount,
      equals(0),
      reason: 'Empty text MUST be exactly 0 tokens',
    );

    // ===== TEST 4: Consistency (determinism) =====
    print('\n[Test 4] Consistency check (10 iterations)...');
    final counts = <int>[];
    for (var i = 0; i < 10; i++) {
      counts.add(tokenizer.countTokens(basicText));
    }
    print('   10 counts: $counts');

    expect(
      counts.toSet().length,
      equals(1),
      reason: 'All 10 counts MUST be identical (deterministic)',
    );
    expect(
      counts.first,
      equals(4),
      reason: 'All counts should be 4',
    );

    // ===== TEST 5: Encode/Decode roundtrip =====
    print('\n[Test 5] Encode/Decode roundtrip...');
    const roundtripText = 'Testing encode and decode roundtrip.';
    final encoded = tokenizer.encode(roundtripText);
    final decoded = tokenizer.decode(encoded);
    print('   Original: "$roundtripText"');
    print('   Encoded: ${encoded.length} tokens');
    print('   Decoded: "$decoded"');

    expect(
      decoded,
      equals(roundtripText),
      reason: 'Decode(Encode(text)) MUST equal original text exactly',
    );
    expect(
      encoded.length,
      equals(tokenizer.countTokens(roundtripText)),
      reason: 'encode().length MUST equal countTokens()',
    );

    // ===== TEST 6: truncateToTokens - CRITICAL for ContextCapacity =====
    print('\n[Test 6] truncateToTokens (critical for ContextCapacity)...');
    const longText = 'This is a longer sentence that we will truncate to a smaller number of tokens for testing purposes.';
    final originalTokens = tokenizer.countTokens(longText);
    print('   Original text: ${longText.length} chars, $originalTokens tokens');

    // Truncate to 5 tokens
    const maxTokens = 5;
    final truncated = tokenizer.truncateToTokens(longText, maxTokens);
    final truncatedTokens = tokenizer.countTokens(truncated);
    print('   Truncated to $maxTokens tokens: "$truncated"');
    print('   Actual tokens after truncation: $truncatedTokens');

    expect(
      truncatedTokens,
      lessThanOrEqualTo(maxTokens),
      reason: 'Truncated text MUST have <= maxTokens tokens',
    );
    expect(
      truncatedTokens,
      equals(maxTokens),
      reason: 'Truncation should produce exactly maxTokens when input is longer',
    );
    expect(
      truncated.length,
      lessThan(longText.length),
      reason: 'Truncated text MUST be shorter than original',
    );

    // Verify truncated text is a prefix of original
    expect(
      longText.startsWith(truncated),
      isTrue,
      reason: 'Truncated text MUST be a prefix of original',
    );

    // ===== TEST 7: truncateToTokens edge cases =====
    print('\n[Test 7] truncateToTokens edge cases...');

    // 7a: Empty input
    final truncatedEmpty = tokenizer.truncateToTokens('', 10);
    expect(
      truncatedEmpty,
      equals(''),
      reason: 'Truncating empty string MUST return empty string',
    );

    // 7b: maxTokens = 0
    final truncatedZero = tokenizer.truncateToTokens(longText, 0);
    expect(
      truncatedZero,
      equals(''),
      reason: 'Truncating to 0 tokens MUST return empty string',
    );

    // 7c: maxTokens < 0
    final truncatedNegative = tokenizer.truncateToTokens(longText, -5);
    expect(
      truncatedNegative,
      equals(''),
      reason: 'Truncating to negative tokens MUST return empty string',
    );

    // 7d: maxTokens > actual tokens (no truncation needed)
    final truncatedNoOp = tokenizer.truncateToTokens(basicText, 100);
    expect(
      truncatedNoOp,
      equals(basicText),
      reason: 'When maxTokens > actual, MUST return original text unchanged',
    );

    print('   All edge cases passed');

    // ===== TEST 8: Unicode and emoji handling =====
    print('\n[Test 8] Unicode and emoji handling...');
    const emojiText = 'Hello 👋 world 🌍!';
    final emojiCount = tokenizer.countTokens(emojiText);
    print('   Text: "$emojiText"');
    print('   Tokens: $emojiCount');

    // Emojis typically take 1-3 tokens each
    expect(
      emojiCount,
      greaterThan(0),
      reason: 'Emoji text must have positive token count',
    );
    expect(
      emojiCount,
      greaterThan(tokenizer.countTokens('Hello world!')),
      reason: 'Text with emojis should have MORE tokens than without',
    );

    // Verify encode/decode preserves emojis
    final emojiEncoded = tokenizer.encode(emojiText);
    final emojiDecoded = tokenizer.decode(emojiEncoded);
    expect(
      emojiDecoded,
      equals(emojiText),
      reason: 'Emoji roundtrip MUST preserve characters exactly',
    );

    // ===== TEST 9: Code snippet tokenization =====
    print('\n[Test 9] Code snippet tokenization...');
    const codeSnippet = '''
def hello():
    print("Hello, world!")
''';
    final codeCount = tokenizer.countTokens(codeSnippet);
    print('   Code: ${codeSnippet.length} chars');
    print('   Tokens: $codeCount');

    // Code typically has more tokens per character due to special chars
    final codeRatio = codeSnippet.length / codeCount;
    print('   Chars per token: ${codeRatio.toStringAsFixed(2)}');

    expect(
      codeCount,
      greaterThan(0),
      reason: 'Code snippet must have positive token count',
    );

    // Verify roundtrip preserves code exactly (whitespace-sensitive)
    final codeEncoded = tokenizer.encode(codeSnippet);
    final codeDecoded = tokenizer.decode(codeEncoded);
    expect(
      codeDecoded,
      equals(codeSnippet),
      reason: 'Code roundtrip MUST preserve whitespace and formatting exactly',
    );

    // ===== TEST 10: Multi-byte UTF-8 characters =====
    print('\n[Test 10] Multi-byte UTF-8 characters...');
    const utf8Text = '日本語テスト';  // Japanese text
    final utf8Count = tokenizer.countTokens(utf8Text);
    print('   Text: "$utf8Text"');
    print('   Tokens: $utf8Count');

    expect(
      utf8Count,
      greaterThan(0),
      reason: 'Japanese text must have positive token count',
    );

    // Roundtrip must preserve
    final utf8Encoded = tokenizer.encode(utf8Text);
    final utf8Decoded = tokenizer.decode(utf8Encoded);
    expect(
      utf8Decoded,
      equals(utf8Text),
      reason: 'Japanese text roundtrip MUST preserve characters exactly',
    );

    print('\n=== Tokenizer Test PASSED (10 test cases) ===');
  },
);
