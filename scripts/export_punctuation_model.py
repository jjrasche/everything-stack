"""Export the punctuation model's SentencePiece vocabulary to JSON
and optionally quantize the ONNX model to INT8.

Usage:
  pip install sentencepiece onnx onnxruntime
  python scripts/export_punctuation_model.py

Downloads from HuggingFace:
  1-800-BAD-CODE/punctuation_fullstop_truecase_english

Outputs:
  assets/models/punctuation_sp_vocab.json  — SentencePiece vocabulary for Dart tokenizer
  assets/models/punctuation_en.onnx        — Original FP32 model (copied)
  assets/models/punctuation_en_int8.onnx   — INT8 quantized model
"""

import json
import os
import shutil

from huggingface_hub import hf_hub_download
import sentencepiece as spm


REPO_ID = "1-800-BAD-CODE/punctuation_fullstop_truecase_english"
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "models")


def download_model_files():
    """Download ONNX model and SentencePiece model from HuggingFace."""
    onnx_path = hf_hub_download(REPO_ID, "punct_cap_seg_en.onnx")
    sp_path = hf_hub_download(REPO_ID, "spe_32k_lc_en.model")
    return onnx_path, sp_path


def export_vocab(sp_path: str, output_path: str):
    """Export SentencePiece vocabulary and scores to JSON for Dart tokenizer."""
    sp = spm.SentencePieceProcessor()
    sp.Load(sp_path)

    pieces = []
    for i in range(sp.GetPieceSize()):
        piece = sp.IdToPiece(i)
        score = sp.GetScore(i)
        pieces.append([piece, score])

    vocab = {
        "pieces": pieces,
        "unkId": sp.unk_id(),
        "bosId": sp.bos_id(),
        "eosId": sp.eos_id(),
        "padId": sp.pad_id() if sp.pad_id() >= 0 else None,
    }

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False, indent=2)

    print(f"Exported {sp.GetPieceSize()} pieces to {output_path}")
    return vocab


def quantize_model(onnx_path: str, output_path: str):
    """Quantize ONNX model to INT8 dynamic quantization."""
    try:
        from onnxruntime.quantization import quantize_dynamic, QuantType

        quantize_dynamic(
            model_input=onnx_path,
            model_output=output_path,
            weight_type=QuantType.QInt8,
        )
        original_mb = os.path.getsize(onnx_path) / (1024 * 1024)
        quantized_mb = os.path.getsize(output_path) / (1024 * 1024)
        print(f"Quantized: {original_mb:.1f}MB -> {quantized_mb:.1f}MB")
    except ImportError:
        print("onnxruntime.quantization not available, skipping INT8 quantization")
        print("Install with: pip install onnxruntime")


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("Downloading model files from HuggingFace...")
    onnx_path, sp_path = download_model_files()

    vocab_output = os.path.join(OUTPUT_DIR, "punctuation_sp_vocab.json")
    export_vocab(sp_path, vocab_output)

    fp32_output = os.path.join(OUTPUT_DIR, "punctuation_en.onnx")
    shutil.copy2(onnx_path, fp32_output)
    print(f"Copied FP32 model to {fp32_output}")

    int8_output = os.path.join(OUTPUT_DIR, "punctuation_en_int8.onnx")
    quantize_model(fp32_output, int8_output)

    print("\nDone. Files in assets/models/:")
    for f in sorted(os.listdir(OUTPUT_DIR)):
        size_mb = os.path.getsize(os.path.join(OUTPUT_DIR, f)) / (1024 * 1024)
        print(f"  {f} ({size_mb:.1f}MB)")


if __name__ == "__main__":
    main()
