/// ## Why semantic chunking?
/// Use case alignment: unstructured, rambling content without clear boundaries.
/// Research-backed: 70% retrieval improvement over recursive for unstructured text.
/// Reuses existing EmbeddingService infrastructure.
///
/// ## Why two-level chunking?
/// Parent level detects major topic shifts; child level provides precise
/// semantic units within parent chunks. Enables both broad and fine-grained retrieval.
library chunking;

export 'chunk.dart';
export 'chunking_config.dart';
export 'chunking_strategy.dart';
export 'semantic_chunker.dart';
export 'sentence_splitter.dart';
