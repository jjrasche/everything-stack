/// # TokenizerService
///
/// ## What it does
/// Provides accurate token counting for GPT-4/o1 models.
/// Used by ContextCapacity to know when to truncate context.
///
/// ## Why tiktoken?
/// Character-based estimation (chars/4) is inaccurate for:
/// - Code snippets (more tokens per char)
/// - Multi-byte characters (fewer tokens per char)
/// - Special tokens (exact mapping required)
///
/// tiktoken provides exact BPE tokenization matching OpenAI's API.
///
/// ## Usage
/// ```dart
/// final tokenizer = TokenizerService.instance;
/// final tokens = tokenizer.countTokens(text);
/// print('Text uses $tokens tokens');
/// ```

import 'dart:typed_data';
import 'package:tiktoken_tokenizer_gpt4o_o1/tiktoken_tokenizer_gpt4o_o1.dart';

/// Service for counting tokens in text using tiktoken.
///
/// This is a singleton service - use [TokenizerService.instance] or
/// register in GetIt and retrieve via dependency injection.
class TokenizerService {
  /// Singleton instance
  static final TokenizerService instance = TokenizerService._();

  /// Internal tiktoken tokenizer
  late final Tiktoken _tiktoken;

  /// Private constructor - initializes tiktoken
  TokenizerService._() {
    // Initialize with GPT-4o model encoding
    // This is compatible with: GPT-4, GPT-4o, GPT-4o-mini, o1, o1-mini
    _tiktoken = Tiktoken(OpenAiModel.gpt_4o);
  }

  /// Count the number of tokens in a text string.
  ///
  /// Uses BPE tokenization matching OpenAI's API.
  /// Returns 0 for empty or null-like input.
  ///
  /// Example:
  /// ```dart
  /// final tokens = tokenizer.countTokens('Hello, world!');
  /// // Returns ~4 tokens
  /// ```
  int countTokens(String text) {
    if (text.isEmpty) return 0;

    try {
      return _tiktoken.count(text);
    } catch (e) {
      // Fallback to rough estimation if tokenization fails
      // This should rarely happen with tiktoken
      print('⚠️ [TokenizerService] Tokenization failed, using estimation: $e');
      return (text.length / 4).round();
    }
  }

  /// Encode text to token IDs.
  ///
  /// Returns the actual token IDs (integers) for the text.
  /// Useful for advanced use cases like token manipulation.
  Uint32List encode(String text) {
    if (text.isEmpty) return Uint32List(0);
    return _tiktoken.encode(text);
  }

  /// Decode token IDs back to text.
  ///
  /// Reverses the encoding process.
  String decode(Uint32List tokens) {
    if (tokens.isEmpty) return '';
    return _tiktoken.decode(tokens);
  }

  /// Truncate text to a maximum number of tokens.
  ///
  /// Useful for ensuring text fits within a token budget.
  /// Returns the truncated text that uses at most [maxTokens] tokens.
  String truncateToTokens(String text, int maxTokens) {
    if (text.isEmpty || maxTokens <= 0) return '';

    final tokens = encode(text);
    if (tokens.length <= maxTokens) return text;

    // Truncate tokens and decode
    final truncatedTokens = Uint32List.sublistView(tokens, 0, maxTokens);
    return decode(truncatedTokens);
  }
}
