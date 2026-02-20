"""Train a SetFit filter model from labeled golden data.

Loads labels, measures zero-shot baseline, fine-tunes DeBERTa-v3-xsmall
via SetFit contrastive learning, measures improvement, exports ONNX + INT8.

Usage:
  pip install setfit transformers torch onnx onnxruntime sentencepiece
  python scripts/train_filter.py

  Options:
    --labels PATH           Path to labeled JSON (default: golden/labels/filter/labeled_200.json)
    --output DIR            Output directory (default: assets/models/)
    --train-per-class 64    Training examples per class (few-shot)
    --seed 42               Random seed

Outputs:
  assets/models/filter_deberta_v3_xsmall.onnx     — INT8 quantized model (~40MB)
  assets/models/filter_deberta_sp_vocab.json       — SentencePiece vocabulary
  assets/models/filter_head.json                   — Logistic regression head weights
"""

import argparse
import json
import os
import sys

import numpy as np
import torch
from datasets import Dataset
from onnxruntime.quantization import QuantType, quantize_dynamic
from setfit import SetFitModel, Trainer, TrainingArguments
from sklearn.metrics import classification_report
from transformers import AutoTokenizer

sys.stdout.reconfigure(encoding="utf-8")

GOLDEN_DIR = os.path.join(
    os.path.dirname(__file__),
    "..",
    "lib",
    "training",
    "extraction",
    "golden",
)
DEFAULT_LABELS = os.path.join(GOLDEN_DIR, "labels", "filter", "labeled_200.json")
DEFAULT_OUTPUT = os.path.join(os.path.dirname(__file__), "..", "assets", "models")

# 22M params, SentencePiece tokenizer, ~40MB quantized. Runs on mobile.
BASE_MODEL = "microsoft/deberta-v3-xsmall"

LABEL_MAP = {"skip": 0, "extract": 1}
LABEL_NAMES = ["skip", "extract"]


def load_labeled_spans(labels_path: str) -> list[dict]:
    """Load labeled spans from JSON, validate required fields."""
    with open(labels_path, "r", encoding="utf-8") as f:
        items = json.load(f)

    validated = []
    for item in items:
        if "text" not in item or "label" not in item:
            continue
        if item["label"] not in LABEL_MAP:
            continue
        validated.append(item)

    extract_count = sum(1 for i in validated if i["label"] == "extract")
    skip_count = sum(1 for i in validated if i["label"] == "skip")
    print(f"Loaded {len(validated)} labeled spans: {extract_count} extract, {skip_count} skip")
    return validated


def split_train_eval(
    items: list[dict], train_per_class: int, seed: int
) -> tuple[list[dict], list[dict]]:
    """Few-shot split: fixed train size per class, rest is eval."""
    rng = np.random.default_rng(seed)

    extract = [i for i in items if i["label"] == "extract"]
    skip = [i for i in items if i["label"] == "skip"]

    rng.shuffle(extract)
    rng.shuffle(skip)

    train_extract = min(train_per_class, len(extract) - 2)
    train_skip = min(train_per_class, len(skip) - 2)

    train = extract[:train_extract] + skip[:train_skip]
    eval_set = extract[train_extract:] + skip[train_skip:]

    rng.shuffle(train)
    rng.shuffle(eval_set)

    print(f"Train: {len(train)} ({train_extract} extract, {train_skip} skip)")
    print(f"Eval:  {len(eval_set)} ({len(extract) - train_extract} extract, {len(skip) - train_skip} skip)")
    return train, eval_set


def build_dataset(items: list[dict]) -> Dataset:
    """Convert labeled spans to HuggingFace Dataset."""
    return Dataset.from_dict(
        {
            "text": [i["text"] for i in items],
            "label": [LABEL_MAP[i["label"]] for i in items],
        }
    )


def measure_baseline(train_items: list[dict], eval_items: list[dict]) -> None:
    """Measure pre-trained encoder baseline: fit head on untrained embeddings."""
    print("\n--- BASELINE (pre-trained encoder, no contrastive training) ---")
    model = SetFitModel.from_pretrained(BASE_MODEL)

    # Encode with the pre-trained body (no contrastive training), fit head directly
    train_texts = [i["text"] for i in train_items]
    train_labels = [LABEL_MAP[i["label"]] for i in train_items]
    train_embeddings = model.model_body.encode(train_texts)
    model.model_head.fit(train_embeddings, train_labels)

    eval_texts = [i["text"] for i in eval_items]
    true_labels = [LABEL_MAP[i["label"]] for i in eval_items]
    eval_embeddings = model.model_body.encode(eval_texts)

    pred_labels = model.model_head.predict(eval_embeddings).tolist()

    print(classification_report(true_labels, pred_labels, target_names=LABEL_NAMES))

    majority_count = sum(1 for l in true_labels if l == 1)
    majority_acc = majority_count / len(true_labels)
    print(f"Majority-class baseline (predict all extract): {majority_acc:.1%}")


def train_model(
    train_dataset: Dataset, eval_dataset: Dataset, seed: int
) -> SetFitModel:
    """Fine-tune DeBERTa-v3-xsmall with SetFit contrastive learning."""
    model = SetFitModel.from_pretrained(BASE_MODEL)

    training_args = TrainingArguments(
        batch_size=16,
        num_iterations=5,
        num_epochs=1,
        seed=seed,
    )

    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=train_dataset,
        eval_dataset=eval_dataset,
    )

    trainer.train()
    metrics = trainer.evaluate(eval_dataset)
    print(f"Eval metrics: {metrics}")
    return model


def evaluate_detailed(model: SetFitModel, eval_items: list[dict]) -> None:
    """Print per-class precision, recall, F1."""
    print("\n--- TRAINED MODEL ---")
    texts = [i["text"] for i in eval_items]
    true_labels = [LABEL_MAP[i["label"]] for i in eval_items]

    predictions = model.predict(texts)
    pred_labels = [int(p) for p in predictions]

    print(classification_report(true_labels, pred_labels, target_names=LABEL_NAMES))


def export_onnx(model: SetFitModel, output_dir: str) -> str:
    """Export SetFit model body (sentence transformer) to ONNX."""
    fp32_path = os.path.join(output_dir, "filter_deberta_v3_xsmall_fp32.onnx")
    int8_path = os.path.join(output_dir, "filter_deberta_v3_xsmall.onnx")

    body = model.model_body

    tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL)
    dummy = tokenizer(
        "This is a test sentence for export.",
        return_tensors="pt",
        padding="max_length",
        max_length=512,
        truncation=True,
    )

    transformer = body[0].auto_model

    # Export transformer only; pooling + classification happen in Dart
    transformer.eval()
    with torch.no_grad():
        torch.onnx.export(
            transformer,
            (dummy["input_ids"], dummy["attention_mask"]),
            fp32_path,
            input_names=["input_ids", "attention_mask"],
            output_names=["last_hidden_state"],
            dynamic_axes={
                "input_ids": {0: "batch", 1: "seq"},
                "attention_mask": {0: "batch", 1: "seq"},
                "last_hidden_state": {0: "batch", 1: "seq"},
            },
            opset_version=14,
        )

    size_mb = os.path.getsize(fp32_path) / (1024 * 1024)
    print(f"Exported FP32 ONNX: {fp32_path} ({size_mb:.1f}MB)")

    quantize_dynamic(fp32_path, int8_path, weight_type=QuantType.QInt8)
    size_mb = os.path.getsize(int8_path) / (1024 * 1024)
    print(f"Quantized INT8 ONNX: {int8_path} ({size_mb:.1f}MB)")

    os.remove(fp32_path)

    head = model.model_head
    head_path = os.path.join(output_dir, "filter_head.json")
    head_data = {
        "coef": head.coef_.tolist(),
        "intercept": head.intercept_.tolist(),
        "classes": head.classes_.tolist(),
    }
    with open(head_path, "w", encoding="utf-8") as f:
        json.dump(head_data, f)
    print(f"Exported classification head: {head_path}")

    return int8_path


def export_vocab(output_dir: str) -> str:
    """Export SentencePiece vocabulary for DeBERTa-v3-xsmall."""
    import sentencepiece as spm
    from huggingface_hub import hf_hub_download

    sp_path = hf_hub_download(BASE_MODEL, "spm.model")
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

    output_path = os.path.join(output_dir, "filter_deberta_sp_vocab.json")
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False, indent=2)

    print(f"Exported {sp.GetPieceSize()} pieces to {output_path}")
    return output_path


def main():
    parser = argparse.ArgumentParser(description="Train SetFit filter model")
    parser.add_argument("--labels", default=DEFAULT_LABELS, help="Path to labeled JSON")
    parser.add_argument("--output", default=DEFAULT_OUTPUT, help="Output directory")
    parser.add_argument("--train-per-class", type=int, default=64, help="Training examples per class (few-shot)")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    args = parser.parse_args()

    os.makedirs(args.output, exist_ok=True)

    items = load_labeled_spans(args.labels)
    if len(items) < 20:
        print(f"Only {len(items)} labeled spans — need at least 20 for SetFit")
        sys.exit(1)

    train_items, eval_items = split_train_eval(items, args.train_per_class, args.seed)

    # Measure baseline BEFORE contrastive training
    measure_baseline(train_items, eval_items)

    train_dataset = build_dataset(train_items)
    eval_dataset = build_dataset(eval_items)

    print(f"\nTraining SetFit on {BASE_MODEL}...")
    model = train_model(train_dataset, eval_dataset, args.seed)

    evaluate_detailed(model, eval_items)

    print("\nExporting ONNX...")
    export_onnx(model, args.output)

    print("\nExporting vocabulary...")
    export_vocab(args.output)

    print("\nDone. Files:")
    for f in sorted(os.listdir(args.output)):
        if "filter" in f:
            size_mb = os.path.getsize(os.path.join(args.output, f)) / (1024 * 1024)
            print(f"  {f} ({size_mb:.1f}MB)")


if __name__ == "__main__":
    main()
