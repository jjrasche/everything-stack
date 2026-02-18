"""Export bert-wiki-paragraphs to ONNX + WordPiece vocab JSON.

Usage:
  pip install transformers torch onnx onnxruntime
  python scripts/export_coherence_model.py

Downloads from HuggingFace:
  dennlinger/bert-wiki-paragraphs  (BERT-base, binary topic coherence)

Outputs:
  assets/models/bert_wiki_paragraphs.onnx      — INT8 quantized ONNX (~110 MB)
  assets/models/bert_wiki_paragraphs_vocab.json — WordPiece vocabulary for Dart tokenizer
"""

import json
import os

import torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification
from onnxruntime.quantization import quantize_dynamic, QuantType


MODEL_ID = "dennlinger/bert-wiki-paragraphs"
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "models")


def download_model():
    """Download model and tokenizer from HuggingFace."""
    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
    model = AutoModelForSequenceClassification.from_pretrained(MODEL_ID)
    model.eval()
    return tokenizer, model


def export_vocab(tokenizer, output_path: str):
    """Export WordPiece vocabulary to JSON for Dart tokenizer."""
    vocab = tokenizer.get_vocab()
    sorted_tokens = sorted(vocab.items(), key=lambda x: x[1])
    tokens = [token for token, _ in sorted_tokens]

    vocab_json = {
        "tokens": tokens,
        "unkId": tokenizer.unk_token_id,
        "clsId": tokenizer.cls_token_id,
        "sepId": tokenizer.sep_token_id,
        "padId": tokenizer.pad_token_id,
        "doLowerCase": tokenizer.do_lower_case,
    }

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(vocab_json, f, ensure_ascii=False)

    print(f"Exported {len(tokens)} tokens to {output_path}")


def export_onnx(model, tokenizer, fp32_path: str):
    """Export model to ONNX format."""
    dummy = tokenizer(
        "First paragraph about a topic.",
        "Second paragraph continuing the topic.",
        return_tensors="pt",
        padding="max_length",
        max_length=128,
        truncation=True,
    )

    torch.onnx.export(
        model,
        (dummy["input_ids"], dummy["attention_mask"], dummy["token_type_ids"]),
        fp32_path,
        input_names=["input_ids", "attention_mask", "token_type_ids"],
        output_names=["logits"],
        dynamic_axes={
            "input_ids": {0: "batch", 1: "seq"},
            "attention_mask": {0: "batch", 1: "seq"},
            "token_type_ids": {0: "batch", 1: "seq"},
            "logits": {0: "batch"},
        },
        opset_version=14,
    )

    size_mb = os.path.getsize(fp32_path) / (1024 * 1024)
    print(f"Exported FP32 ONNX to {fp32_path} ({size_mb:.1f}MB)")


def quantize(fp32_path: str, int8_path: str):
    """Quantize FP32 ONNX to INT8."""
    quantize_dynamic(
        fp32_path,
        int8_path,
        weight_type=QuantType.QInt8,
    )

    size_mb = os.path.getsize(int8_path) / (1024 * 1024)
    print(f"Quantized to INT8 at {int8_path} ({size_mb:.1f}MB)")


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("Downloading model and tokenizer...")
    tokenizer, model = download_model()

    vocab_path = os.path.join(OUTPUT_DIR, "bert_wiki_paragraphs_vocab.json")
    export_vocab(tokenizer, vocab_path)

    fp32_path = os.path.join(OUTPUT_DIR, "bert_wiki_paragraphs_fp32.onnx")
    export_onnx(model, tokenizer, fp32_path)

    int8_path = os.path.join(OUTPUT_DIR, "bert_wiki_paragraphs.onnx")
    quantize(fp32_path, int8_path)

    # Clean up FP32 intermediate
    os.remove(fp32_path)
    print(f"Removed FP32 intermediate: {fp32_path}")

    print("\nDone. Files in assets/models/:")
    for f in sorted(os.listdir(OUTPUT_DIR)):
        if "bert_wiki" in f:
            size_mb = os.path.getsize(os.path.join(OUTPUT_DIR, f)) / (1024 * 1024)
            print(f"  {f} ({size_mb:.1f}MB)")


if __name__ == "__main__":
    main()
