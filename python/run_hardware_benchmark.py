"""Run a labeled MNIST FX2 -> Cyclone II ML -> FX2 benchmark."""
from __future__ import annotations

import argparse
import csv
import time
from pathlib import Path

from fx2_protocol_test import pack_frame
from fx2_winusb_ui import FX2
from train import load_mnist, normalize_mnist


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", type=Path, default=Path("data/mnist"))
    ap.add_argument("--count", type=int, default=200)
    ap.add_argument("--start", type=int, default=0)
    ap.add_argument("--out", type=Path, default=Path("artifacts/hardware_benchmark.csv"))
    ap.add_argument("--delay", type=float, default=0.05)
    args = ap.parse_args()
    if args.count < 1 or args.start < 0:
        ap.error("--count must be positive and --start must be non-negative")

    _, _, images, labels = load_mnist(args.data)
    end = args.start + args.count
    if end > len(images):
        ap.error(f"requested samples [{args.start}, {end}) but test set has {len(images)}")
    frames = normalize_mnist(images[args.start:end])
    expected = labels[args.start:end]
    args.out.parent.mkdir(parents=True, exist_ok=True)
    fields = ["sample_id", "dataset_index", "expected_label", "fpga_digit",
              "accepted", "confidence", "margin", "cycles", "transport_ms",
              "correct", "error"]
    rows = []
    recoveries = 0
    transport_errors = 0
    accepted = 0
    correct = 0
    dev = FX2()
    try:
        print(dev.open())
        for offset, (pixels, label) in enumerate(zip(frames, expected)):
            result = None
            error = ""
            started = time.perf_counter()
            for attempt in range(3):
                try:
                    result = dev.transact(pack_frame([int(p) for p in pixels]))
                    break
                except (OSError, TimeoutError) as exc:
                    if attempt == 2:
                        transport_errors += 1
                        error = type(exc).__name__
                        print(f"{offset + 1}: transport failure: {exc}")
                        break
                    recoveries += 1
                    print(f"{offset + 1}: recovery {attempt + 1}: {exc}")
                    dev.close()
                    time.sleep(0.25)
                    print(dev.open())
            elapsed_ms = (time.perf_counter() - started) * 1000.0
            if result is None:
                rows.append({"sample_id": offset + 1, "dataset_index": args.start + offset,
                             "expected_label": int(label), "fpga_digit": "", "accepted": 0,
                             "confidence": "", "margin": "", "cycles": "",
                             "transport_ms": f"{elapsed_ms:.3f}", "correct": 0, "error": error})
                continue
            is_accepted = bool(result["accepted"])
            is_correct = is_accepted and int(result["digit"]) == int(label)
            accepted += int(is_accepted)
            correct += int(is_correct)
            rows.append({"sample_id": offset + 1, "dataset_index": args.start + offset,
                         "expected_label": int(label), "fpga_digit": int(result["digit"]),
                         "accepted": int(is_accepted), "confidence": int(result["confidence"]),
                         "margin": int(result["margin"]), "cycles": int(result["cycles"]),
                         "transport_ms": f"{elapsed_ms:.3f}", "correct": int(is_correct),
                         "error": "" if is_accepted else "non_recognizable"})
            print(f"{offset + 1}/{args.count}: expected={int(label)} digit={result['digit']} "
                  f"accepted={int(is_accepted)} correct={int(is_correct)} "
                  f"confidence={result['confidence']} margin={result['margin']} "
                  f"cycles={result['cycles']}")
            time.sleep(args.delay)
    finally:
        dev.close()
    with args.out.open("w", newline="", encoding="ascii") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    total = len(rows)
    print(f"BENCHMARK SUMMARY: samples={total} accepted={accepted} correct={correct} "
          f"acceptance={accepted / total:.4f} accuracy_all={correct / total:.4f} "
          f"accuracy_accepted={(correct / accepted if accepted else 0):.4f} "
          f"recoveries={recoveries} transport_errors={transport_errors}")
    print(f"CSV: {args.out}")


if __name__ == "__main__":
    main()
