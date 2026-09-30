"""Check exported int8 weights and create Quartus-compatible MIF files."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

from train import load_mnist, normalize_mnist


def signed_hex(value: int, bits: int) -> str:
    return f"{int(value) & ((1 << bits) - 1):0{bits // 4}X}"


def write_mif(path: Path, values: np.ndarray, width: int) -> None:
    flat = values.astype(np.int64).reshape(-1)
    lines = [f"WIDTH={width};", f"DEPTH={len(flat)};", "ADDRESS_RADIX=UNS;", "DATA_RADIX=HEX;", "CONTENT BEGIN"]
    lines.extend(f"{i} : {signed_hex(v, width)};" for i, v in enumerate(flat))
    lines.append("END;")
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--artifacts", type=Path, default=Path("artifacts"))
    ap.add_argument("--data", type=Path, default=Path("data/mnist"))
    args = ap.parse_args()

    meta = json.loads((args.artifacts / "metadata.json").read_text())
    scale = float(meta["quantization"]["scale"])
    w1 = np.load(args.artifacts / "w1.npy").astype(np.float32) / scale
    b1 = np.load(args.artifacts / "b1.npy").astype(np.float32) / scale
    w2 = np.load(args.artifacts / "w2.npy").astype(np.float32) / scale
    b2 = np.load(args.artifacts / "b2.npy").astype(np.float32) / scale

    _, _, test_images, test_labels = load_mnist(args.data)
    x = normalize_mnist(test_images).astype(np.float32) / 15.0
    h = np.maximum(0.0, x @ w1 + b1)
    logits = h @ w2 + b2
    prediction = logits.argmax(axis=1)
    accuracy = float((prediction == test_labels).mean())

    write_mif(args.artifacts / "weights_l1.mif", np.load(args.artifacts / "w1.npy"), 8)
    write_mif(args.artifacts / "bias_l1.mif", np.load(args.artifacts / "b1.npy"), 32)
    write_mif(args.artifacts / "weights_l2.mif", np.load(args.artifacts / "w2.npy"), 8)
    write_mif(args.artifacts / "bias_l2.mif", np.load(args.artifacts / "b2.npy"), 32)
    report = {"quantized_dequantized_test_accuracy": accuracy, "weight_scale": scale, "format": "row-major signed two's-complement MIF"}
    (args.artifacts / "quantized_report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
