#!/usr/bin/env python3
"""Convert a flat binary image into a $readmemh file (one 32-bit word per line).

usage: elf2hex.py <input.bin> <output.hex>
"""
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    data = open(sys.argv[1], "rb").read()
    data += b"\0" * (-len(data) % 4)
    with open(sys.argv[2], "w") as out:
        for i in range(0, len(data), 4):
            out.write(f"{int.from_bytes(data[i:i + 4], 'little'):08x}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
