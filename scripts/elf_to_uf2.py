"""Convert a linked RP2040 ELF into a code-only UF2 using GNU objcopy."""
from pathlib import Path
import argparse
import struct
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("elf", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--objcopy", required=True)
args = parser.parse_args()
binary = args.output.with_suffix(".bin")
subprocess.run([args.objcopy, "-O", "binary", str(args.elf), str(binary)], check=True)
data = binary.read_bytes()
if not data or len(data) > 1024 * 1024:
    raise SystemExit("Code image is empty or exceeds the PGB-1 code partition")
count = (len(data) + 255) // 256
with args.output.open("wb") as output:
    for index in range(count):
        payload = data[index * 256:(index + 1) * 256].ljust(256, b"\0")
        header = struct.pack("<8I", 0x0A324655, 0x9E5D5157, 0x2000,
                             0x10000000 + index * 256, 256, index, count,
                             0xE48BFF56)
        output.write(header + payload + bytes(220) + struct.pack("<I", 0x0AB16F30))
print(f"{args.output}: {count} RP2040 blocks, {len(data)} code bytes")
