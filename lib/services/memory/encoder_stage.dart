/// Type contract for encoder pipeline stages.
/// Each stage transforms input to output with a named identity.
abstract class EncoderStage<TIn, TOut> {
  String get stageName;
  Future<TOut> process(TIn input);
}
