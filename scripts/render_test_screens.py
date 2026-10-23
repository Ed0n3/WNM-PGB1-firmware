"""Turn optional 128x64 RGBA test framebuffers into readable PNG captures."""
from pathlib import Path
import argparse
import struct
import zlib

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("directory", type=Path)
args = parser.parse_args()


def chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))


for source in sorted(args.directory.glob("*.rgba")):
    pixels = source.read_bytes()
    if len(pixels) != 128 * 64 * 4:
        raise ValueError(f"Invalid framebuffer size: {source}")
    rows = []
    for y in range(64):
        row = b"".join(pixels[(y * 128 + x) * 4:(y * 128 + x + 1) * 4] * 4
                       for x in range(128))
        rows.extend([b"\0" + row] * 4)
    target = source.with_suffix(".png")
    target.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">2I5B", 512, 256, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(b"".join(rows)))
        + chunk(b"IEND", b""))
    print(target)
