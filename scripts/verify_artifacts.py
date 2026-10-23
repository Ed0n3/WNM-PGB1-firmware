"""Independently check the UF2 envelope, payload and RP2040 boot vectors."""
from pathlib import Path
import hashlib
import json
import re
import struct
import subprocess

root = Path(__file__).resolve().parents[1]
output = root / "artifacts"
raw = (output / "pgb1-cfw.bin").read_bytes()
uf2 = (output / "pgb1-cfw.uf2").read_bytes()
assert len(uf2) % 512 == 0, "truncated UF2"
count = len(uf2) // 512
payloads = []
for index in range(count):
    block = uf2[index * 512:(index + 1) * 512]
    first, second, flags, address, size, number, total, family = struct.unpack_from("<8I", block)
    assert (first, second) == (0x0A324655, 0x9E5D5157)
    assert flags == 0x2000 and family == 0xE48BFF56
    assert number == index and total == count and size == 256
    assert address == 0x10000000 + index * 256
    assert address + size <= 0x10100000, "UF2 would enter project storage"
    assert struct.unpack_from("<I", block, 508)[0] == 0x0AB16F30
    payloads.append(block[32:32 + size])
assert b"".join(payloads) == raw.ljust(count * 256, b"\0")
# Match the SDK boot2 generator: non-reflected CRC-32, initial 0xffffffff,
# polynomial 0x04c11db7, no final XOR, stored little-endian.
crc = 0xffffffff
for byte in raw[:252]:
    crc ^= byte << 24
    for _ in range(8):
        crc = ((crc << 1) ^ (0x04c11db7 if crc & 0x80000000 else 0)) & 0xffffffff
assert crc == struct.unpack_from("<I", raw, 252)[0], "invalid RP2040 boot2 CRC"
stack, reset = struct.unpack_from("<2I", raw, 256)
assert 0x20000000 < stack <= 0x20042000 and stack % 8 == 0
assert reset & 1 and 0x10000100 <= reset < 0x10000000 + len(raw)
paths = [output / name for name in ("pgb1-cfw.uf2", "pgb1-cfw.elf", "pgb1-cfw.bin")]
paths += list((root / "simulator/bin").glob("*.exe"))
paths += list((root / "simulator/bin").glob("*.dll"))
report = {
    "build_date": "2026-10-23",
    "version": "0.1.0-cfw.5",
    "upstream_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
    "working_tree_has_custom_changes": True,
    "code_bytes": len(raw),
    "uf2_blocks": count,
    "uf2_verified": True,
    "boot2_crc_verified": True,
    "initial_stack": hex(stack),
    "reset_vector": hex(reset),
    "artifacts": [{"path": str(path.relative_to(root)), "bytes": path.stat().st_size,
                   "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in paths],
}
build_log = (root / ".tools/device-link-verbose.log").read_text(encoding="utf-8-sig")
memory = re.findall(r"RAM:\s+(\d+) B\s+(\d+) KB", build_log)
if memory:
    used, kib = map(int, memory[-1])
    report["ram_bytes"] = used
    report["ram_capacity_bytes"] = kib * 1024
    report["ram_free_bytes"] = kib * 1024 - used
test_log = root / ".tools/test-run.log"
if test_log.exists():
    log = test_log.read_text(encoding="utf-8-sig")
    report["regression_tests"] = (
        "passed" if "CFW regression tests passed" in log and "exception" not in log.lower()
        else "not_clean")
report["hardware_validation"] = "not_run"
smoke_log = root / ".tools/simulator-smoke.json"
if smoke_log.exists():
    report["simulator_startup"] = json.loads(smoke_log.read_text(encoding="utf-8-sig"))
(output / "build-report.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"Verified {count} UF2 blocks, boot vectors and exact payload ({len(raw)} bytes)")
