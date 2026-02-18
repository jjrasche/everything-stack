"""Export the NLI DeBERTa-v3-xsmall model's SentencePiece vocabulary to JSON.

Usage:
  pip install sentencepiece huggingface_hub
  python scripts/export_nli_model.py

Downloads from HuggingFace:
  cross-encoder/nli-deberta-v3-xsmall  (SentencePiece vocab)
  Xenova/nli-deberta-v3-xsmall         (pre-quantized ONNX)

Outputs:
  assets/models/nli_deberta_sp_vocab.json  — SentencePiece vocabulary for Dart tokenizer
  assets/models/nli_deberta_v3_xsmall.onnx — INT8 quantized ONNX model (~87 MB)
"""

import json
import os
import shutil

from huggingface_hub import hf_hub_download
import sentencepiece as spm


VOCAB_REPO = "cross-encoder/nli-deberta-v3-xsmall"
ONNX_REPO = "Xenova/nli-deberta-v3-xsmall"
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "models")


def download_spm_model():
    """Download SentencePiece model from the cross-encoder repo."""
    return hf_hub_download(VOCAB_REPO, "spm.model")


def download_onnx_model():
    """Download pre-quantized ONNX model from Xenova's export."""
    return hf_hub_download(ONNX_REPO, "onnx/model_quantized.onnx")


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


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("Downloading SentencePiece model...")
    sp_path = download_spm_model()

    vocab_output = os.path.join(OUTPUT_DIR, "nli_deberta_sp_vocab.json")
    export_vocab(sp_path, vocab_output)

    print("Downloading pre-quantized ONNX model...")
    onnx_path = download_onnx_model()

    onnx_output = os.path.join(OUTPUT_DIR, "nli_deberta_v3_xsmall.onnx")
    shutil.copy2(onnx_path, onnx_output)
    size_mb = os.path.getsize(onnx_output) / (1024 * 1024)
    print(f"Copied quantized model to {onnx_output} ({size_mb:.1f}MB)")

    print("\nDone. Files in assets/models/:")
    for f in sorted(os.listdir(OUTPUT_DIR)):
        if "nli" in f:
            size_mb = os.path.getsize(os.path.join(OUTPUT_DIR, f)) / (1024 * 1024)
            print(f"  {f} ({size_mb:.1f}MB)")


if __name__ == "__main__":
    main()
