"""PC-only test for the CoreEP2C5 FX2 ML packet format.

This does not require the board.  It validates the exact 16-bit words that
the streaming RTL expects and decodes the six-word result packet returned by
the RTL.  Pixels are 14x14, row-major, 4-bit grayscale values.
"""
from __future__ import annotations

import argparse
from pathlib import Path

PIXELS = 14 * 14


def make_four_points() -> list[int]:
    pixels = [0] * PIXELS
    for row, col in ((3, 3), (3, 10), (10, 3), (10, 10)):
        pixels[row * 14 + col] = 15
    return pixels


def pack_frame(pixels: list[int]) -> list[int]:
    if len(pixels) != PIXELS:
        raise ValueError(f"expected {PIXELS} pixels, got {len(pixels)}")
    if any(not 0 <= p <= 15 for p in pixels):
        raise ValueError("pixels must be 4-bit values in the range 0..15")
    words = [0xA5A5]
    words.extend((pixels[i] & 0xF) | ((pixels[i + 1] & 0xF) << 8) for i in range(0, PIXELS, 2))
    return words


def unpack_frame(words: list[int]) -> list[int]:
    if len(words) != 99 or words[0] != 0xA5A5:
        raise ValueError("frame must contain A5A5 plus 98 data words")
    pixels: list[int] = []
    for word in words[1:]:
        pixels.extend((word & 0xF, (word >> 8) & 0xF))
    return pixels


def decode_result(words: list[int]) -> dict[str, int | bool]:
    if len(words) != 6 or words[0] != 0x5A5A:
        raise ValueError("result must contain six words beginning with 5A5A")
    return {
        "accepted": bool((words[1] >> 8) & 1),
        "digit": words[1] & 0xF,
        "confidence": words[2] & 0xFF,
        "margin": words[3] & 0xFFFF,
        "cycles": (words[4] & 0xFFFF) | ((words[5] & 0xFFFF) << 16),
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", type=Path, help="write the packed frame as hexadecimal words")
    args = ap.parse_args()

    pixels = make_four_points()
    words = pack_frame(pixels)
    assert unpack_frame(words) == pixels
    if args.write:
        args.write.write_text("\n".join(f"0x{word:04X}" for word in words) + "\n", encoding="ascii")
    print(f"PASS: {len(words)} TX words, {len(unpack_frame(words))} pixels, row-major order preserved")
    print("Example result:", decode_result([0x5A5A, 0x0107, 0x0042, 0x0010, 0x1234, 0x0000]))


if __name__ == "__main__":
    main()
