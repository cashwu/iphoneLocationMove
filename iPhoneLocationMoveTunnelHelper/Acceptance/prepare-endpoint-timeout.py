#!/usr/bin/python3 -Es
"""Prepare the fixed root-owned endpoint-timeout production acceptance fixture."""

import hashlib
import json
import os
from pathlib import Path
import stat
import sys


RUNTIME_ROOT = Path(
    "/Library/Application Support/iPhoneLocationMove/TunnelRuntime/current"
)
EXECUTABLE = RUNTIME_ROOT / "runtime/pymobiledevice3"
SEAL = RUNTIME_ROOT / "runtime-seal.json"
TIMEOUT_FIXTURE = b"""#!/usr/bin/python3 -Es
import time

while True:
    time.sleep(1)
"""


def fail(message: str) -> None:
    raise SystemExit(message)


if len(sys.argv) != 1:
    fail("This fixed acceptance tool accepts no arguments.")
if os.geteuid() != 0:
    fail("This fixed acceptance tool must run as root.")

executable_info = os.lstat(EXECUTABLE)
if not stat.S_ISREG(executable_info.st_mode) or executable_info.st_uid != 0:
    fail("Generated executable is not a root-owned regular file.")

descriptor = os.open(EXECUTABLE, os.O_WRONLY | os.O_TRUNC | os.O_NOFOLLOW)
try:
    os.write(descriptor, TIMEOUT_FIXTURE)
    os.fchown(descriptor, 0, 0)
    os.fchmod(descriptor, 0o700)
    os.fsync(descriptor)
finally:
    os.close(descriptor)

files = []
for directory, directory_names, file_names in os.walk(RUNTIME_ROOT, followlinks=False):
    for name in directory_names:
        info = os.lstat(Path(directory) / name)
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
            fail(f"Unsafe runtime directory: {Path(directory) / name}")
    for name in file_names:
        path = Path(directory) / name
        if path == SEAL:
            continue
        info = os.lstat(path)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
            fail(f"Unsafe runtime file: {path}")
        files.append(
            {
                "mode": stat.S_IMODE(info.st_mode),
                "ownerID": info.st_uid,
                "relativePath": path.relative_to(RUNTIME_ROOT).as_posix(),
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            }
        )

files.sort(key=lambda item: item["relativePath"])
seal_data = json.dumps(
    {"files": files},
    separators=(",", ":"),
    sort_keys=True,
).encode()
descriptor = os.open(SEAL, os.O_WRONLY | os.O_TRUNC | os.O_NOFOLLOW)
try:
    os.write(descriptor, seal_data)
    os.fchown(descriptor, 0, 0)
    os.fchmod(descriptor, 0o600)
    os.fsync(descriptor)
finally:
    os.close(descriptor)
