"""Train and export the reusable PC reference model.

The FPGA receives only the exported 14x14 uint4 tensor.  Photo handling and
training stay on the PC so the same inference contract can serve MNIST, a PNG
photo, or a later LCD-touch capture.
"""
from __future__ import annotations

import argparse
import gzip
import json
import struct
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

BASE_URL = "https://storage.googleapis.com/cvdf-datasets/mnist/"
FILES = {
    "train_images": "train-images-idx3-ubyte.gz",
    "train_labels": "train-labels-idx1-ubyte.gz",
    "test_images": "t10k-images-idx3-ubyte.gz",
    "test_labels": "t10k-labels-idx1-ubyte.gz",
}


def download_dataset(data_dir: Path) -> None:
    data_dir.mkdir(parents=True, exist_ok=True)
    for name in FILES.values():
        target = data_dir / name
        if not target.exists():
            print(f"Downloading {name}")
            urllib.request.urlretrieve(BASE_URL + name, target)


def read_idx(path: Path) -> np.ndarray:
    with gzip.open(path, "rb") as f:
        magic, count = struct.unpack(">II", f.read(8))
        kind = magic & 0xFF
        if kind == 3:
            rows, cols = struct.unpack(">II", f.read(8))
            return np.frombuffer(f.read(), dtype=np.uint8).reshape(count, rows, cols)
        if kind == 1:
            return np.frombuffer(f.read(), dtype=np.uint8, count=count)
    raise ValueError(f"Unsupported IDX file: {path}")


def load_mnist(data_dir: Path):
    download_dataset(data_dir)
    return (
        read_idx(data_dir / FILES["train_images"]),
        read_idx(data_dir / FILES["train_labels"]),
        read_idx(data_dir / FILES["test_images"]),
        read_idx(data_dir / FILES["test_labels"]),
    )


def normalize_mnist(images: np.ndarray) -> np.ndarray:
    """Area-average 28x28 images into the FPGA's 14x14 uint4 tensor."""
    x = images.reshape(-1, 14, 2, 14, 2).mean(axis=(2, 4))
    return np.rint(x / 17.0).clip(0, 15).astype(np.uint8).reshape(len(images), 196)


def normalize_photo(path: Path) -> np.ndarray:
    """Normalize one photo containing a single dark-on-light digit."""
    img = ImageOps.grayscale(Image.open(path)).convert("L")
    arr = np.asarray(img, dtype=np.uint8)
    threshold = max(32, int(np.percentile(arr, 35)))
    mask = arr < threshold
    ys, xs = np.where(mask)
    if len(xs) < 20:
        raise ValueError("NON_RECOGNIZABLE: no usable foreground")
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    crop = Image.fromarray(arr[y0:y1, x0:x1]).resize((24, 24), Image.Resampling.BOX)
    canvas = Image.new("L", (28, 28), 255)
    canvas.paste(crop, (2, 2))
    return normalize_mnist(np.asarray(canvas, dtype=np.uint8)[None, ...])[0]


class MLP:
    def __init__(self, seed: int = 1234):
        rng = np.random.default_rng(seed)
        self.w1 = (rng.standard_normal((196, 32), dtype=np.float32) * 0.08)
        self.b1 = np.zeros(32, dtype=np.float32)
        self.w2 = (rng.standard_normal((32, 10), dtype=np.float32) * 0.08)
        self.b2 = np.zeros(10, dtype=np.float32)

    def logits(self, x):
        h = np.maximum(0.0, x @ self.w1 + self.b1)
        return h @ self.w2 + self.b2

    def fit(self, x, y, epochs=8, batch=256, lr=0.04):
        rng = np.random.default_rng(1234)
        n = len(x)
        for epoch in range(epochs):
            order = rng.permutation(n)
            for start in range(0, n, batch):
                ix = order[start:start + batch]
                xb, yb = x[ix], y[ix]
                z1 = xb @ self.w1 + self.b1
                h = np.maximum(0.0, z1)
                logits = h @ self.w2 + self.b2
                logits -= logits.max(axis=1, keepdims=True)
                p = np.exp(logits); p /= p.sum(axis=1, keepdims=True)
                p[np.arange(len(yb)), yb] -= 1.0
                p /= len(yb)
                dw2 = h.T @ p; db2 = p.sum(axis=0)
                dh = p @ self.w2.T; dz1 = dh * (z1 > 0)
                dw1 = xb.T @ dz1; db1 = dz1.sum(axis=0)
                self.w2 -= lr * dw2; self.b2 -= lr * db2
                self.w1 -= lr * dw1; self.b1 -= lr * db1
            print(f"epoch {epoch + 1}/{epochs}: accuracy={accuracy(self, x[:10000], y[:10000]):.4f}")


def accuracy(model, x, y):
    return float((model.logits(x).argmax(axis=1) == y).mean())


def decision_stats(model, x, y, thresholds=None):
    logits = model.logits(x)
    ex = np.exp(logits - logits.max(axis=1, keepdims=True))
    probs = ex / ex.sum(axis=1, keepdims=True)
    order = np.argsort(probs, axis=1)[:, ::-1]
    confidence = probs[np.arange(len(y)), order[:, 0]]
    margin = confidence - probs[np.arange(len(y)), order[:, 1]]
    if thresholds is None:
        correct = order[:, 0] == y
        thresholds = {
            "confidence": float(np.quantile(confidence[correct], 0.05)),
            "margin": float(np.quantile(margin[correct], 0.05)),
        }
    accepted = (confidence >= thresholds["confidence"]) & (margin >= thresholds["margin"])
    return thresholds, order[:, 0], confidence, margin, accepted


def quantize(model):
    scale = 127.0 / max(np.abs(model.w1).max(), np.abs(model.w2).max(), 1e-6)
    return {
        "w1": np.rint(model.w1 * scale).clip(-127, 127).astype(np.int8),
        "b1": np.rint(model.b1 * scale).astype(np.int32),
        "w2": np.rint(model.w2 * scale).clip(-127, 127).astype(np.int8),
        "b2": np.rint(model.b2 * scale).astype(np.int32),
        "scale": float(scale),
    }


def export_model(model, out_dir: Path, metadata: dict):
    out_dir.mkdir(parents=True, exist_ok=True)
    q = quantize(model)
    for key in ("w1", "b1", "w2", "b2"):
        np.save(out_dir / f"{key}.npy", q[key])
    (out_dir / "metadata.json").write_text(json.dumps({**metadata, "quantization": {"scale": q["scale"]}}, indent=2))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", type=Path, default=Path("data/mnist"))
    ap.add_argument("--out", type=Path, default=Path("artifacts"))
    ap.add_argument("--epochs", type=int, default=8)
    ap.add_argument("--photo", type=Path)
    args = ap.parse_args()
    tr_i, tr_y, te_i, te_y = load_mnist(args.data)
    val_x = normalize_mnist(tr_i[:10000]).astype(np.float32) / 15.0
    val_y = tr_y[:10000]
    x = normalize_mnist(tr_i[10000:]).astype(np.float32) / 15.0
    y = tr_y[10000:]
    xt = normalize_mnist(te_i).astype(np.float32) / 15.0
    model = MLP()
    model.fit(x, y, epochs=args.epochs)
    thresholds, _, _, _, _ = decision_stats(model, val_x, val_y)
    thresholds, pred, conf, margin, accepted = decision_stats(model, xt, te_y, thresholds)
    cm = np.zeros((10, 10), dtype=np.int64)
    for actual, guess in zip(te_y[accepted], pred[accepted]):
        cm[int(actual), int(guess)] += 1
    print(f"test_accuracy={accuracy(model, xt, te_y):.4f}")
    print(f"accepted_coverage={accepted.mean():.4f}")
    print(f"accepted_accuracy={(pred[accepted] == te_y[accepted]).mean():.4f}")
    print("confusion_matrix=")
    print(cm)
    export_model(model, args.out, {"model": "196-32-10", "input": "14x14 uint4", "seed": 1234, "thresholds": thresholds})
    if args.photo:
        tensor = normalize_photo(args.photo).astype(np.float32) / 15.0
        _, pred, conf, margin, accepted = decision_stats(model, tensor[None, :], np.array([0]), thresholds)
        print({"status": "ACCEPTED" if bool(accepted[0]) else "NON_RECOGNIZABLE", "digit": int(pred[0]), "confidence": float(conf[0]), "margin": float(margin[0])})


if __name__ == "__main__":
    main()
