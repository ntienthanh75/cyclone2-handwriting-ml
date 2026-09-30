"""Generate deterministic UVM golden vectors from the exported MIF weights."""
from pathlib import Path
import json
import re


ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / "artifacts"


def read_mif(name: str, bits: int) -> list[int]:
    values = []
    for line in (ARTIFACTS / name).read_text(encoding="ascii").splitlines():
        match = re.match(r"\s*\d+\s*:\s*([0-9A-Fa-f]+)", line)
        if match:
            value = int(match.group(1), 16)
            if value & (1 << (bits - 1)):
                value -= 1 << bits
            values.append(value)
    return values


def infer(frame: list[int], w1: list[int], b1: list[int], w2: list[int], b2: list[int]) -> dict:
    hidden = [max(0, b1[n] + sum(frame[p] * w1[n * 196 + p] for p in range(196))) for n in range(32)]
    scores = [b2[o] + sum(hidden[n] * w2[o * 32 + n] for n in range(32)) for o in range(10)]
    order = sorted(range(10), key=lambda digit: scores[digit], reverse=True)
    digit, second = order[0], order[1]
    return {
        "digit": digit,
        "confidence": max(0, min(255, scores[digit])),
        "margin": max(0, min(65535, scores[digit] - scores[second])),
    }


def main() -> None:
    w1 = read_mif("weights_l1.mif", 8)
    b1 = read_mif("bias_l1.mif", 32)
    w2 = read_mif("weights_l2.mif", 8)
    b2 = read_mif("bias_l2.mif", 32)
    vectors = {
        "zero": [0] * 196,
        "white": [15] * 196,
        "checker": [15 if pixel % 2 == 0 else 0 for pixel in range(196)],
        "diagonal": [15 if pixel // 14 == pixel % 14 else 0 for pixel in range(196)],
    }
    result = {name: {"pixels": pixels, "expected": infer(pixels, w1, b1, w2, b2)} for name, pixels in vectors.items()}
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
