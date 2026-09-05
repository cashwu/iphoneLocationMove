from __future__ import annotations

import argparse
import base64
import fcntl
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from .config import ConfigError, parse_cash_config, parse_openspec_config


BUNDLE_VERSION = "2.21.0"
VERSION_RE = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")
DIGEST_RE = re.compile(r"[0-9a-f]{64}\Z")
MODE_RE = re.compile(r"0[0-7]{3}\Z")
SKILLS = (
    "analyze",
    "apply",
    "archive",
    "ask",
    "audit",
    "commit",
    "debug",
    "discuss",
    "drift",
    "ingest",
    "propose",
    "verify",
)
# The expected runtime inventory for a target, where no source tree exists to
# derive it from. Ordered by path bytes, matching `source_inventory`'s sort key.
# `test_installer_runtime.py` asserts this equals what `source_inventory`
# derives, so a runtime module added or removed without updating this tuple
# turns the source-side suite red instead of reaching a target.
BUNDLE_RUNTIME_PATHS = (
    ".cash-skills/lib/cash_cli/__init__.py",
    ".cash-skills/lib/cash_cli/commands/__init__.py",
    ".cash-skills/lib/cash_cli/commands/analyze.py",
    ".cash-skills/lib/cash_cli/commands/archive.py",
    ".cash-skills/lib/cash_cli/commands/create.py",
    ".cash-skills/lib/cash_cli/commands/discovery.py",
    ".cash-skills/lib/cash_cli/commands/drift.py",
    ".cash-skills/lib/cash_cli/commands/lifecycle.py",
    ".cash-skills/lib/cash_cli/commands/search.py",
    ".cash-skills/lib/cash_cli/commands/tasks.py",
    ".cash-skills/lib/cash_cli/commands/validate.py",
    ".cash-skills/lib/cash_cli/config.py",
    ".cash-skills/lib/cash_cli/errors.py",
    ".cash-skills/lib/cash_cli/installer.py",
    ".cash-skills/lib/cash_cli/main.py",
    ".cash-skills/lib/cash_cli/resources.py",
    ".cash-skills/lib/cash_cli/spec_merge.py",
    ".cash-skills/lib/cash_cli/validation.py",
    ".cash-skills/lib/cash_cli/workspace.py",
)
STABLE_PATHS = (".cash-skills/bin/cash", ".cash-workspace.lock")
GUIDANCE_PATHS = ("AGENTS.md", "CLAUDE.md")
RECEIPT_PATH = ".cash-skills/receipt.tsv"
PORTABLE_MANIFEST_PATH = ".cash-skills/manifest.tsv"
JOURNAL_PATH = ".cash-skills/state/installer/journal.json"
GITIGNORE_PATH = ".gitignore"
OPENSPEC_CONFIG_PATH = "openspec/config.yaml"
OPENSPEC_CONFIG_BASELINE: bytes = (
    b"schema: spec-driven\n"
    b"\n"
    b"# Add project context with a context block when needed.\n"
    b"# Add artifact-specific instructions under rules when needed.\n"
)
GITIGNORE_RULES = (
    b".cash-skills/receipt.tsv",
    b".cash-skills/state/",
    b"__pycache__/",
)
LEGACY_MANIFEST_PATH = "scripts/cash-skills/legacy-spectra-digests.tsv"
APPROVED_LAUNCHER_TRANSITIONS = (
    (
        "592345fffa009998d48008857ad903d89b0e5f0986d141a5fec26368b527c8a4",
        "76fe6dd649b1df558ef374d055ca2c5fe4c40a9200b32a1da1d41ca631c3d52f",
        "2.12.0",
    ),
    (
        "76fe6dd649b1df558ef374d055ca2c5fe4c40a9200b32a1da1d41ca631c3d52f",
        "e7457338cfd6721fcc21fbbf96fad287176ebec674be6a12fc4e9ff27542804e",
        "2.13.0",
    ),
    (
        "592345fffa009998d48008857ad903d89b0e5f0986d141a5fec26368b527c8a4",
        "e7457338cfd6721fcc21fbbf96fad287176ebec674be6a12fc4e9ff27542804e",
        "2.13.0",
    ),
)


class InstallerError(Exception):
    def __init__(self, message: str, *, result: str | None = None, exit_code: int = 1):
        super().__init__(message)
        self.result = result
        self.exit_code = exit_code


class InitError(Exception):
    """A target-side receipt initialization failure with a named error code."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class Record:
    kind: str
    path: str
    digest: str
    mode: int


@dataclass(frozen=True)
class Snapshot:
    exists: bool
    content: bytes | None = None
    mode: int | None = None
    device: int | None = None
    inode: int | None = None


@dataclass(frozen=True)
class Receipt:
    version: str
    generation: str
    records: tuple[tuple[str, str, str, int, int | None, int | None], ...]


@dataclass(frozen=True)
class PortableManifest:
    version: str
    generation: str
    records: tuple[Record, ...]


@dataclass(frozen=True)
class LegacyReceipt:
    version: str
    records: tuple[tuple[str, str], ...]


@dataclass(frozen=True)
class TestHooks:
    hold: str | None = None
    publication_hold: str | None = None
    fail_after: int | None = None
    fail_after_path: str | None = None
    crash_after_quarantine: int | None = None


CONSUMED_TEST_HOLDS: set[str] = set()


def sha256(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def version_parts(value: str) -> tuple[str, str, str]:
    match = VERSION_RE.fullmatch(value)
    if match is None:
        raise InstallerError(f"invalid bundle version: {value}")
    return match.group(1), match.group(2), match.group(3)


def compare_versions(left: str, right: str) -> int:
    for a, b in zip(version_parts(left), version_parts(right), strict=True):
        if len(a) != len(b):
            return -1 if len(a) < len(b) else 1
        if a != b:
            return -1 if a < b else 1
    return 0


def relative_path(value: str) -> str:
    path = Path(value)
    if not value or path.is_absolute() or ".." in path.parts or value != path.as_posix():
        raise InstallerError(f"unsafe managed path: {value}")
    return value


def ensure_contained(root: Path, relative: str) -> Path:
    relative_path(relative)
    candidate = root / relative
    current = root
    for part in Path(relative).parts:
        current = current / part
        try:
            metadata = os.lstat(current)
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(metadata.st_mode):
            raise InstallerError(f"symlink managed boundary: {relative}")
        if current != candidate and not stat.S_ISDIR(metadata.st_mode):
            raise InstallerError(f"managed parent is not a directory: {relative}")
    return candidate


def read_regular(
    root: Path,
    relative: str,
    *,
    expected_mode: int | None = None,
    allow_hardlink: bool = False,
) -> tuple[bytes, os.stat_result]:
    path = ensure_contained(root, relative)
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise InstallerError(f"cannot open regular file {relative}: {error}") from error
    try:
        opened = os.fstat(descriptor)
        named = os.lstat(path)
        if (
            not stat.S_ISREG(opened.st_mode)
            or (not allow_hardlink and opened.st_nlink != 1)
            or (opened.st_dev, opened.st_ino) != (named.st_dev, named.st_ino)
        ):
            raise InstallerError(f"unsafe regular file identity: {relative}")
        if expected_mode is not None and stat.S_IMODE(opened.st_mode) != expected_mode:
            raise InstallerError(f"invalid mode for {relative}: expected {expected_mode:04o}")
        chunks: list[bytes] = []
        while chunk := os.read(descriptor, 131072):
            chunks.append(chunk)
        after = os.fstat(descriptor)
        if (opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns) != (
            after.st_dev,
            after.st_ino,
            after.st_size,
            after.st_mtime_ns,
        ):
            raise InstallerError(f"file changed while reading: {relative}")
        return b"".join(chunks), opened
    finally:
        os.close(descriptor)


def optional_snapshot(root: Path, relative: str) -> Snapshot:
    path = ensure_contained(root, relative)
    try:
        metadata = os.lstat(path)
    except FileNotFoundError:
        return Snapshot(False)
    content, opened = read_regular(root, relative)
    return Snapshot(
        True,
        content,
        stat.S_IMODE(opened.st_mode),
        opened.st_dev,
        opened.st_ino,
    )


def snapshots(
    root: Path,
    relatives: Iterable[str],
) -> tuple[tuple[str, Snapshot], ...]:
    return tuple(
        (relative, optional_snapshot(root, relative))
        for relative in dict.fromkeys(relatives)
    )


def ensure_directories(root: Path, relative_parent: str) -> None:
    current = root
    for part in Path(relative_parent).parts:
        current = current / part
        try:
            metadata = os.lstat(current)
        except FileNotFoundError:
            os.mkdir(current, 0o755)
            metadata = os.lstat(current)
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise InstallerError(f"unsafe managed directory: {current}")


def snapshot_matches(root: Path, relative: str, expected: Snapshot) -> bool:
    current = optional_snapshot(root, relative)
    if current.exists != expected.exists:
        return False
    if not expected.exists:
        return True
    return (
        current.device == expected.device
        and current.inode == expected.inode
        and current.mode == expected.mode
        and current.content == expected.content
    )


def atomic_write(
    root: Path,
    relative: str,
    content: bytes,
    mode: int,
    *,
    expected: Snapshot | None = None,
) -> None:
    path = ensure_contained(root, relative)
    ensure_directories(root, Path(relative).parent.as_posix())
    parent = path.parent
    before = os.lstat(parent)
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    directory_fd = os.open(parent, flags)
    temporary = f".cash-install-{uuid.uuid4().hex}"
    try:
        held = os.fstat(directory_fd)
        named = os.lstat(parent)
        if (held.st_dev, held.st_ino) != (before.st_dev, before.st_ino) or (
            named.st_dev,
            named.st_ino,
        ) != (held.st_dev, held.st_ino):
            raise InstallerError(f"managed parent identity changed: {relative}")
        ensure_contained(root, relative)
        if expected is not None and not snapshot_matches(root, relative, expected):
            raise InstallerError(f"managed destination changed after preflight: {relative}")
        descriptor = os.open(
            temporary,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
            mode,
            dir_fd=directory_fd,
        )
        try:
            offset = 0
            while offset < len(content):
                offset += os.write(descriptor, content[offset:])
            os.fsync(descriptor)
            os.fchmod(descriptor, mode)
        finally:
            os.close(descriptor)
        os.replace(temporary, path.name, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
    except Exception:
        try:
            os.unlink(temporary, dir_fd=directory_fd)
        except OSError:
            pass
        raise
    finally:
        os.close(directory_fd)


def source_inventory(source: Path) -> tuple[str, tuple[Record, ...], str]:
    version_bytes, _ = read_regular(source, "cash-skills.version", expected_mode=0o644)
    try:
        version_text = version_bytes.decode("utf-8")
    except UnicodeDecodeError as error:
        raise InstallerError("bundle version must be UTF-8") from error
    if not version_text.endswith("\n") or version_text.count("\n") != 1:
        raise InstallerError("bundle version must contain one LF-terminated line")
    version = version_text[:-1]
    version_parts(version)

    launcher, _ = read_regular(source, STABLE_PATHS[0], expected_mode=0o755)
    lock, _ = read_regular(source, STABLE_PATHS[1], expected_mode=0o644)
    if lock:
        raise InstallerError("source workspace lock must be empty")
    records: list[Record] = [
        Record("stable", STABLE_PATHS[0], sha256(launcher), 0o755),
        Record("stable", STABLE_PATHS[1], sha256(lock), 0o644),
    ]
    library = source / ".cash-skills" / "lib" / "cash_cli"
    if library.is_symlink() or not library.is_dir():
        raise InstallerError("missing source Cash runtime")
    runtime_paths = sorted(
        (
            path.relative_to(source).as_posix()
            for path in library.rglob("*.py")
            if "__pycache__" not in path.parts
        ),
        key=lambda value: value.encode("utf-8"),
    )
    if not runtime_paths:
        raise InstallerError("source Cash runtime is empty")
    for relative in runtime_paths:
        content, _ = read_regular(source, relative, expected_mode=0o644)
        records.append(Record("runtime", relative, sha256(content), 0o644))
    for variant in (".agents", ".claude"):
        for skill in SKILLS:
            relative = f"{variant}/skills/cash-{skill}/SKILL.md"
            content, _ = read_regular(source, relative, expected_mode=0o644)
            records.append(Record("skill", relative, sha256(content), 0o644))
    runtime_stream = "".join(
        f"{record.path}\t{record.digest}\t{record.mode:04o}\n"
        for record in records
        if record.kind == "runtime"
    ).encode("utf-8")
    return version, tuple(records), sha256(runtime_stream)


def legacy_manifest(source: Path) -> tuple[tuple[str, str], ...]:
    content, _ = read_regular(source, LEGACY_MANIFEST_PATH, expected_mode=0o644)
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError as error:
        raise InstallerError("legacy digest manifest must be UTF-8") from error
    if not text.endswith("\n") or "\r" in text:
        raise InstallerError("legacy digest manifest must be LF terminated")
    rows = [line.split("\t") for line in text.splitlines()]
    if not rows or rows[0] != ["version", "1"]:
        raise InstallerError("legacy digest manifest has an invalid version")
    expected_paths = tuple(
        f"{variant}/skills/spectra-{skill}"
        for variant in (".agents", ".claude")
        for skill in SKILLS
    )
    if len(rows) != len(expected_paths) + 1:
        raise InstallerError("legacy digest manifest has an invalid record count")
    result: list[tuple[str, str]] = []
    for row, expected in zip(rows[1:], expected_paths, strict=True):
        if (
            len(row) != 3
            or row[0] != "skill"
            or row[1] != expected
            or DIGEST_RE.fullmatch(row[2]) is None
        ):
            raise InstallerError(f"legacy digest record is invalid: {expected}")
        result.append((row[1], row[2]))
    return tuple(result)


def inspect_legacy_candidate(
    target: Path,
    relative: str,
    expected_digest: str,
) -> dict[str, int | str]:
    directory = ensure_contained(target, relative)
    metadata = os.lstat(directory)
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise InstallerError(f"legacy candidate is not a real directory: {relative}")
    entries = sorted(entry.name for entry in os.scandir(directory))
    if entries != ["SKILL.md"]:
        raise InstallerError(f"legacy candidate has unknown or extra content: {relative}")
    skill_relative = f"{relative}/SKILL.md"
    content, opened = read_regular(target, skill_relative, expected_mode=0o644)
    if sha256(content) != expected_digest:
        raise InstallerError(f"legacy candidate body drift: {relative}")
    parent = os.lstat(directory.parent)
    return {
        "path": relative,
        "digest": expected_digest,
        "removable": True,
        "directory_device": metadata.st_dev,
        "directory_inode": metadata.st_ino,
        "file_device": opened.st_dev,
        "file_inode": opened.st_ino,
        "parent_device": parent.st_dev,
        "parent_inode": parent.st_ino,
    }


def classify_legacy_candidate(
    target: Path,
    relative: str,
    expected_digest: str,
) -> dict[str, int | str]:
    """Plan-time classification of an existing legacy skill directory.

    Boundary-unsafe shapes (symlink, non-directory, extra content, unsafe mode
    or hard link) still fail closed because they can lead to deletion outside
    the target. A body that simply does not match the known baseline is an
    unrecognised release, not a safety problem: it is preserved and reported
    instead of blocking the whole installation.
    """
    directory = ensure_contained(target, relative)
    metadata = os.lstat(directory)
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise InstallerError(f"legacy candidate is not a real directory: {relative}")
    entries = sorted(entry.name for entry in os.scandir(directory))
    if entries != ["SKILL.md"]:
        raise InstallerError(f"legacy candidate has unknown or extra content: {relative}")
    content, opened = read_regular(target, f"{relative}/SKILL.md")
    if stat.S_IMODE(opened.st_mode) != 0o644 or sha256(content) != expected_digest:
        return {
            "path": relative,
            "digest": sha256(content),
            "removable": False,
        }
    return inspect_legacy_candidate(target, relative, expected_digest)


def legacy_candidates(
    target: Path,
    records: tuple[tuple[str, str], ...],
) -> list[dict[str, int | str]]:
    result: list[dict[str, int | str]] = []
    for relative, digest in records:
        candidate_path = ensure_contained(target, relative)
        if candidate_path.exists() or candidate_path.is_symlink():
            result.append(classify_legacy_candidate(target, relative, digest))
    return result


def installation_inputs(
    source: Path,
    target: Path,
    records: tuple[Record, ...],
) -> tuple[
    tuple[tuple[str, Snapshot], ...],
    tuple[tuple[str, Snapshot], ...],
]:
    ensure_regular_gitignore(target)
    source_paths = (
        "cash-skills.version",
        ".cash.yaml",
        LEGACY_MANIFEST_PATH,
        *GUIDANCE_PATHS,
        *(record.path for record in records),
    )
    target_paths = (
        RECEIPT_PATH,
        ".cash.yaml",
        ".spectra.yaml",
        GITIGNORE_PATH,
        OPENSPEC_CONFIG_PATH,
        *GUIDANCE_PATHS,
        *(record.path for record in records if record.kind != "stable"),
    )
    return snapshots(source, source_paths), snapshots(target, target_paths)


def receipt_bytes(
    version: str,
    generation: str,
    records: Iterable[Record],
    target: Path,
) -> bytes:
    lines = [f"version\t{version}", f"runtime_generation\t{generation}"]
    for record in records:
        if record.kind == "stable":
            metadata = os.lstat(target / record.path)
            lines.append(
                f"stable\t{record.path}\t{record.digest}\t{record.mode:04o}"
                f"\t{metadata.st_dev}\t{metadata.st_ino}"
            )
        else:
            lines.append(
                f"{record.kind}\t{record.path}\t{record.digest}\t{record.mode:04o}"
            )
    return ("\n".join(lines) + "\n").encode("utf-8")


def portable_manifest_bytes(
    version: str,
    generation: str,
    records: Iterable[Record],
) -> bytes:
    version_parts(version)
    if DIGEST_RE.fullmatch(generation) is None:
        raise InstallerError("portable manifest runtime generation is invalid")
    lines = [
        "format\tcash-portable-manifest-v1",
        f"bundle_version\t{version}",
        f"runtime_generation\t{generation}",
    ]
    for record in records:
        mode = "100755" if record.mode & 0o111 else "100644"
        lines.append(
            f"{record.kind}\t{record.path}\t{record.digest}\t{mode}"
        )
    return ("\n".join(lines) + "\n").encode("utf-8")


def portable_relative_path(value: str) -> bool:
    return bool(
        value
        and not value.startswith("/")
        and "\\" not in value
        and all(part not in {"", ".", ".."} for part in value.split("/"))
    )


def parse_portable_manifest(
    content: bytes,
    expected_records: tuple[Record, ...] | None = None,
) -> PortableManifest:
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError as error:
        raise InstallerError("portable manifest must be UTF-8") from error
    if not text.endswith("\n") or "\r" in text or "\x00" in text:
        raise InstallerError("portable manifest must be LF-terminated text")
    rows = [line.split("\t") for line in text.splitlines()]
    if (
        len(rows) < 6
        or rows[0] != ["format", "cash-portable-manifest-v1"]
        or len(rows[1]) != 2
        or rows[1][0] != "bundle_version"
        or len(rows[2]) != 2
        or rows[2][0] != "runtime_generation"
    ):
        raise InstallerError("portable manifest header or record count is invalid")
    version_parts(rows[1][1])
    if DIGEST_RE.fullmatch(rows[2][1]) is None:
        raise InstallerError("portable manifest runtime generation is invalid")
    parsed: list[Record] = []
    seen: set[str] = set()
    for row in rows[3:]:
        if (
            len(row) != 4
            or row[0] not in {"stable", "runtime", "skill"}
            or not portable_relative_path(row[1])
            or row[1] in seen
            or DIGEST_RE.fullmatch(row[2]) is None
            or row[3] not in {"100644", "100755"}
        ):
            raise InstallerError("portable manifest record is invalid")
        seen.add(row[1])
        parsed.append(
            Record(
                row[0],
                row[1],
                row[2],
                0o755 if row[3] == "100755" else 0o644,
            )
        )
    runtime_paths = [
        record.path for record in parsed if record.kind == "runtime"
    ]
    skill_paths = [
        f"{variant}/skills/cash-{skill}/SKILL.md"
        for variant in (".agents", ".claude")
        for skill in SKILLS
    ]
    expected_order = [
        ("stable", STABLE_PATHS[0]),
        ("stable", STABLE_PATHS[1]),
        *(("runtime", path) for path in runtime_paths),
        *(("skill", path) for path in skill_paths),
    ]
    if (
        not runtime_paths
        or runtime_paths
        != sorted(runtime_paths, key=lambda value: value.encode("utf-8"))
        or any(
            not path.startswith(".cash-skills/lib/cash_cli/")
            or not path.endswith(".py")
            for path in runtime_paths
        )
        or [(record.kind, record.path) for record in parsed] != expected_order
        or any(
            record.mode
            != (0o755 if record.path == STABLE_PATHS[0] else 0o644)
            for record in parsed
        )
    ):
        raise InstallerError("portable manifest inventory or order is invalid")
    if expected_records is not None and tuple(
        (record.kind, record.path, record.mode) for record in parsed
    ) != tuple(
        (record.kind, record.path, record.mode) for record in expected_records
    ):
        raise InstallerError("portable manifest inventory differs from expected")
    result = PortableManifest(rows[1][1], rows[2][1], tuple(parsed))
    if portable_manifest_bytes(
        result.version,
        result.generation,
        result.records,
    ) != content:
        raise InstallerError("portable manifest is not canonical")
    runtime_stream = "".join(
        f"{record.path}\t{record.digest}\t{record.mode:04o}\n"
        for record in result.records
        if record.kind == "runtime"
    ).encode("utf-8")
    if sha256(runtime_stream) != result.generation:
        raise InstallerError("portable manifest runtime generation does not match")
    return result


def parse_receipt(content: bytes, expected_records: tuple[Record, ...]) -> Receipt:
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError as error:
        raise InstallerError("receipt must be UTF-8") from error
    if not text.endswith("\n") or "\r" in text or "\x00" in text:
        raise InstallerError("receipt must be LF-terminated text")
    rows = [line.split("\t") for line in text.splitlines()]
    if len(rows) != len(expected_records) + 2:
        raise InstallerError("receipt has an invalid record count")
    if len(rows[0]) != 2 or rows[0][0] != "version":
        raise InstallerError("receipt has an invalid version record")
    version_parts(rows[0][1])
    if (
        len(rows[1]) != 2
        or rows[1][0] != "runtime_generation"
        or DIGEST_RE.fullmatch(rows[1][1]) is None
    ):
        raise InstallerError("receipt has an invalid runtime generation")
    parsed: list[tuple[str, str, str, int, int | None, int | None]] = []
    for row, expected in zip(rows[2:], expected_records, strict=True):
        expected_fields = 6 if expected.kind == "stable" else 4
        if len(row) != expected_fields or row[0] != expected.kind or row[1] != expected.path:
            raise InstallerError(f"receipt record order or shape is invalid: {expected.path}")
        if DIGEST_RE.fullmatch(row[2]) is None or MODE_RE.fullmatch(row[3]) is None:
            raise InstallerError(f"receipt digest or mode is invalid: {expected.path}")
        mode = int(row[3], 8)
        if mode != expected.mode:
            raise InstallerError(f"receipt contract mode is invalid: {expected.path}")
        device = inode = None
        if expected.kind == "stable":
            try:
                device, inode = int(row[4]), int(row[5])
            except ValueError as error:
                raise InstallerError(f"receipt stable identity is invalid: {expected.path}") from error
            if device < 0 or inode <= 0:
                raise InstallerError(f"receipt stable identity is invalid: {expected.path}")
        parsed.append((row[0], row[1], row[2], mode, device, inode))
    runtime_stream = "".join(
        f"{path}\t{digest}\t{mode:04o}\n"
        for kind, path, digest, mode, _, _ in parsed
        if kind == "runtime"
    ).encode("utf-8")
    if sha256(runtime_stream) != rows[1][1]:
        raise InstallerError("receipt runtime generation does not match its records")
    return Receipt(rows[0][1], rows[1][1], tuple(parsed))


def parse_legacy_receipt(
    content: bytes,
    skill_records: tuple[Record, ...],
) -> LegacyReceipt | None:
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError:
        return None
    if not text.endswith("\n") or "\r" in text:
        return None
    rows = [line.split("\t") for line in text.splitlines()]
    if len(rows) != 25 or len(rows[0]) != 2 or rows[0][0] != "version":
        return None
    version_parts(rows[0][1])
    parsed: list[tuple[str, str]] = []
    for row, record in zip(rows[1:], skill_records, strict=True):
        if (
            len(row) != 3
            or row[0] != "sha256"
            or DIGEST_RE.fullmatch(row[1]) is None
            or row[2] != record.path
        ):
            return None
        parsed.append((row[2], row[1]))
    return LegacyReceipt(rows[0][1], tuple(parsed))


def validate_target_prerequisites(
    target: Path,
    *,
    allow_missing_config: bool = False,
) -> None:
    try:
        result = subprocess.run(
            ["git", "-C", str(target), "rev-parse", "--show-toplevel"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise InstallerError("target must be a Git worktree top-level") from error
    if Path(result.stdout.strip()).resolve() != target:
        raise InstallerError("target must be the Git worktree top-level")
    ensure_regular_shape(target, OPENSPEC_CONFIG_PATH)
    try:
        os.lstat(ensure_contained(target, OPENSPEC_CONFIG_PATH))
    except FileNotFoundError:
        if allow_missing_config:
            return
    content, _ = read_regular(target, OPENSPEC_CONFIG_PATH)
    try:
        parse_openspec_config(content.decode("utf-8"), path=OPENSPEC_CONFIG_PATH)
    except (UnicodeDecodeError, ConfigError) as error:
        raise InstallerError(f"invalid target openspec/config.yaml: {error}") from error


def parse_legacy_config(content: bytes) -> bytes:
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError as error:
        raise InstallerError("legacy config must be UTF-8") from error
    values: dict[str, str] = {}
    allowed = {"locale", "tdd", "audit", "parallel_tasks", "spec_dir"}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        if line != line.strip() or ":" not in line:
            raise InstallerError("legacy config contains unsupported YAML")
        key, value = line.split(":", 1)
        value = value.strip()
        if key not in allowed or key in values or not value or any(
            token in value for token in ("#", "[", "]", "{", "}", "&", "*", "!", '"', "'")
        ):
            raise InstallerError(f"legacy config contains unsupported key or value: {key}")
        values[key] = value
    if values.get("spec_dir", "openspec") != "openspec":
        raise InstallerError("legacy config uses a non-default spec_dir")
    values.pop("spec_dir", None)
    output = "".join(f"{key}: {value}\n" for key, value in values.items()).encode("utf-8")
    try:
        parse_cash_config(output.decode("utf-8"), path=".cash.yaml")
    except ConfigError as error:
        raise InstallerError(f"legacy config cannot migrate: {error}") from error
    return output


def config_plan(source: Path, target: Path) -> tuple[bytes | None, bool]:
    source_content, _ = read_regular(source, ".cash.yaml", expected_mode=0o644)
    try:
        parse_cash_config(source_content.decode("utf-8"), path=".cash.yaml")
    except (UnicodeDecodeError, ConfigError) as error:
        raise InstallerError(f"invalid source .cash.yaml: {error}") from error
    cash = optional_snapshot(target, ".cash.yaml")
    if cash.exists:
        try:
            parse_cash_config(cash.content.decode("utf-8"), path=".cash.yaml")  # type: ignore[union-attr]
        except (UnicodeDecodeError, ConfigError) as error:
            raise InstallerError(f"invalid target .cash.yaml: {error}") from error
        return None, False
    legacy = optional_snapshot(target, ".spectra.yaml")
    if legacy.exists:
        return parse_legacy_config(legacy.content or b""), True
    return source_content, True


def openspec_config_plan(snapshot: Snapshot) -> bytes | None:
    if snapshot.exists:
        return None
    try:
        parse_openspec_config(
            OPENSPEC_CONFIG_BASELINE.decode("utf-8"),
            path=OPENSPEC_CONFIG_PATH,
        )
    except (UnicodeDecodeError, ConfigError) as error:
        raise InstallerError(
            f"invalid installer {OPENSPEC_CONFIG_PATH} baseline: {error}"
        ) from error
    return OPENSPEC_CONFIG_BASELINE


def marker_matches(data: bytes, name: bytes, kind: bytes) -> list[re.Match[bytes]]:
    prefix = re.escape(b"<!-- " + name + b":" + kind)
    return list(re.finditer(prefix + rb"(?: [^<>\r\n]+)? -->", data))


def marker_span(data: bytes, name: bytes, label: str) -> tuple[int, int] | None:
    starts = marker_matches(data, name, b"START")
    ends = marker_matches(data, name, b"END")
    if (
        sum(match.end() < len(data) and data[match.end()] == 10 for match in starts)
        != len(starts)
        or sum(match.end() < len(data) and data[match.end()] == 10 for match in ends)
        != len(ends)
    ):
        raise InstallerError(f"malformed {name.decode()} guidance marker: {label}")
    if len(starts) > 1 or len(ends) > 1 or len(starts) != len(ends):
        raise InstallerError(
            f"duplicate or unbalanced {name.decode()} guidance marker: {label}"
        )
    if not starts:
        return None
    begin = starts[0].start()
    finish = ends[0].start()
    if finish < begin:
        raise InstallerError(f"reversed {name.decode()} guidance marker: {label}")
    line_end = data.find(b"\n", finish)
    return begin, len(data) if line_end < 0 else line_end + 1


def canonical_guidance(source: Path, relative: str) -> bytes:
    content, _ = read_regular(source, relative, expected_mode=0o644)
    label = f"source {relative}"
    span = marker_span(content, b"CASH", label)
    if span is None:
        raise InstallerError(f"source guidance has no Cash block: {relative}")
    for kind in (b"START", b"END"):
        expected = b"<!-- CASH:" + kind + b" -->"
        if marker_matches(content, b"CASH", kind)[0].group() != expected:
            raise InstallerError(f"Cash guidance marker has suffix: {label}")
    if marker_span(content, b"SPECTRA", label) is not None:
        raise InstallerError(f"source guidance contains a legacy Spectra block: {relative}")
    return content[span[0] : span[1]]


def render_guidance(source: Path, target: Path, relative: str) -> tuple[bytes, int, bool]:
    canonical = canonical_guidance(source, relative)
    existing = optional_snapshot(target, relative)
    content = existing.content or b""
    cash = marker_span(content, b"CASH", relative)
    legacy = marker_span(content, b"SPECTRA", relative)
    if cash and legacy and not (cash[1] <= legacy[0] or legacy[1] <= cash[0]):
        raise InstallerError(f"nested guidance markers: {relative}")
    spans: list[tuple[int, int, bytes]] = []
    if cash:
        spans.append((cash[0], cash[1], canonical))
    if legacy:
        spans.append((legacy[0], legacy[1], b"" if cash else canonical))
    if not spans:
        separator = b"" if not content or content.endswith(b"\n") else b"\n"
        rendered = content + separator + canonical
    else:
        rendered = content
        for begin, end, replacement in sorted(spans, reverse=True):
            rendered = rendered[:begin] + replacement + rendered[end:]
    return rendered, existing.mode or 0o644, rendered != content


def ensure_regular_shape(root: Path, relative: str) -> None:
    """Reject a file shape that cannot be safely read.

    `read_regular` already rejects a symlink, a hard link and a directory, but
    opening a FIFO for reading blocks until a writer appears, so the shape is
    decided from the lstat metadata before any open.
    """
    path = ensure_contained(root, relative)
    try:
        metadata = os.lstat(path)
    except FileNotFoundError:
        return
    if not stat.S_ISREG(metadata.st_mode):
        raise InstallerError(f"unsafe regular file identity: {relative}")


def ensure_regular_gitignore(target: Path) -> None:
    ensure_regular_shape(target, GITIGNORE_PATH)


def gitignore_terminator(content: bytes) -> bytes:
    index = content.rfind(b"\n")
    if index < 0:
        return b"\n"
    return b"\r\n" if content[index - 1 : index] == b"\r" else b"\n"


def gitignore_plan(existing: Snapshot) -> tuple[bytes, int] | None:
    """Plan the version-control exclusions a target still lacks.

    Lines are compared as exact bytes so a pathname pattern that is not valid
    UTF-8 cannot turn an installable target into `failed`, and a trailing `\\r`
    is tolerated so rules already present in a CRLF file are recognised. The
    comparison is line-exact on purpose: an equivalent spelling is not treated
    as covered, which appends a harmless duplicate rather than mistaking a
    differently scoped rule for this one. Returns None when nothing is missing.
    """
    content = existing.content or b""
    present = {line.removesuffix(b"\r") for line in content.split(b"\n")}
    missing = [rule for rule in GITIGNORE_RULES if rule not in present]
    if not missing:
        return None
    terminator = gitignore_terminator(content)
    separator = b"" if not content or content.endswith(b"\n") else terminator
    appended = b"".join(rule + terminator for rule in missing)
    mode = 0o644 if existing.mode is None else existing.mode
    return content + separator + appended, mode


def report_version_controlled_receipt(target: Path) -> None:
    """Report a receipt that is already tracked, without touching the index.

    The query must read the index rather than ask whether the path is ignored:
    once this contract ships every target ignores the receipt, and gitignore
    does not apply to files that are already tracked. `core.fsmonitor` is
    cleared because reading the index otherwise runs a program named by the
    target's own repository config, which a read-only query must not do.
    """
    try:
        result = subprocess.run(
            [
                "git",
                "-c",
                "core.fsmonitor=",
                "-C",
                str(target),
                "ls-files",
                "--",
                RECEIPT_PATH,
            ],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError:
        return
    if result.returncode != 0 or not result.stdout.strip():
        return
    print(
        f"{target}: {RECEIPT_PATH} is tracked by version control; it records "
        "target-specific inode identity, so any copy with a "
        "different inode fails closed. Run "
        f"`git rm --cached {RECEIPT_PATH}` in that project.",
        file=sys.stderr,
    )


def _validate_hold_path(hook: str, hold_path: str) -> None:
    path = Path(hold_path)
    if not path.is_absolute():
        raise InstallerError(f"invalid installer test hook {hook}: path must be absolute")
    try:
        parent = os.lstat(path.parent)
    except OSError as error:
        raise InstallerError(
            f"invalid installer test hook {hook}: parent is unavailable"
        ) from error
    if stat.S_ISLNK(parent.st_mode) or not stat.S_ISDIR(parent.st_mode):
        raise InstallerError(
            f"invalid installer test hook {hook}: parent must be a real directory"
        )


def _require_absent_hook_file(
    hook: str,
    path: Path,
    *,
    detail: str = "already exists",
) -> None:
    """Reject a hold file that is present when it must not be.

    `detail` distinguishes the stage that made the observation. Preflight and
    the hold entry both reject the same shapes, so without a stage-specific
    message a timing-sensitive test cannot tell which one it exercised and a
    late file created too early would silently downgrade the hold-entry case
    into a duplicate of the preflight case.
    """
    try:
        os.lstat(path)
    except FileNotFoundError:
        return
    except OSError as error:
        raise InstallerError(f"invalid installer test hook {hook}: {error}") from error
    raise InstallerError(f"invalid installer test hook {hook}: {path.name} {detail}")


def test_hooks() -> TestHooks:
    if os.environ.get("CASH_INSTALL_TEST_HOOKS") != "1":
        return TestHooks()
    hold_values = {
        "CASH_INSTALL_HOLD_FILE": os.environ.get("CASH_INSTALL_HOLD_FILE"),
        "CASH_INSTALL_PUBLICATION_HOLD_FILE": os.environ.get(
            "CASH_INSTALL_PUBLICATION_HOLD_FILE"
        ),
    }
    enabled_holds = {
        hook: value for hook, value in hold_values.items() if value is not None
    }
    normalized_holds = {Path(value).resolve() for value in enabled_holds.values()}
    if len(normalized_holds) != len(enabled_holds):
        raise InstallerError("invalid installer test hook: hold paths must be distinct")
    for hook, hold_path in enabled_holds.items():
        _validate_hold_path(hook, hold_path)
        if hook not in CONSUMED_TEST_HOLDS:
            _require_absent_hook_file(hook, Path(f"{hold_path}.ready"))
            _require_absent_hook_file(hook, Path(f"{hold_path}.release"))

    parsed: dict[str, int | None] = {}
    for name in ("CASH_INSTALL_FAIL_AFTER", "CASH_INSTALL_CRASH_AFTER_QUARANTINE"):
        value = os.environ.get(name)
        try:
            parsed[name] = int(value) if value is not None else None
        except ValueError as error:
            raise InstallerError(
                f"invalid installer test hook {name}: expected an integer"
            ) from error
    return TestHooks(
        hold=hold_values["CASH_INSTALL_HOLD_FILE"],
        publication_hold=hold_values["CASH_INSTALL_PUBLICATION_HOLD_FILE"],
        fail_after=parsed["CASH_INSTALL_FAIL_AFTER"],
        fail_after_path=os.environ.get("CASH_INSTALL_FAIL_AFTER_PATH"),
        crash_after_quarantine=parsed["CASH_INSTALL_CRASH_AFTER_QUARANTINE"],
    )


def wait_for_test_hold(hook: str, hold_path: str) -> None:
    _validate_hold_path(hook, hold_path)
    if hook in CONSUMED_TEST_HOLDS:
        return
    ready = Path(f"{hold_path}.ready")
    release = Path(f"{hold_path}.release")
    _require_absent_hook_file(hook, ready, detail="appeared after preflight")
    _require_absent_hook_file(hook, release, detail="appeared after preflight")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(ready, flags, 0o644)
    except OSError as error:
        raise InstallerError(f"invalid installer test hook {hook}: {error}") from error
    try:
        os.write(descriptor, b"ready\n")
    finally:
        os.close(descriptor)
    CONSUMED_TEST_HOLDS.add(hook)
    deadline = time.monotonic() + 10
    while True:
        try:
            metadata = os.lstat(release)
        except FileNotFoundError:
            metadata = None
        except OSError as error:
            raise InstallerError(f"invalid installer test hook {hook}: {error}") from error
        if metadata is not None:
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
                raise InstallerError(
                    f"invalid installer test hook {hook}: release must be a regular file"
                )
            return
        if time.monotonic() >= deadline:
            raise InstallerError("installer test hold timed out")
        time.sleep(0.01)


def acquire_lock(
    target: Path,
    *,
    dry_run: bool,
    create: bool = True,
    logical_contract: bool = False,
) -> tuple[int | None, bool]:
    lock = target / STABLE_PATHS[1]
    existed = lock.exists()
    if dry_run and not existed:
        return None, False
    if not existed and not create:
        raise InstallerError(
            "unfinished installer journal requires an existing stable workspace lock"
        )
    flags = os.O_RDWR | getattr(os, "O_NOFOLLOW", 0)
    if not existed:
        flags |= os.O_CREAT | os.O_EXCL
    try:
        descriptor = os.open(lock, flags, 0o644)
    except FileExistsError:
        try:
            descriptor = os.open(
                lock,
                os.O_RDWR | getattr(os, "O_NOFOLLOW", 0),
            )
            existed = True
        except OSError as error:
            raise InstallerError(f"cannot open stable workspace lock: {error}") from error
    except OSError as error:
        raise InstallerError(f"cannot open stable workspace lock: {error}") from error
    fcntl.flock(descriptor, fcntl.LOCK_EX)
    opened = os.fstat(descriptor)
    named = os.lstat(lock)
    if (
        not stat.S_ISREG(opened.st_mode)
        or opened.st_nlink != 1
        or (
            logical_mode(stat.S_IMODE(opened.st_mode)) != 0o644
            if logical_contract
            else stat.S_IMODE(opened.st_mode) != 0o644
        )
        or opened.st_size != 0
        or (opened.st_dev, opened.st_ino) != (named.st_dev, named.st_ino)
    ):
        os.close(descriptor)
        raise InstallerError("stable workspace lock is unsafe or drifted")
    return descriptor, not existed


def launcher_update(
    source: Path,
    target: Path,
    version: str,
) -> bytes | None:
    source_bytes, _ = read_regular(source, STABLE_PATHS[0], expected_mode=0o755)
    existing = optional_snapshot(target, STABLE_PATHS[0])
    if not existing.exists:
        return source_bytes
    if existing.content == source_bytes and existing.mode == 0o755:
        return None
    if existing.mode != 0o755:
        raise InstallerError("stable launcher has an invalid mode")
    old_digest = sha256(existing.content or b"")
    new_digest = sha256(source_bytes)
    approved = any(
        old_digest == approved_old
        and new_digest == approved_new
        and compare_versions(version, introduced_version) >= 0
        for approved_old, approved_new, introduced_version
        in APPROVED_LAUNCHER_TRANSITIONS
    )
    if not approved:
        raise InstallerError(
            "stable launcher drift requires an approved exact bootstrap migration"
        )
    return source_bytes


def wait_for_inflight_receipt(
    target: Path,
    before: Snapshot,
) -> bool:
    if not (target / STABLE_PATHS[1]).exists():
        return False
    descriptor, _ = acquire_lock(target, dry_run=False)
    try:
        after = optional_snapshot(target, RECEIPT_PATH)
        return (
            after.exists != before.exists
            or after.content != before.content
            or after.device != before.device
            or after.inode != before.inode
        )
    finally:
        if descriptor is not None:
            os.close(descriptor)


def path_is_present(root: Path, relative: str) -> bool:
    path = ensure_contained(root, relative)
    try:
        os.lstat(path)
        return True
    except FileNotFoundError:
        return False
    except OSError as error:
        raise InstallerError(f"cannot inspect {relative}: {error}") from error


def logical_mode(mode: int | None) -> int | None:
    if mode is None:
        return None
    return 0o755 if mode & 0o111 else 0o644


def validate_portable_target(
    target: Path,
    manifest: PortableManifest,
) -> list[str]:
    conflicts: list[str] = []
    for record in manifest.records:
        snapshot = optional_snapshot(target, record.path)
        if not snapshot.exists:
            if record.kind == "stable":
                raise InstallerError(
                    f"portable stable path is missing: {record.path}"
                )
            conflicts.append(record.path)
            continue
        if (
            logical_mode(snapshot.mode) != record.mode
            or sha256(snapshot.content or b"") != record.digest
        ):
            if record.kind == "stable":
                raise InstallerError(
                    f"portable stable path drift: {record.path}"
                )
            conflicts.append(record.path)
    actual_runtime = set(portable_runtime_paths(target))
    expected_runtime = {
        record.path for record in manifest.records if record.kind == "runtime"
    }
    extra = sorted(actual_runtime - expected_runtime)
    if extra:
        raise InstallerError(
            "portable runtime contains unknown paths: " + ", ".join(extra)
        )
    conflicts.extend(sorted(expected_runtime - actual_runtime))
    return sorted(set(conflicts))


def portable_runtime_paths(target: Path) -> tuple[str, ...]:
    runtime_root = target / ".cash-skills" / "lib" / "cash_cli"
    if runtime_root.is_symlink() or not runtime_root.is_dir():
        return ()
    paths: list[str] = []
    try:
        for directory, names, files in os.walk(runtime_root, followlinks=False):
            for name in names:
                candidate = Path(directory) / name
                if candidate.is_symlink():
                    raise InstallerError(
                        "portable runtime directory is a symlink: "
                        + candidate.relative_to(target).as_posix()
                    )
            for name in files:
                if name.endswith(".py"):
                    paths.append(
                        (Path(directory) / name).relative_to(target).as_posix()
                    )
    except OSError as error:
        raise InstallerError(
            f"cannot enumerate portable runtime inventory: {error}"
        ) from error
    return tuple(sorted(paths, key=lambda value: value.encode("utf-8")))


def vendored_planned_paths(
    records: tuple[Record, ...],
) -> tuple[str, ...]:
    return tuple(
        dict.fromkeys(
            (
                *(record.path for record in records),
                PORTABLE_MANIFEST_PATH,
                ".cash.yaml",
                OPENSPEC_CONFIG_PATH,
                *GUIDANCE_PATHS,
                GITIGNORE_PATH,
            )
        )
    )


def git_excluded_paths(target: Path, relatives: Iterable[str]) -> tuple[str, ...]:
    blocked: list[str] = []
    for relative in relatives:
        tracked = subprocess.run(
            [
                "git",
                "-c",
                "core.fsmonitor=",
                "-C",
                str(target),
                "ls-files",
                "--error-unmatch",
                "--",
                relative,
            ],
            check=False,
            capture_output=True,
        )
        if tracked.returncode == 0:
            continue
        if tracked.returncode != 1:
            raise InstallerError(
                f"cannot query Git index for {relative}"
            )
        ignored = subprocess.run(
            [
                "git",
                "-c",
                "core.fsmonitor=",
                "-C",
                str(target),
                "check-ignore",
                "--no-index",
                "-q",
                "--",
                relative,
            ],
            check=False,
            capture_output=True,
        )
        if ignored.returncode == 0:
            blocked.append(relative)
        elif ignored.returncode != 1:
            raise InstallerError(
                f"cannot evaluate Git excludes for {relative}"
            )
    return tuple(blocked)


def require_vendored_paths_committable(
    target: Path,
    relatives: Iterable[str],
) -> None:
    blocked = git_excluded_paths(target, relatives)
    if blocked:
        raise InstallerError(
            "planned vendored paths are excluded by Git: "
            + ", ".join(blocked)
        )


def validate_installed_receipt(
    target: Path,
    receipt: Receipt,
    records: tuple[Record, ...],
) -> list[str]:
    conflicts: list[str] = []
    identity_drift: str | None = None
    for parsed, expected in zip(receipt.records, records, strict=True):
        kind, path, digest, mode, device, inode = parsed
        snapshot = optional_snapshot(target, path)
        if not snapshot.exists:
            raise InstallerError(f"receipt-managed path is missing: {path}")
        actual_digest = sha256(snapshot.content or b"")
        drifted = False
        if kind == "stable":
            if actual_digest != digest:
                raise InstallerError(f"stable receipt content drift: {path}")
            if identity_drift is None and (
                snapshot.mode != mode or snapshot.inode != inode
            ):
                identity_drift = path
        elif actual_digest != digest or snapshot.mode != mode:
            drifted = True
        if path != expected.path:
            raise InstallerError(f"receipt path mismatch: {path}")
        if drifted:
            if identity_drift is not None:
                raise InstallerError(
                    f"stable receipt identity drift: {identity_drift} in {target}; "
                    f"{kind} record drift: {path}. "
                    "Restore that record to the content the receipt records,"
                    " or reinstall from a trusted source, then retry"
                )
            conflicts.append(path)
    if identity_drift is not None:
        raise InstallerError(
            f"stable receipt identity drift: {identity_drift} in {target}. "
            "Run PYTHONPATH=.cash-skills/lib python3 -s -P -B -m cash_cli.installer"
            " --init-receipt in that project; "
            "if .cash-skills/receipt.tsv is tracked by version control, untrack it first because it is machine-local identity"
        )
    return conflicts


def rebind_receipt_stable_identity(content: bytes, target: Path) -> bytes:
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError as error:
        raise InstallerError("cannot rebind non-UTF-8 receipt") from error
    if not text.endswith("\n") or "\r" in text:
        raise InstallerError("cannot rebind malformed receipt")
    rows = [line.split("\t") for line in text.splitlines()]
    rebound: list[str] = []
    stable_seen: set[str] = set()
    for row in rows:
        if len(row) == 6 and row[0] == "stable" and row[1] in STABLE_PATHS:
            metadata = os.lstat(target / row[1])
            if (
                not stat.S_ISREG(metadata.st_mode)
                or metadata.st_nlink != 1
            ):
                raise InstallerError(
                    f"cannot rebind unsafe stable identity: {row[1]}"
                )
            row[4] = str(metadata.st_dev)
            row[5] = str(metadata.st_ino)
            stable_seen.add(row[1])
        rebound.append("\t".join(row))
    if stable_seen != set(STABLE_PATHS):
        raise InstallerError("cannot rebind receipt without both stable records")
    return ("\n".join(rebound) + "\n").encode("utf-8")


class InstallTransaction:
    def __init__(self, target: Path, hooks: TestHooks | None = None):
        self.target = target
        self.hooks = hooks or TestHooks()
        self.operations: list[dict[str, object]] = []

    def add(self, relative: str, content: bytes, mode: int) -> None:
        before = optional_snapshot(self.target, relative)
        self.operations.append(
            {
                "kind": "write",
                "path": relative,
                "content": content,
                "mode": mode,
                "before": before,
            }
        )

    def add_launcher(self, content: bytes) -> None:
        self.operations.append(
            {
                "kind": "launcher",
                "path": STABLE_PATHS[0],
                "content": content,
                "mode": 0o755,
                "before": optional_snapshot(self.target, STABLE_PATHS[0]),
            }
        )

    def add_receipt(
        self,
        version: str,
        generation: str,
        records: tuple[Record, ...],
    ) -> None:
        self.operations.append(
            {
                "kind": "receipt",
                "path": RECEIPT_PATH,
                "version": version,
                "generation": generation,
                "records": records,
                "before": optional_snapshot(self.target, RECEIPT_PATH),
            }
        )

    def add_manifest(self, content: bytes) -> None:
        self.operations.append(
            {
                "kind": "manifest",
                "path": PORTABLE_MANIFEST_PATH,
                "content": content,
                "mode": 0o644,
                "before": optional_snapshot(self.target, PORTABLE_MANIFEST_PATH),
            }
        )

    def add_delete(self, relative: str) -> None:
        self.operations.append(
            {
                "kind": "delete",
                "path": relative,
                "before": optional_snapshot(self.target, relative),
            }
        )

    def add_receipt_delete(self) -> None:
        self.operations.append(
            {
                "kind": "receipt_delete",
                "path": RECEIPT_PATH,
                "before": optional_snapshot(self.target, RECEIPT_PATH),
            }
        )

    def add_legacy_delete(self, candidate: dict[str, int | str]) -> None:
        relative = str(candidate["path"])
        parent = Path(relative).parent.as_posix()
        quarantine = f"{parent}/.cash-legacy-{uuid.uuid4().hex}"
        self.operations.append(
            {
                "kind": "legacy_delete",
                **candidate,
                "quarantine": quarantine,
            }
        )

    @staticmethod
    def _snapshot_fields(before: Snapshot) -> dict[str, object]:
        return {
            "exists": before.exists,
            "content": (
                base64.b64encode(before.content or b"").decode("ascii")
                if before.exists
                else None
            ),
            "mode": before.mode,
            "device": before.device,
            "inode": before.inode,
        }

    def _journal(self, published: int, phase: str = "publishing") -> bytes:
        rows = []
        for operation in self.operations:
            if operation["kind"] in {
                "write",
                "launcher",
                "receipt",
                "manifest",
                "delete",
                "receipt_delete",
            }:
                before = operation["before"]
                assert isinstance(before, Snapshot)
                row = {
                    "kind": operation["kind"],
                    "path": operation["path"],
                    **self._snapshot_fields(before),
                }
                content = operation.get("content")
                if isinstance(content, bytes):
                    row["after_digest"] = sha256(content)
                    row["after_mode"] = operation.get("mode")
                rows.append(row)
            else:
                rows.append(
                    {
                        key: value
                        for key, value in operation.items()
                        if key != "content"
                    }
                )
        return (
            json.dumps(
                {
                    "version": 3,
                    "phase": phase,
                    "published": published,
                    "operations": rows,
                },
                separators=(",", ":"),
            )
            + "\n"
        ).encode("utf-8")

    def commit(self) -> None:
        if not self.operations:
            return
        ensure_directories(self.target, str(Path(JOURNAL_PATH).parent))
        atomic_write(self.target, JOURNAL_PATH, self._journal(0), 0o600)
        published = 0
        phase = "publishing"
        try:
            for operation in self.operations:
                next_published = published + 1
                atomic_write(
                    self.target,
                    JOURNAL_PATH,
                    self._journal(next_published, phase),
                    0o600,
                )
                self._publish_operation(operation)
                published = next_published
                if operation["kind"] == "manifest":
                    phase = "portable_cutover"
                    atomic_write(
                        self.target,
                        JOURNAL_PATH,
                        self._journal(published, phase),
                        0o600,
                    )
                if self.hooks.fail_after == published:
                    raise InstallerError(f"injected publication failure after {published}")
                fail_path = self.hooks.fail_after_path
                if fail_path and operation["path"] == fail_path:
                    raise InstallerError(f"injected publication failure after {fail_path}")
        except Exception:
            if phase == "portable_cutover":
                raise
            try:
                self.rollback(published)
                self.cleanup_journal()
            except Exception as rollback_error:
                raise InstallerError(
                    f"installer rollback failed; recovery journal preserved: {rollback_error}"
                ) from rollback_error
            raise
        atomic_write(
            self.target,
            JOURNAL_PATH,
            self._journal(published, "committed"),
            0o600,
        )
        try:
            self._remove_quarantines(committed=True)
        except Exception as error:
            raise InstallerError(
                f"installer commit cleanup failed; recovery journal preserved: {error}"
            ) from error
        self.cleanup_journal()

    def _publish_operation(self, operation: dict[str, object]) -> None:
        kind = str(operation["kind"])
        if kind in {"write", "launcher", "manifest"}:
            before = operation["before"]
            assert isinstance(before, Snapshot)
            atomic_write(
                self.target,
                str(operation["path"]),
                bytes(operation["content"]),
                int(operation["mode"]),
                expected=before,
            )
            return
        if kind == "receipt":
            before = operation["before"]
            records = operation["records"]
            assert isinstance(before, Snapshot)
            assert isinstance(records, tuple)
            content = receipt_bytes(
                str(operation["version"]),
                str(operation["generation"]),
                records,
                self.target,
            )
            atomic_write(
                self.target,
                RECEIPT_PATH,
                content,
                0o644,
                expected=before,
            )
            return
        if kind == "receipt_delete":
            self._publish_receipt_delete(operation)
            return
        if kind == "delete":
            self._publish_delete(operation)
            return
        self._publish_legacy_delete(operation)

    def _publish_delete(self, operation: dict[str, object]) -> None:
        before = operation["before"]
        assert isinstance(before, Snapshot)
        relative = str(operation["path"])
        if not before.exists:
            return
        if not snapshot_matches(self.target, relative, before):
            raise InstallerError(f"managed path changed before deletion: {relative}")
        ensure_contained(self.target, relative).unlink()

    def _publish_receipt_delete(self, operation: dict[str, object]) -> None:
        before = operation["before"]
        assert isinstance(before, Snapshot)
        if not before.exists:
            return
        if not optional_snapshot(self.target, RECEIPT_PATH).exists:
            return
        if not snapshot_matches(self.target, RECEIPT_PATH, before):
            raise InstallerError("receipt changed before portable cleanup")
        path = ensure_contained(self.target, RECEIPT_PATH)
        path.unlink()

    def rollback(self, published: int) -> None:
        for operation in reversed(self.operations[:published]):
            if operation["kind"] == "legacy_delete":
                original = ensure_contained(self.target, str(operation["path"]))
                quarantine = ensure_contained(self.target, str(operation["quarantine"]))
                if quarantine.exists() and not original.exists():
                    os.rename(quarantine, original)
                elif quarantine.exists() or original.exists():
                    candidate = inspect_legacy_candidate(
                        self.target,
                        str(operation["path"]),
                        str(operation["digest"]),
                    )
                    if (
                        candidate["directory_device"] != operation["directory_device"]
                        or candidate["directory_inode"] != operation["directory_inode"]
                    ):
                        raise InstallerError(
                            f"legacy rollback identity drift: {operation['path']}"
                    )
                continue
            if operation["kind"] == "receipt_delete":
                before = operation["before"]
                assert isinstance(before, Snapshot)
                if before.exists:
                    atomic_write(
                        self.target,
                        RECEIPT_PATH,
                        before.content or b"",
                        before.mode or 0o644,
                    )
                continue
            relative = str(operation["path"])
            before = operation["before"]
            assert isinstance(before, Snapshot)
            path = ensure_contained(self.target, relative)
            if before.exists:
                atomic_write(
                    self.target,
                    relative,
                    before.content or b"",
                    before.mode or 0o644,
                )
            elif operation["kind"] == "launcher":
                continue
            elif path.exists():
                metadata = os.lstat(path)
                if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
                    raise InstallerError(f"rollback target is unsafe: {relative}")
                path.unlink()
        if any(
            operation["kind"] == "launcher"
            for operation in self.operations[:published]
        ):
            old_receipt = next(
                (
                    operation["before"]
                    for operation in self.operations
                    if operation["kind"] in {"receipt", "receipt_delete"}
                    and isinstance(operation.get("before"), Snapshot)
                    and operation["before"].exists
                ),
                None,
            )
            if isinstance(old_receipt, Snapshot):
                rebound = rebind_receipt_stable_identity(
                    old_receipt.content or b"",
                    self.target,
                )
                atomic_write(
                    self.target,
                    RECEIPT_PATH,
                    rebound,
                    old_receipt.mode or 0o644,
                )

    def _publish_legacy_delete(self, operation: dict[str, object]) -> None:
        candidate = inspect_legacy_candidate(
            self.target,
            str(operation["path"]),
            str(operation["digest"]),
        )
        for field in (
            "directory_device",
            "directory_inode",
            "file_device",
            "file_inode",
            "parent_device",
            "parent_inode",
        ):
            if candidate[field] != operation[field]:
                raise InstallerError(
                    f"legacy candidate changed after preflight: {operation['path']}"
                )
        source = ensure_contained(self.target, str(operation["path"]))
        quarantine = ensure_contained(self.target, str(operation["quarantine"]))
        if quarantine.exists():
            raise InstallerError(f"legacy quarantine collision: {operation['quarantine']}")
        os.rename(source, quarantine)

    def _remove_quarantines(self, *, committed: bool = False) -> None:
        removed = 0
        for operation in self.operations:
            if operation["kind"] != "legacy_delete":
                continue
            quarantine = ensure_contained(self.target, str(operation["quarantine"]))
            if not quarantine.exists():
                original = ensure_contained(self.target, str(operation["path"]))
                if committed and not original.exists():
                    continue
                raise InstallerError(
                    f"legacy quarantine disappeared: {operation['quarantine']}"
                )
            candidate = inspect_legacy_candidate(
                self.target,
                str(operation["quarantine"]),
                str(operation["digest"]),
            )
            if (
                candidate["directory_device"] != operation["directory_device"]
                or candidate["directory_inode"] != operation["directory_inode"]
            ):
                raise InstallerError(
                    f"legacy quarantine identity drift: {operation['quarantine']}"
                )
            (quarantine / "SKILL.md").unlink()
            quarantine.rmdir()
            removed += 1
            if self.hooks.crash_after_quarantine == removed:
                os._exit(98)

    def cleanup_journal(self) -> None:
        journal = self.target / JOURNAL_PATH
        if journal.exists():
            journal.unlink()
        for relative in (
            ".cash-skills/state/installer",
            ".cash-skills/state",
        ):
            try:
                (self.target / relative).rmdir()
            except OSError:
                pass


def installer_journal_present(target: Path) -> bool:
    try:
        journal = ensure_contained(target, JOURNAL_PATH)
    except InstallerError as error:
        raise InstallerError(f"unsafe installer journal: {error}") from error
    try:
        metadata = os.lstat(journal)
    except FileNotFoundError:
        return False
    except OSError as error:
        raise InstallerError(f"cannot inspect installer journal: {error}") from error
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
        raise InstallerError("unsafe installer journal")
    return True


def recover_installer(target: Path) -> bool:
    if not installer_journal_present(target):
        return False
    content, _ = read_regular(target, JOURNAL_PATH, expected_mode=0o600)
    try:
        document = json.loads(content)
        schema = document.get("version")
        if schema not in {2, 3}:
            raise InstallerError(
                "cannot recover installer journal; use a matching or newer installer"
            )
        if (
            set(document) != {"version", "phase", "published", "operations"}
            or document["phase"]
            not in {"publishing", "portable_cutover", "committed"}
        ):
            raise ValueError("invalid journal schema")
        operations = document["operations"]
        published = int(document["published"])
        if published < 0 or published > len(operations):
            raise ValueError("invalid publication ledger")
        transaction = InstallTransaction(target)
        for item in operations:
            if item["kind"] in {
                "write",
                "launcher",
                "receipt",
                "manifest",
                "delete",
                "receipt_delete",
            }:
                before = Snapshot(
                    bool(item["exists"]),
                    (
                        base64.b64decode(item["content"])
                        if item["exists"]
                        else None
                    ),
                    item["mode"],
                    item.get("device"),
                    item.get("inode"),
                )
                transaction.operations.append(
                    {
                        "kind": item["kind"],
                        "path": item["path"],
                        "content": b"",
                        "mode": item.get("after_mode", 0o644),
                        "before": before,
                        "after_digest": item.get("after_digest"),
                    }
                )
            else:
                transaction.operations.append(dict(item))
        portable_cutover = document["phase"] == "portable_cutover"
        if schema == 3 and not portable_cutover:
            for index, item in enumerate(operations[:published]):
                if item["kind"] != "manifest":
                    continue
                snapshot = optional_snapshot(target, str(item["path"]))
                portable_cutover = bool(
                    snapshot.exists
                    and snapshot.mode == item.get("after_mode")
                    and sha256(snapshot.content or b"")
                    == item.get("after_digest")
                )
                if portable_cutover and any(
                    later["kind"] != "receipt_delete"
                    for later in operations[index + 1 :]
                ):
                    raise ValueError(
                        "portable manifest is not the final trust-bearing operation"
                    )
        if document["phase"] == "committed" or portable_cutover:
            if published != len(operations):
                if document["phase"] == "committed":
                    raise ValueError("committed journal has incomplete publication ledger")
            for operation in transaction.operations:
                if operation["kind"] == "receipt_delete":
                    transaction._publish_receipt_delete(operation)
            transaction._remove_quarantines(committed=True)
        else:
            transaction.rollback(published)
        transaction.cleanup_journal()
        return True
    except InstallerError:
        raise
    except Exception as error:
        raise InstallerError(f"cannot recover installer journal: {error}") from error


def install_target(
    source: Path,
    target_input: str,
    *,
    dry_run: bool,
    force: bool,
    announce_tracking: bool = True,
) -> str:
    if sys.version_info < (3, 11):
        raise InstallerError("Cash installer requires Python 3.11+")
    if not target_input or target_input == "/" or Path(target_input).is_symlink():
        raise InstallerError("target must be a safe existing directory")
    target = Path(target_input).resolve()
    if not target.is_dir() or target == source:
        raise InstallerError("target must be an existing non-source directory")
    validate_target_prerequisites(target, allow_missing_config=True)
    if path_is_present(target, PORTABLE_MANIFEST_PATH):
        raise InstallerError(
            "target is managed by a portable manifest; use --vendor"
        )
    # Reclassification re-enters this function; the diagnostic stays one line
    # per target rather than one line per retry.
    if announce_tracking:
        report_version_controlled_receipt(target)
    version, records, generation = source_inventory(source)
    legacy_records = legacy_manifest(source)
    for relative in (
        *(record.path for record in records),
        RECEIPT_PATH,
        ".cash.yaml",
        *GUIDANCE_PATHS,
    ):
        ensure_contained(target, relative)
    hooks = test_hooks()

    receipt_snapshot = optional_snapshot(target, RECEIPT_PATH)
    receipt: Receipt | None = None
    legacy_receipt: LegacyReceipt | None = None
    skill_records = tuple(record for record in records if record.kind == "skill")
    if receipt_snapshot.exists:
        try:
            receipt = parse_receipt(receipt_snapshot.content or b"", records)
        except InstallerError as new_error:
            legacy_receipt = parse_legacy_receipt(
                receipt_snapshot.content or b"",
                skill_records,
            )
            if legacy_receipt is None:
                raise new_error
    target_version = receipt.version if receipt else (
        legacy_receipt.version if legacy_receipt else None
    )
    journal_present = installer_journal_present(target)
    if journal_present:
        print(
            f"{target}: unfinished installer journal detected",
            file=sys.stderr,
        )
    if target_version is not None and compare_versions(version, target_version) < 0:
        if journal_present:
            print(
                f"{target}: use the matching newer installer to recover this journal",
                file=sys.stderr,
            )
        return "newer"
    if journal_present and not dry_run:
        lock_existed_before = (target / STABLE_PATHS[1]).exists()
        launcher_existed_before = (target / STABLE_PATHS[0]).exists()
        if launcher_existed_before and not lock_existed_before:
            raise InstallerError("launcher exists without stable workspace lock")
        recovery_lock, _ = acquire_lock(
            target,
            dry_run=False,
            create=False,
        )
        try:
            recovered = recover_installer(target)
        finally:
            if recovery_lock is not None:
                os.close(recovery_lock)
        if recovered:
            return install_target(
                source,
                str(target),
                dry_run=dry_run,
                force=force,
                announce_tracking=False,
            )

    source_config, _ = read_regular(source, ".cash.yaml", expected_mode=0o644)
    try:
        parse_cash_config(source_config.decode("utf-8"), path=".cash.yaml")
    except (UnicodeDecodeError, ConfigError) as error:
        raise InstallerError(f"invalid source .cash.yaml: {error}") from error

    planned_config, config_changed = config_plan(source, target)
    guidance: list[tuple[str, bytes, int, bool]] = []
    for relative in GUIDANCE_PATHS:
        rendered, mode, changed = render_guidance(source, target, relative)
        guidance.append((relative, rendered, mode, changed))
    planned_legacy_candidates = legacy_candidates(target, legacy_records)

    conflicts: list[str] = []
    if receipt is not None:
        conflicts = validate_installed_receipt(target, receipt, records)
        if compare_versions(version, receipt.version) == 0:
            for parsed, source_record in zip(receipt.records, records, strict=True):
                if parsed[2] != source_record.digest:
                    raise InstallerError(
                        f"equal-version source integrity drift: {source_record.path}"
                    )
            if receipt.generation != generation:
                raise InstallerError("equal-version runtime generation drift")
    elif legacy_receipt is not None:
        for (path, expected_digest), record in zip(
            legacy_receipt.records,
            skill_records,
            strict=True,
        ):
            snapshot = optional_snapshot(target, path)
            # The legacy receipt schema records only path and digest; it has no
            # mode field and the legacy installer never guaranteed one. Gating
            # migration on mode would reject installs the old contract produced.
            # The upgrade rewrites每個 managed skill with its contract mode，
            # so mode is normalised by this transaction instead.
            if (
                not snapshot.exists
                or sha256(snapshot.content or b"") != expected_digest
                or path != record.path
            ):
                raise InstallerError(f"legacy receipt drift: {path}")
    else:
        present_skills = [
            record
            for record in skill_records
            if optional_snapshot(target, record.path).exists
        ]
        if len(present_skills) not in {0, 24} and not force:
            if wait_for_inflight_receipt(target, receipt_snapshot):
                return install_target(
                    source,
                    str(target),
                    dry_run=dry_run,
                    force=force,
                    announce_tracking=False,
                )
            raise InstallerError(
                "receipt-less Cash skill inventory is partial",
                result="conflict",
                exit_code=2,
            )
        for record in present_skills:
            snapshot = optional_snapshot(target, record.path)
            if (
                snapshot.mode != 0o644
                or sha256(snapshot.content or b"") != record.digest
            ):
                conflicts.append(record.path)
        runtime_records = [record for record in records if record.kind == "runtime"]
        present_runtime = [
            record for record in runtime_records if optional_snapshot(target, record.path).exists
        ]
        if present_runtime and len(present_runtime) != len(runtime_records):
            conflicts.extend(record.path for record in runtime_records)
    if conflicts and not force:
        if wait_for_inflight_receipt(target, receipt_snapshot):
            return install_target(
                source,
                str(target),
                dry_run=dry_run,
                force=force,
                announce_tracking=False,
            )
        raise InstallerError(
            "managed target drift: " + ", ".join(sorted(set(conflicts))),
            result="conflict",
            exit_code=2,
        )

    source_inputs, target_inputs = installation_inputs(
        source,
        target,
        records,
    )
    lock_existed_before = (target / STABLE_PATHS[1]).exists()
    launcher_existed_before = (target / STABLE_PATHS[0]).exists()
    if launcher_existed_before and not lock_existed_before:
        raise InstallerError("launcher exists without stable workspace lock")
    lock_descriptor, _ = acquire_lock(target, dry_run=dry_run)
    try:
        if hooks.hold and not dry_run:
            wait_for_test_hold("CASH_INSTALL_HOLD_FILE", hooks.hold)
        validate_target_prerequisites(target, allow_missing_config=True)
        locked_source_inputs, locked_target_inputs = installation_inputs(
            source,
            target,
            records,
        )
        locked_legacy_candidates = legacy_candidates(target, legacy_records)
        if (
            locked_source_inputs != source_inputs
            or locked_target_inputs != target_inputs
            or locked_legacy_candidates != planned_legacy_candidates
        ):
            if lock_descriptor is not None:
                os.close(lock_descriptor)
                lock_descriptor = None
            return install_target(
                source,
                str(target),
                dry_run=dry_run,
                force=force,
                announce_tracking=False,
            )
        post_lock_receipt = optional_snapshot(target, RECEIPT_PATH)
        if (
            post_lock_receipt.exists != receipt_snapshot.exists
            or post_lock_receipt.content != receipt_snapshot.content
            or post_lock_receipt.device != receipt_snapshot.device
            or post_lock_receipt.inode != receipt_snapshot.inode
        ):
            if lock_descriptor is not None:
                os.close(lock_descriptor)
                lock_descriptor = None
            return install_target(
                source,
                str(target),
                dry_run=dry_run,
                force=force,
                announce_tracking=False,
            )
        launcher_content = launcher_update(source, target, version)

        transaction = InstallTransaction(target, hooks)
        if launcher_content is not None:
            transaction.add_launcher(launcher_content)
        for record in records:
            if record.kind == "stable":
                continue
            source_content, _ = read_regular(
                source,
                record.path,
                expected_mode=record.mode,
            )
            if sha256(source_content) != record.digest:
                raise InstallerError(
                    f"source managed path changed after preflight: {record.path}"
                )
            current = optional_snapshot(target, record.path)
            if (
                not current.exists
                or current.mode != record.mode
                or sha256(current.content or b"") != record.digest
            ):
                transaction.add(record.path, source_content, record.mode)
        if config_changed and planned_config is not None:
            transaction.add(".cash.yaml", planned_config, 0o644)
        planned_openspec_config = openspec_config_plan(
            dict(target_inputs)[OPENSPEC_CONFIG_PATH]
        )
        if planned_openspec_config is not None:
            transaction.add(
                OPENSPEC_CONFIG_PATH,
                planned_openspec_config,
                0o644,
            )
        for relative, rendered, mode, changed in guidance:
            if changed:
                transaction.add(relative, rendered, mode)
        for candidate in planned_legacy_candidates:
            if candidate.get("removable"):
                transaction.add_legacy_delete(candidate)
        # Fixed last position before the receipt so the operation indices of
        # every earlier publication stay stable.
        planned_gitignore = gitignore_plan(dict(target_inputs)[GITIGNORE_PATH])
        if planned_gitignore is not None:
            transaction.add(GITIGNORE_PATH, *planned_gitignore)

        preserved = [
            str(candidate["path"])
            for candidate in planned_legacy_candidates
            if not candidate.get("removable")
        ]
        if preserved:
            print(
                f"{target}: preserved {len(preserved)} unrecognised legacy skill(s): "
                + ", ".join(preserved),
                file=sys.stderr,
            )

        would_change = bool(transaction.operations) or receipt is None
        if receipt is not None and not would_change:
            expected_receipt = receipt_bytes(version, generation, records, target)
            would_change = expected_receipt != (receipt_snapshot.content or b"")
        if not would_change:
            return "current"
        if dry_run:
            return "update"
        if hooks.publication_hold:
            wait_for_test_hold(
                "CASH_INSTALL_PUBLICATION_HOLD_FILE",
                hooks.publication_hold,
            )
        final_source_inputs, final_target_inputs = installation_inputs(
            source,
            target,
            records,
        )
        if (
            final_source_inputs != source_inputs
            or final_target_inputs != target_inputs
            or legacy_candidates(target, legacy_records) != planned_legacy_candidates
        ):
            raise InstallerError("installation inputs changed after lock acquisition")
        transaction.add_receipt(version, generation, records)
        transaction.commit()
        return "update"
    finally:
        if lock_descriptor is not None:
            os.close(lock_descriptor)


def install_vendored_target(
    source: Path,
    target_input: str,
    *,
    dry_run: bool,
    force: bool,
    announce_tracking: bool = True,
    require_manifest: bool = False,
) -> str:
    if sys.version_info < (3, 11):
        raise InstallerError("Cash installer requires Python 3.11+")
    if not target_input or target_input == "/" or Path(target_input).is_symlink():
        raise InstallerError("vendor target must be a safe existing directory")
    target = Path(target_input).resolve()
    if not target.is_dir() or target == source:
        raise InstallerError("vendor target must be an existing non-source directory")
    validate_target_prerequisites(target, allow_missing_config=True)
    version, records, generation = source_inventory(source)
    manifest_content = portable_manifest_bytes(version, generation, records)
    planned_paths = vendored_planned_paths(records)
    source_watch_paths = (
        "cash-skills.version",
        ".cash.yaml",
        LEGACY_MANIFEST_PATH,
        *GUIDANCE_PATHS,
        *(record.path for record in records),
    )
    target_watch_paths = tuple(
        relative
        for relative in dict.fromkeys(
            (
                *planned_paths,
                RECEIPT_PATH,
                ".spectra.yaml",
                *(record.path for record in records),
            )
        )
        if relative != STABLE_PATHS[1]
    )
    prelock_source_inputs = snapshots(source, source_watch_paths)
    prelock_target_inputs = snapshots(target, target_watch_paths)
    require_vendored_paths_committable(target, planned_paths)
    for relative in (*planned_paths, RECEIPT_PATH):
        ensure_contained(target, relative)
    hooks = test_hooks()

    manifest_snapshot: Snapshot
    manifest: PortableManifest | None = None
    if require_manifest and not path_is_present(target, PORTABLE_MANIFEST_PATH):
        # The batch dispatcher selected this path from a manifest it observed
        # before this call. Losing the manifest in between would silently turn
        # the run into a receipt conversion or a receiptless adoption, both of
        # which may only happen through an explicit --vendor invocation.
        raise InstallerError(
            "portable manifest disappeared before classification; "
            "publish this target with --vendor"
        )
    if path_is_present(target, PORTABLE_MANIFEST_PATH):
        ensure_regular_shape(target, PORTABLE_MANIFEST_PATH)
        manifest_snapshot = optional_snapshot(target, PORTABLE_MANIFEST_PATH)
        if logical_mode(manifest_snapshot.mode) != 0o644:
            raise InstallerError("portable manifest must be non-executable")
        manifest = parse_portable_manifest(
            manifest_snapshot.content or b"",
        )
        obsolete_paths = tuple(
            record.path
            for record in manifest.records
            if record.path not in {current.path for current in records}
        )
        planned_paths = tuple(dict.fromkeys((*planned_paths, *obsolete_paths)))
        require_vendored_paths_committable(target, planned_paths)
        added_watch_paths = tuple(
            path for path in obsolete_paths if path not in target_watch_paths
        )
        if added_watch_paths:
            prelock_target_inputs += snapshots(target, added_watch_paths)
            target_watch_paths += added_watch_paths
    else:
        manifest_snapshot = Snapshot(False)

    receipt_snapshot: Snapshot
    receipt: Receipt | None = None
    if path_is_present(target, RECEIPT_PATH):
        ensure_regular_shape(target, RECEIPT_PATH)
        receipt_snapshot = optional_snapshot(target, RECEIPT_PATH)
        if manifest is None:
            receipt = parse_receipt(receipt_snapshot.content or b"", records)
    else:
        receipt_snapshot = Snapshot(False)

    target_version = manifest.version if manifest else (
        receipt.version if receipt else None
    )
    journal_present = installer_journal_present(target)
    if journal_present and announce_tracking:
        print(f"{target}: unfinished installer journal detected", file=sys.stderr)
    if target_version is not None and compare_versions(version, target_version) < 0:
        if journal_present:
            print(
                f"{target}: use the matching newer installer to recover this journal",
                file=sys.stderr,
            )
        return "newer"
    if journal_present and not dry_run:
        recovery_lock, _ = acquire_lock(
            target,
            dry_run=False,
            create=False,
            logical_contract=True,
        )
        try:
            recovered = recover_installer(target)
        finally:
            if recovery_lock is not None:
                os.close(recovery_lock)
        if recovered:
            return install_vendored_target(
                source,
                str(target),
                dry_run=dry_run,
                force=force,
                announce_tracking=False,
                require_manifest=require_manifest,
            )

    source_config, _ = read_regular(source, ".cash.yaml", expected_mode=0o644)
    try:
        parse_cash_config(source_config.decode("utf-8"), path=".cash.yaml")
    except (UnicodeDecodeError, ConfigError) as error:
        raise InstallerError(f"invalid source .cash.yaml: {error}") from error
    planned_config, config_changed = config_plan(source, target)
    guidance: list[tuple[str, bytes, int, bool]] = []
    for relative in GUIDANCE_PATHS:
        rendered, mode, changed = render_guidance(source, target, relative)
        guidance.append((relative, rendered, mode, changed))
    legacy_records = legacy_manifest(source)
    planned_legacy_candidates = legacy_candidates(target, legacy_records)

    conflicts: list[str] = []
    if manifest is not None:
        conflicts.extend(validate_portable_target(target, manifest))
        if compare_versions(version, manifest.version) == 0 and (
            manifest.generation != generation
            or tuple(
                (record.kind, record.path, record.digest, record.mode)
                for record in manifest.records
            )
            != tuple(
                (record.kind, record.path, record.digest, record.mode)
                for record in records
            )
        ):
            raise InstallerError("equal-version portable source integrity drift")
    elif receipt is not None:
        conflicts.extend(validate_installed_receipt(target, receipt, records))
        if compare_versions(version, receipt.version) == 0:
            if receipt.generation != generation or any(
                parsed[2] != source_record.digest
                for parsed, source_record in zip(
                    receipt.records,
                    records,
                    strict=True,
                )
            ):
                raise InstallerError("equal-version receipt source integrity drift")
    else:
        actual_runtime = set(portable_runtime_paths(target))
        expected_runtime = {
            record.path for record in records if record.kind == "runtime"
        }
        extra_runtime = sorted(actual_runtime - expected_runtime)
        if extra_runtime:
            raise InstallerError(
                "vendored runtime contains unknown paths: "
                + ", ".join(extra_runtime)
            )
        present: list[Record] = []
        exact: list[Record] = []
        for record in records:
            snapshot = optional_snapshot(target, record.path)
            if not snapshot.exists:
                continue
            present.append(record)
            if (
                logical_mode(snapshot.mode) == record.mode
                and sha256(snapshot.content or b"") == record.digest
            ):
                exact.append(record)
            elif record.kind == "stable":
                if record.path == STABLE_PATHS[1]:
                    raise InstallerError("vendored workspace lock drift")
                launcher_update(source, target, version)
            else:
                conflicts.append(record.path)
        if (target / STABLE_PATHS[0]).exists() and not (
            target / STABLE_PATHS[1]
        ).exists():
            raise InstallerError("launcher exists without stable workspace lock")
        complete_exact = len(exact) == len(records)
        present_replaceable = [
            record for record in present if record.kind != "stable"
        ]
        if present_replaceable and not complete_exact and not force:
            return "conflict"
        if force:
            conflicts.extend(
                record.path
                for record in records
                if record.kind != "stable" and record not in exact
            )

    if conflicts and not force:
        return "conflict"

    lock_descriptor, _ = acquire_lock(
        target,
        dry_run=dry_run,
        logical_contract=True,
    )
    try:
        if hooks.hold and not dry_run:
            wait_for_test_hold("CASH_INSTALL_HOLD_FILE", hooks.hold)
        validate_target_prerequisites(target, allow_missing_config=True)
        if source_inventory(source) != (version, records, generation):
            raise InstallerError("vendored source inventory changed before lock acquisition")
        if snapshots(source, source_watch_paths) != prelock_source_inputs:
            raise InstallerError("vendored source inputs changed before lock acquisition")
        if snapshots(target, target_watch_paths) != prelock_target_inputs:
            raise InstallerError("vendored target inputs changed before lock acquisition")
        require_vendored_paths_committable(target, planned_paths)
        launcher_content = launcher_update(source, target, version)

        locked_target_inputs = snapshots(target, target_watch_paths)
        locked_source_inputs = snapshots(source, source_watch_paths)

        transaction = InstallTransaction(target, hooks)
        if launcher_content is not None:
            transaction.add_launcher(launcher_content)
        if manifest is not None:
            current_paths = {record.path for record in records}
            for old_record in manifest.records:
                if old_record.path not in current_paths:
                    transaction.add_delete(old_record.path)
        for record in records:
            if record.kind == "stable":
                continue
            source_content, _ = read_regular(
                source,
                record.path,
                expected_mode=record.mode,
            )
            if sha256(source_content) != record.digest:
                raise InstallerError(
                    f"vendored source digest changed while planning: {record.path}"
                )
            current = optional_snapshot(target, record.path)
            if (
                not current.exists
                or logical_mode(current.mode) != record.mode
                or sha256(current.content or b"") != record.digest
            ):
                transaction.add(record.path, source_content, record.mode)
        if config_changed and planned_config is not None:
            transaction.add(".cash.yaml", planned_config, 0o644)
        openspec_snapshot = dict(locked_target_inputs)[OPENSPEC_CONFIG_PATH]
        planned_openspec_config = openspec_config_plan(openspec_snapshot)
        if planned_openspec_config is not None:
            transaction.add(
                OPENSPEC_CONFIG_PATH,
                planned_openspec_config,
                0o644,
            )
        for relative, rendered, mode, changed in guidance:
            if changed:
                transaction.add(relative, rendered, mode)
        for candidate in planned_legacy_candidates:
            if candidate.get("removable"):
                transaction.add_legacy_delete(candidate)
        planned_gitignore = gitignore_plan(
            dict(locked_target_inputs)[GITIGNORE_PATH]
        )
        if planned_gitignore is not None:
            transaction.add(GITIGNORE_PATH, *planned_gitignore)
        current_manifest = optional_snapshot(target, PORTABLE_MANIFEST_PATH)
        if (
            not current_manifest.exists
            or current_manifest.content != manifest_content
            or logical_mode(current_manifest.mode) != 0o644
        ):
            transaction.add_manifest(manifest_content)
        if receipt_snapshot.exists:
            transaction.add_receipt_delete()

        if not transaction.operations:
            return "current"
        if dry_run:
            return "update"
        if hooks.publication_hold:
            wait_for_test_hold(
                "CASH_INSTALL_PUBLICATION_HOLD_FILE",
                hooks.publication_hold,
            )
        if snapshots(target, target_watch_paths) != locked_target_inputs:
            raise InstallerError("vendored target changed after lock acquisition")
        if snapshots(source, source_watch_paths) != locked_source_inputs:
            raise InstallerError("vendored source changed after lock acquisition")
        require_vendored_paths_committable(target, planned_paths)
        transaction.commit()
        return "update"
    finally:
        if lock_descriptor is not None:
            os.close(lock_descriptor)


def bootstrap_source(source: Path, *, dry_run: bool) -> str:
    if sys.version_info < (3, 11):
        raise InstallerError("Cash installer requires Python 3.11+")
    validate_target_prerequisites(source)
    version, records, generation = source_inventory(source)
    source_config, _ = read_regular(source, ".cash.yaml", expected_mode=0o644)
    try:
        parse_cash_config(source_config.decode("utf-8"), path=".cash.yaml")
    except (UnicodeDecodeError, ConfigError) as error:
        raise InstallerError(f"invalid source .cash.yaml: {error}") from error
    for relative in (PORTABLE_MANIFEST_PATH, RECEIPT_PATH):
        ensure_contained(source, relative)
        if path_is_present(source, relative):
            ensure_regular_shape(source, relative)
    manifest_content = portable_manifest_bytes(version, generation, records)

    lock_descriptor, _ = acquire_lock(source, dry_run=dry_run)
    try:
        validate_target_prerequisites(source)
        locked_version, locked_records, locked_generation = source_inventory(source)
        if (
            locked_version != version
            or locked_records != records
            or locked_generation != generation
        ):
            raise InstallerError("source inventory changed while acquiring lock")
        locked_config, _ = read_regular(source, ".cash.yaml", expected_mode=0o644)
        if locked_config != source_config:
            raise InstallerError("source .cash.yaml changed while acquiring lock")

        manifest_snapshot = optional_snapshot(source, PORTABLE_MANIFEST_PATH)
        receipt_snapshot = optional_snapshot(source, RECEIPT_PATH)
        transaction = InstallTransaction(source)
        if (
            not manifest_snapshot.exists
            or manifest_snapshot.content != manifest_content
            or manifest_snapshot.mode != 0o644
        ):
            transaction.add_manifest(manifest_content)
        if receipt_snapshot.exists:
            transaction.add_receipt_delete()
        if not transaction.operations:
            return "current"
        if dry_run:
            return "would-bootstrap"
        transaction.commit()
        return "bootstrap"
    finally:
        if lock_descriptor is not None:
            os.close(lock_descriptor)


def managed_skill_paths() -> tuple[str, ...]:
    return tuple(
        f"{variant}/skills/cash-{skill}/SKILL.md"
        for variant in (".agents", ".claude")
        for skill in SKILLS
    )


def init_source_layout(root: Path) -> bool:
    """Detect the canonical source repository from the launcher's marker set.

    The launcher also requires the root to be the Git worktree top-level; the
    caller has already established that, so only the file shapes and the
    bundle version file remain.

    Unlike the launcher this predicate does not gate on contract modes. A
    source repository cloned under umask `002` carries `0664`/`0775` markers,
    and none of them belong to the managed inventory that mode normalisation
    repairs, so a mode-equal predicate would silently classify that clone as
    an ordinary target and sign a receipt for it.
    """
    required: list[str] = [
        "install-cash-skills.fish",
        "cash-skills.version",
        ".cash.yaml",
        OPENSPEC_CONFIG_PATH,
        "CASH-SKILLS.md",
        LEGACY_MANIFEST_PATH,
        ".cash-skills/lib/cash_cli/__init__.py",
        ".cash-skills/lib/cash_cli/installer.py",
        ".cash-skills/lib/cash_cli/main.py",
        ".cash-skills/lib/cash_cli/workspace.py",
        *managed_skill_paths(),
    ]
    try:
        for relative in required:
            metadata = os.lstat(root / relative)
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
                return False
        content, _ = read_regular(root, "cash-skills.version")
        text = content.decode("ascii")
        if not text.endswith("\n") or text.count("\n") != 1:
            return False
        version_parts(text[:-1])
    except (OSError, UnicodeError, InstallerError):
        return False
    return True


def init_validate_config(root: Path) -> None:
    try:
        ensure_regular_shape(root, OPENSPEC_CONFIG_PATH)
        content, _ = read_regular(root, OPENSPEC_CONFIG_PATH)
        parse_openspec_config(content.decode("utf-8"), path=OPENSPEC_CONFIG_PATH)
    except (InstallerError, UnicodeDecodeError, ConfigError) as error:
        raise InitError(
            "init_config_invalid",
            f"invalid {OPENSPEC_CONFIG_PATH}: {error}",
        ) from error


def init_manifest_present(root: Path) -> bool:
    try:
        return path_is_present(root, PORTABLE_MANIFEST_PATH)
    except InstallerError as error:
        raise InitError("init_vendored_bundle", str(error)) from error


def init_managed_shape(root: Path, relative: str) -> Path:
    try:
        path = ensure_contained(root, relative)
    except InstallerError as error:
        raise InitError("init_inventory_invalid", str(error)) from error
    try:
        metadata = os.lstat(path)
    except FileNotFoundError as error:
        raise InitError(
            "init_inventory_invalid",
            f"managed path is missing: {relative}",
        ) from error
    except OSError as error:
        raise InitError(
            "init_inventory_invalid",
            f"cannot inspect managed path {relative}: {error}",
        ) from error
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
        raise InitError(
            "init_inventory_invalid",
            f"unsafe managed file identity: {relative}",
        )
    return path


def init_acquire_lock(root: Path) -> int:
    """Take the stable workspace lock without creating it and without a mode gate.

    The contract mode is applied by mode normalisation after the lock is held,
    so gating the lock on `0644` here would reject exactly the umask-skewed
    clone this mode exists to repair. Emptiness is still gated, because a
    non-empty lock leaves the CLI failing with `workspace_lock_invalid` after
    an otherwise successful initialization, and repairing a stable file is a
    declared Non-Goal.
    """
    path = init_managed_shape(root, STABLE_PATHS[1])
    try:
        descriptor = os.open(path, os.O_RDWR | getattr(os, "O_NOFOLLOW", 0))
    except OSError as error:
        raise InitError(
            "init_inventory_invalid",
            f"cannot open stable workspace lock: {error}",
        ) from error
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        opened = os.fstat(descriptor)
        named = os.lstat(path)
        if (
            not stat.S_ISREG(opened.st_mode)
            or opened.st_nlink != 1
            or opened.st_size != 0
            or (opened.st_dev, opened.st_ino) != (named.st_dev, named.st_ino)
        ):
            raise InitError(
                "init_inventory_invalid",
                f"stable workspace lock must be an empty regular file: {STABLE_PATHS[1]}",
            )
    except BaseException:
        os.close(descriptor)
        raise
    return descriptor


def init_inventory(root: Path) -> tuple[tuple[str, str, int], ...]:
    """(kind, path, contract mode) for every managed path, in receipt order."""
    library = root / ".cash-skills" / "lib" / "cash_cli"
    if library.is_symlink() or not library.is_dir():
        raise InitError(
            "init_inventory_invalid",
            "managed path is missing: .cash-skills/lib/cash_cli",
        )
    # The exclusion is judged on the path relative to the target root, so a
    # project that happens to live under an ancestor directory named
    # `__pycache__` does not report its whole runtime as missing.
    present = set()
    for path in library.rglob("*.py"):
        relative = path.relative_to(root)
        if "__pycache__" not in relative.parts:
            present.add(relative.as_posix())
    expected = set(BUNDLE_RUNTIME_PATHS)
    if present != expected:
        missing = sorted(expected - present)
        extra = sorted(present - expected)
        raise InitError(
            "init_inventory_invalid",
            "runtime inventory does not match the canonical set: "
            f"missing={missing} extra={extra}",
        )
    entries: list[tuple[str, str, int]] = [
        ("stable", STABLE_PATHS[0], 0o755),
        ("stable", STABLE_PATHS[1], 0o644),
    ]
    entries.extend(("runtime", relative, 0o644) for relative in BUNDLE_RUNTIME_PATHS)
    entries.extend(("skill", relative, 0o644) for relative in managed_skill_paths())
    return tuple(entries)


def init_normalize_modes(root: Path, inventory: tuple[tuple[str, str, int], ...]) -> None:
    """Absorb the umask a clone applied, after validating every managed shape.

    Shape validation is a separate pass so an unsafe entry cannot leave an
    earlier entry already chmod-ed. A `chmod` that itself fails part way
    through can still leave the inventory partly normalised; only file content
    is guaranteed untouched on every failure path.
    """
    pending: list[tuple[Path, str, int]] = []
    for _, relative, mode in inventory:
        path = init_managed_shape(root, relative)
        if stat.S_IMODE(os.lstat(path).st_mode) != mode:
            pending.append((path, relative, mode))
    for path, relative, mode in pending:
        try:
            descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        except OSError as error:
            raise InitError(
                "init_inventory_invalid",
                f"cannot open managed path {relative}: {error}",
            ) from error
        try:
            opened = os.fstat(descriptor)
            if not stat.S_ISREG(opened.st_mode) or opened.st_nlink != 1:
                raise InitError(
                    "init_inventory_invalid",
                    f"unsafe managed file identity: {relative}",
                )
            os.fchmod(descriptor, mode)
        except OSError as error:
            raise InitError(
                "init_inventory_invalid",
                f"cannot normalise mode for {relative}: {error}",
            ) from error
        finally:
            os.close(descriptor)


def init_records(
    root: Path,
    inventory: tuple[tuple[str, str, int], ...],
) -> tuple[Record, ...]:
    records: list[Record] = []
    for kind, relative, mode in inventory:
        try:
            content, _ = read_regular(root, relative, expected_mode=mode)
        except InstallerError as error:
            raise InitError("init_inventory_invalid", str(error)) from error
        records.append(Record(kind, relative, sha256(content), mode))
    return tuple(records)


def init_publish_receipt(root: Path, records: tuple[Record, ...]) -> str:
    runtime_stream = "".join(
        f"{record.path}\t{record.digest}\t{record.mode:04o}\n"
        for record in records
        if record.kind == "runtime"
    ).encode("utf-8")
    try:
        expected = receipt_bytes(BUNDLE_VERSION, sha256(runtime_stream), records, root)
        # The shape is decided from lstat before any open: opening a FIFO for
        # reading blocks until a writer appears, and the exclusive workspace
        # lock is already held, so a blocking open would wedge every command.
        ensure_regular_shape(root, RECEIPT_PATH)
        snapshot = optional_snapshot(root, RECEIPT_PATH)
    except (InstallerError, OSError) as error:
        raise InitError("init_write_failed", str(error)) from error
    # A byte-equal receipt whose mode drifted still fails the launcher's
    # `0644` gate, so equivalence includes the contract mode and the drifted
    # mode is repaired by a normal re-issue rather than reported as current.
    if snapshot.exists and snapshot.content == expected and snapshot.mode == 0o644:
        return "current"
    if snapshot.exists:
        try:
            parse_receipt(snapshot.content or b"", records)
        except InstallerError as error:
            print(f"{root}: replacing an invalid {RECEIPT_PATH}: {error}", file=sys.stderr)
    try:
        directory = ensure_contained(root, ".cash-skills")
        metadata = os.lstat(directory)
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise InstallerError("unsafe managed directory: .cash-skills")
        atomic_write(root, RECEIPT_PATH, expected, 0o644, expected=snapshot)
    except (InstallerError, OSError) as error:
        raise InitError("init_write_failed", str(error)) from error
    return "initialized"


def init_receipt() -> str:
    if sys.version_info < (3, 11):
        raise InitError(
            "init_python_version",
            "Cash receipt initialization requires Python 3.11+",
        )
    root = Path.cwd().resolve()
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--show-toplevel"],
            check=True,
            capture_output=True,
            text=True,
        )
        top_level = Path(result.stdout.strip()).resolve()
    except (OSError, subprocess.CalledProcessError) as error:
        raise InitError(
            "init_outside_worktree",
            "--init-receipt must run from the Git worktree top-level",
        ) from error
    if top_level != root:
        raise InitError(
            "init_outside_worktree",
            f"--init-receipt must run from the Git worktree top-level: {top_level}",
        )
    if init_source_layout(root):
        raise InitError(
            "init_source_repo",
            "this is the canonical Cash source repository; run "
            "./install-cash-skills.fish --self from the project root",
        )
    if init_manifest_present(root):
        raise InitError(
            "init_vendored_bundle",
            "this target is managed by a portable manifest; "
            "--init-receipt is not permitted",
        )
    init_validate_config(root)
    descriptor = init_acquire_lock(root)
    try:
        if init_manifest_present(root):
            raise InitError(
                "init_vendored_bundle",
                "a portable manifest appeared while acquiring the workspace lock",
            )
        inventory = init_inventory(root)
        init_normalize_modes(root, inventory)
        return init_publish_receipt(root, init_records(root, inventory))
    finally:
        os.close(descriptor)


def safe_home() -> Path:
    value = os.environ.get("HOME", "")
    path = Path(value)
    if not value or not path.is_absolute() or value == "/" or path.is_symlink():
        raise InstallerError("HOME must be an absolute non-root real directory")
    resolved = path.resolve()
    if not resolved.is_dir() or resolved == Path("/"):
        raise InstallerError("HOME must be an existing directory")
    return resolved


def registry_path() -> Path:
    return safe_home() / ".config" / "cash-skills" / "projects.txt"


def registry_publication_mode(source: Path, record: str) -> str:
    """Decide which publication path one registry record takes.

    This is a dispatch decision, not a property of the target: the canonical
    source carries a regular manifest yet is answered "receipt" so that the
    receipt path keeps producing its existing non-source diagnostic for a
    hand-edited registry record.

    Read-only and never raising: the whole body is evaluated inside one try so
    that an unreadable, malformed or unsafe target falls through to the
    receipt-based catch-all, where the existing publication path produces its
    own diagnostic. Only a manifest that is both present and a regular file
    selects the vendored path, because that path reads the manifest before
    validating its shape and opening a FIFO would block forever.
    """
    try:
        target = Path(record).resolve()
        if target == source:
            return "receipt"
        if path_is_present(target, PORTABLE_MANIFEST_PATH):
            ensure_regular_shape(target, PORTABLE_MANIFEST_PATH)
            return "vendor"
        return "receipt"
    except Exception:
        return "receipt"


def read_registry() -> list[str]:
    root = safe_home()
    path = registry_path()
    relative = path.relative_to(root).as_posix()
    snapshot = optional_snapshot(root, relative)
    if not snapshot.exists:
        return []
    content = snapshot.content or b""
    try:
        lines = content.decode("utf-8").split("\n")
    except UnicodeDecodeError as error:
        raise InstallerError("registry must be UTF-8") from error
    records: list[str] = []
    for line_number, line in enumerate(lines, start=1):
        if line == "":
            continue
        if any(ord(character) < 32 or ord(character) == 127 for character in line):
            raise InstallerError(
                f"registry line {line_number} contains an ASCII control character"
            )
        candidate = Path(line)
        components = line.split("/")
        if (
            not candidate.is_absolute()
            or candidate.as_posix() != line
            or any(part in {"", ".", ".."} for part in components[1:])
        ):
            raise InstallerError(
                f"registry line {line_number} path is not canonical"
            )
        current = Path(candidate.anchor)
        fully_existing = True
        for part in candidate.parts[1:]:
            current /= part
            try:
                metadata = os.lstat(current)
            except FileNotFoundError:
                fully_existing = False
                break
            except OSError as error:
                raise InstallerError(
                    f"cannot inspect registry line {line_number}: {error}"
                ) from error
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
                raise InstallerError(
                    f"registry line {line_number} path is not canonical"
                )
        if fully_existing and candidate.resolve().as_posix() != line:
            raise InstallerError(
                f"registry line {line_number} path is not canonical"
            )
        if line not in records:
            records.append(line)
    return records


def write_registry(records: list[str]) -> None:
    path = registry_path()
    root = safe_home()
    relative = path.relative_to(root).as_posix()
    ensure_directories(root, str(Path(relative).parent))
    atomic_write(root, relative, "".join(f"{record}\n" for record in records).encode(), 0o644)


def canonical_target(value: str, *, allow_missing: bool = False) -> str:
    if not value or any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise InstallerError("project path is invalid")
    path = Path(value)
    if path.exists():
        if path.is_symlink() or not path.is_dir():
            raise InstallerError("project must be a real directory")
        return path.resolve().as_posix()
    if allow_missing and path.is_absolute() and value != "/":
        return path.as_posix()
    raise InstallerError("project must be an existing directory")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(prog="install-cash-skills.fish")
    modes = result.add_mutually_exclusive_group(required=True)
    modes.add_argument("--target", metavar="<project>")
    modes.add_argument("--vendor", metavar="<project>")
    modes.add_argument("--self", action="store_true")
    modes.add_argument("--register", metavar="<project>")
    modes.add_argument("--unregister", metavar="<project>")
    modes.add_argument("--list", action="store_true")
    modes.add_argument("--all", action="store_true")
    modes.add_argument("--init-receipt", action="store_true")
    result.add_argument("--dry-run", action="store_true")
    result.add_argument("--force", action="store_true")
    return result


def run(arguments: list[str] | None = None) -> int:
    options = parser().parse_args(arguments)
    source = Path(__file__).resolve().parents[3]
    for name in ("target", "vendor", "register", "unregister"):
        if getattr(options, name) == "":
            raise InstallerError(
                f"--{name} requires a non-empty value",
                exit_code=2,
            )
    if options.dry_run and not (
        options.target is not None
        or options.vendor is not None
        or options.all
        or options.self
    ):
        raise InstallerError(
            "--dry-run requires --target, --vendor, --all, or --self",
            exit_code=2,
        )
    if options.force and not (
        options.target is not None or options.vendor is not None or options.all
    ):
        raise InstallerError(
            "--force requires --target, --vendor, or --all",
            exit_code=2,
        )
    if options.init_receipt:
        try:
            result = init_receipt()
        except InitError as error:
            sys.stdout.write(
                json.dumps(
                    {"error": {"code": error.code, "message": str(error)}},
                    ensure_ascii=False,
                    separators=(",", ":"),
                )
                + "\n"
            )
            return 1
        print(result)
        return 0
    if options.self:
        result = bootstrap_source(source, dry_run=options.dry_run)
        print(f"Result: {result}")
        return 0
    if options.target is not None:
        result = install_target(
            source,
            options.target,
            dry_run=options.dry_run,
            force=options.force,
        )
        print(f"Result: {result}")
        return 0
    if options.vendor is not None:
        result = install_vendored_target(
            source,
            options.vendor,
            dry_run=options.dry_run,
            force=options.force,
        )
        print(f"Result: {result}")
        return 0
    records = read_registry()
    if options.register is not None:
        project = canonical_target(options.register)
        if Path(project) == source:
            raise InstallerError("project must be an existing non-source directory")
        validate_target_prerequisites(
            Path(project),
            allow_missing_config=True,
        )
        if project not in records:
            records.append(project)
            write_registry(records)
        print(f"registered: {project}")
        return 0
    if options.unregister is not None:
        project = canonical_target(options.unregister, allow_missing=True)
        updated = [record for record in records if record != project]
        if updated != records:
            write_registry(updated)
        print(f"unregistered: {project}")
        return 0
    if options.list:
        print("\n".join(records))
        return 0
    counts = {
        "updated": 0,
        "would-update": 0,
        "current": 0,
        "newer": 0,
        "conflict": 0,
        "failed": 0,
    }
    for record in records:
        suffix = ""
        try:
            mode = registry_publication_mode(source, record)
            suffix = " (vendored)" if mode == "vendor" else ""
            if mode == "vendor":
                result = install_vendored_target(
                    source,
                    record,
                    dry_run=options.dry_run,
                    force=options.force,
                    require_manifest=True,
                )
            else:
                result = install_target(
                    source,
                    record,
                    dry_run=options.dry_run,
                    force=options.force,
                )
            label = "would-update" if options.dry_run and result == "update" else (
                "updated" if result == "update" else result
            )
        except InstallerError as error:
            label = error.result or "failed"
            print(f"{record}: {error}", file=sys.stderr)
        counts[label] += 1
        print(f"{label}: {record}{suffix}")
    print(
        "Summary: "
        + " ".join(f"{key}={value}" for key, value in counts.items())
    )
    return 1 if counts["conflict"] or counts["failed"] else 0


def main() -> int:
    try:
        return run()
    except InstallerError as error:
        print(f"Error: {error}", file=sys.stderr)
        if error.result:
            print(f"Result: {error.result}")
        return error.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
