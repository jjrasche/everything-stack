/// Text-to-token conversion interface.
/// Each SLM model needs a tokenizer. Different models use different
/// algorithms (SentencePiece unigram, WordPiece, BPE) behind this contract.
abstract class Tokenizer {
  /// Encode text to a list of integer token IDs.
  List<int> encode(String text);

  /// Decode token IDs back to text.
  String decode(List<int> tokenIds);

  /// Number of tokens in the vocabulary.
  int get vocabSize;

  /// Beginning-of-sequence token ID, or null if not applicable.
  int? get bosId;

  /// End-of-sequence token ID, or null if not applicable.
  int? get eosId;

  /// Padding token ID, or null if not applicable.
  int? get padId;

  /// Unknown token ID.
  int get unkId;
}
