from __future__ import annotations

import difflib
import hashlib
import json
import os
import re
import stat
import subprocess
from collections.abc import Sequence
from pathlib import Path

from ..errors import CashError
from ..workspace import Workspace
from .tasks import _validate_touched


_HEX = re.compile(r"[0-9a-f]{40,64}\Z")
_LAYERS = ("committed", "staged", "unstaged", "untracked")


def _git_environment() -> dict[str, str]:
    env = os.environ.copy()
    # Scope is always relative to the discovered workspace.  Ignore caller
    # overrides that could redirect Git to a different repository or index.
    for key in tuple(env):
        if key in {
            "GIT_DIR",
            "GIT_WORK_TREE",
            "GIT_INDEX_FILE",
            "GIT_OBJECT_DIRECTORY",
            "GIT_ALTERNATE_OBJECT_DIRECTORIES",
            "GIT_COMMON_DIR",
        } or key.startswith("GIT_CONFIG_") or key.startswith("GIT_TRACE"):
            env.pop(key, None)
    env["GIT_OPTIONAL_LOCKS"] = "0"
    env["GIT_TRACE_FSMONITOR"] = "0"
    env["GIT_NO_LAZY_FETCH"] = "1"
    return env


def _git(workspace: Workspace, *args: str, check: bool = True, input_bytes: bytes | None = None) -> bytes:
    env = _git_environment()
    command = [
        "git",
        "-C",
        str(workspace.root),
        "-c",
        "core.fsmonitor=false",
        "-c",
        "core.untrackedCache=false",
        "-c",
        "diff.external=",
        "-c",
        "diff.textconv=",
        *args,
    ]
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            env=env,
            timeout=10,
            input=input_bytes,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise CashError("execution_error", "Git scope observation failed.", 1) from error
    if check and result.returncode != 0:
        raise CashError(
            "execution_error",
            result.stderr.decode("utf-8", errors="replace").strip() or "Git scope observation failed.",
            1,
        )
    return result.stdout


def _git_exit(workspace: Workspace, *args: str) -> int:
    """Run a read-only Git probe when only its exit status is needed."""
    env = _git_environment()
    command = [
        "git", "-C", str(workspace.root),
        "-c", "core.fsmonitor=false",
        "-c", "core.untrackedCache=false",
        "-c", "diff.external=",
        "-c", "diff.textconv=",
        *args,
    ]
    try:
        return subprocess.run(
            command,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=env,
            timeout=10,
        ).returncode
    except (OSError, subprocess.TimeoutExpired) as error:
        raise CashError("execution_error", "Git scope observation failed.", 1) from error


def _revision(workspace: Workspace, value: str) -> str | None:
    result = _git(
        workspace,
        "rev-parse",
        "--verify",
        "--end-of-options",
        f"{value}^{{commit}}",
        check=False,
    )
    if result:
        return result.decode("ascii", errors="strict").strip()
    return None


def _head(workspace: Workspace) -> str | None:
    return _revision(workspace, "HEAD")


def _ensure_base(workspace: Workspace, base: str, head: str | None) -> str:
    if head is None:
        raise CashError("invalid_base", "A base revision requires a born HEAD.", 2)
    resolved = _revision(workspace, base)
    if resolved is None:
        raise CashError("invalid_base", "Base revision is not a local commit.", 2)
    if _git_exit(workspace, "merge-base", "--is-ancestor", resolved, head) != 0:
        raise CashError("invalid_base", "Base revision is not an ancestor of HEAD.", 2)
    return resolved


def _canonical_path(value: str) -> str:
    path = Path(value)
    if path.is_absolute() or not value or ".." in path.parts or "\\" in value:
        raise CashError("invalid_arguments", "Scope paths must be root-contained literal paths.")
    return path.as_posix()


def _read_json(workspace: Workspace, relative: str) -> object:
    try:
        return json.loads(workspace.read_text(relative))
    except (OSError, ValueError, UnicodeError) as error:
        raise CashError("scope_insufficient", "Cash touched state is invalid.", 2, relative) from error


def _allowlist(workspace: Workspace, change: str) -> set[str]:
    relative = f".cash-skills/state/touched/{change}.json"
    if not workspace.is_file(relative):
        raise CashError("scope_insufficient", "Cash touched state is missing.", 2, relative)
    value = _read_json(workspace, relative)
    if not isinstance(value, dict):
        raise CashError("scope_insufficient", "Cash touched state is invalid.", 2, relative)
    try:
        validated = _validate_touched(value, change)
        files = validated["files"]
        if not isinstance(files, list):
            raise ValueError("files is not a list")
        canonical = [_canonical_path(item) for item in files]
    except (CashError, TypeError, ValueError) as error:
        if isinstance(error, CashError) and error.code == "scope_insufficient":
            raise
        raise CashError("scope_insufficient", "Cash touched state is invalid.", 2, relative) from error
    if canonical != sorted(set(canonical), key=lambda item: item.encode("utf-8")):
        raise CashError("scope_insufficient", "Cash touched allowlist is not canonical.", 2, relative)
    return set(canonical)


def _parse_index_status(workspace: Workspace, head: str | None) -> list[dict[str, object]]:
    diff_args = ["diff", "--cached", "--name-status", "--find-renames", "-z"]
    if head:
        diff_args.append(head)
    diff_args.extend(("--",))
    raw = _git(workspace, *diff_args)
    records = raw.decode("utf-8", errors="surrogateescape").split("\0")
    result: list[dict[str, object]] = []
    index = 0
    while index < len(records):
        row = records[index]
        index += 1
        if not row:
            continue
        if row.startswith(("R", "C")):
            if index + 1 >= len(records):
                raise CashError("execution_error", "Git rename record is malformed.", 1)
            result.append({"path": records[index + 1], "old_path": records[index], "xy": row})
            index += 2
        else:
            if index >= len(records):
                raise CashError("execution_error", "Git diff record is malformed.", 1)
            result.append({"path": records[index], "old_path": None, "xy": row})
            index += 1
    untracked = _git(workspace, "ls-files", "--others", "--exclude-standard", "-z", "--")
    for path in untracked.decode("utf-8", errors="surrogateescape").split("\0"):
        if path:
            result.append({"path": path, "old_path": None, "xy": "??", "untracked": True})
    return result


def _index_entries(workspace: Workspace) -> dict[str, tuple[str, str]]:
    raw = _git(workspace, "ls-files", "--stage", "-z")
    entries: dict[str, tuple[str, str]] = {}
    for record in raw.decode("utf-8", errors="surrogateescape").split("\0"):
        if not record:
            continue
        header, path = record.split("\t", 1)
        fields = header.split()
        if len(fields) != 3 or fields[2] != "0":
            raise CashError("scope_insufficient", "Unmerged index entries are unsupported.", 2)
        entries[path] = (fields[0], fields[1])
    return entries


def _index_flags(workspace: Workspace) -> dict[str, str]:
    raw = _git(workspace, "ls-files", "-v", "--stage", "-z")
    flags: dict[str, str] = {}
    for record in raw.decode("utf-8", errors="surrogateescape").split("\0"):
        if not record:
            continue
        flag, remainder = record[:1], record[2:]
        try:
            _, path = remainder.split("\t", 1)
        except ValueError as error:
            raise CashError("execution_error", "Git index record is malformed.", 1) from error
        flags[path] = flag
    return flags


def _tree_entries(workspace: Workspace, revision: str) -> dict[str, tuple[str, str]]:
    raw = _git(workspace, "ls-tree", "-r", "-z", "--full-tree", revision)
    entries: dict[str, tuple[str, str]] = {}
    for record in raw.decode("utf-8", errors="surrogateescape").split("\0"):
        if not record:
            continue
        header, path = record.split("\t", 1)
        fields = header.split()
        if len(fields) != 3:
            continue
        entries[path] = (fields[0], fields[2])
    return entries


def _committed_renames(workspace: Workspace, base: str, head: str) -> dict[str, str]:
    raw = _git(
        workspace,
        "diff",
        "--name-status",
        "--find-renames",
        "--no-ext-diff",
        "--no-textconv",
        "-z",
        base,
        head,
        "--",
    )
    records = raw.decode("utf-8", errors="surrogateescape").split("\0")
    renames: dict[str, str] = {}
    index = 0
    while index < len(records):
        status = records[index]
        index += 1
        if not status:
            continue
        if status.startswith("R"):
            if index + 1 >= len(records):
                raise CashError("execution_error", "Git rename record is malformed.", 1)
            old_path, new_path = records[index], records[index + 1]
            index += 2
            renames[new_path] = old_path
        else:
            if index >= len(records):
                raise CashError("execution_error", "Git diff record is malformed.", 1)
            index += 1
    return renames


def _blob(workspace: Workspace, oid: str) -> bytes:
    if _HEX.fullmatch(oid) is None:
        raise CashError("scope_insufficient", "Git object identity is invalid.", 2)
    return _git(workspace, "cat-file", "blob", oid)


def _worktree_endpoint(workspace: Workspace, path: str) -> tuple[dict[str, object], bytes | None]:
    try:
        with workspace._open_parent(path) as (descriptor_parent, name):
            metadata = os.stat(name, dir_fd=descriptor_parent, follow_symlinks=False)
            if stat.S_ISLNK(metadata.st_mode):
                value = os.readlink(name, dir_fd=descriptor_parent).encode("utf-8", errors="surrogateescape")
                return {
                    "type": "symlink",
                    "digest": hashlib.sha256(value).hexdigest(),
                    "mode": "120000",
                    "permissions": stat.S_IMODE(metadata.st_mode),
                    "device": metadata.st_dev,
                    "inode": metadata.st_ino,
                }, value
            if not stat.S_ISREG(metadata.st_mode):
                kind = "directory" if stat.S_ISDIR(metadata.st_mode) else "unsupported"
                return {
                    "type": kind,
                    "mode": f"{stat.S_IMODE(metadata.st_mode):04o}",
                    "device": metadata.st_dev,
                    "inode": metadata.st_ino,
                }, None
            descriptor = os.open(name, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0), dir_fd=descriptor_parent)
            try:
                opened = os.fstat(descriptor)
                if not stat.S_ISREG(opened.st_mode) or (opened.st_dev, opened.st_ino) != (metadata.st_dev, metadata.st_ino):
                    return {"type": "unsupported", "reason": "object_changed_during_open"}, None
                chunks: list[bytes] = []
                while chunk := os.read(descriptor, 131072):
                    chunks.append(chunk)
            finally:
                os.close(descriptor)
            value = b"".join(chunks)
            return {
                "type": "regular",
                "digest": hashlib.sha256(value).hexdigest(),
                "mode": "100755" if stat.S_IMODE(opened.st_mode) & stat.S_IXUSR else "100644",
                "permissions": stat.S_IMODE(opened.st_mode),
                "device": opened.st_dev,
                "inode": opened.st_ino,
            }, value
    except FileNotFoundError:
        return {"type": "absent"}, None
    except CashError as error:
        return {"type": "unsupported", "reason": error.code}, None
    except OSError as error:
        return {"type": "unsupported", "reason": str(error)}, None


def _git_endpoint(workspace: Workspace, entry: tuple[str, str] | None) -> tuple[dict[str, object], bytes | None]:
    if entry is None:
        return {"type": "absent"}, None
    mode, oid = entry
    if mode == "160000":
        return {"type": "gitlink", "mode": mode, "oid": oid}, None
    value = _blob(workspace, oid)
    if mode == "120000":
        return {
            "type": "symlink",
            "digest": hashlib.sha256(value).hexdigest(),
            "mode": mode,
            "oid": oid,
        }, value
    return {
        "type": "regular",
        "digest": hashlib.sha256(value).hexdigest(),
        "mode": mode,
        "oid": oid,
    }, value


def _patch(old: bytes | None, new: bytes | None, path: str) -> tuple[str | None, list[str]]:
    if old is None or new is None:
        return None, []
    if b"\x00" in old or b"\x00" in new:
        return None, ["binary_or_unreadable"]
    try:
        old_text = old.decode("utf-8").splitlines(keepends=True)
        new_text = new.decode("utf-8").splitlines(keepends=True)
    except UnicodeDecodeError:
        return None, ["binary_or_unreadable"]
    if old_text == new_text:
        return "", []
    return "".join(
        difflib.unified_diff(old_text, new_text, fromfile=path, tofile=path)
    ), []


def _layer(
    workspace: Workspace,
    path: str,
    old_entry: tuple[str, str] | None,
    new_entry: tuple[str, str] | None,
    *,
    old_worktree: dict[str, object] | None = None,
    new_worktree: dict[str, object] | None = None,
    old_bytes: bytes | None = None,
    new_bytes: bytes | None = None,
) -> dict[str, object]:
    if old_worktree is None:
        old_worktree, old_bytes = _git_endpoint(workspace, old_entry)
    if new_worktree is None:
        new_worktree, new_bytes = _git_endpoint(workspace, new_entry)
    if old_bytes is None and old_worktree.get("type") == "absent" and new_bytes is not None:
        old_bytes = b""
    if new_bytes is None and new_worktree.get("type") == "absent" and old_bytes is not None:
        new_bytes = b""
    patch, limitations = _patch(old_bytes, new_bytes, path)
    return {
        "old": old_worktree,
        "new": new_worktree,
        "patch": patch,
        "limitations": limitations,
    }


def _support_endpoint(
    endpoint: dict[str, object],
    content: bytes | None,
) -> dict[str, object]:
    text = None
    limitations = []
    if content is not None:
        try:
            if b"\x00" in content:
                raise UnicodeError("binary content")
            text = content.decode("utf-8")
        except UnicodeError:
            limitations.append("binary_or_unreadable")
    return {"identity": endpoint, "content": text, "limitations": limitations}


def _support_layers(
    workspace: Workspace,
    path: str,
    *,
    base_entry: tuple[str, str] | None,
    head_entry: tuple[str, str] | None,
    index_entry: tuple[str, str] | None,
    worktree: dict[str, object],
    worktree_bytes: bytes | None,
    include_base: bool = False,
) -> dict[str, object]:
    head, head_bytes = _git_endpoint(workspace, head_entry)
    index, index_bytes = _git_endpoint(workspace, index_entry)
    layers: dict[str, object] = {
        "staged": {
            "old": _support_endpoint(head, head_bytes),
            "new": _support_endpoint(index, index_bytes),
        },
        "unstaged": {
            "old": _support_endpoint(index, index_bytes),
            "new": _support_endpoint(worktree, worktree_bytes),
        },
        "untracked": {
            "old": _support_endpoint({"type": "absent"}, None),
            "new": _support_endpoint(worktree, worktree_bytes),
        },
    }
    if include_base:
        base, base_bytes = _git_endpoint(workspace, base_entry)
        layers["committed"] = {
            "old": _support_endpoint(base, base_bytes),
            "new": _support_endpoint(head, head_bytes),
        }
    return layers


def _equivalent(old: dict[str, object], new: dict[str, object]) -> bool:
    return all(old.get(key) == new.get(key) for key in ("type", "digest", "mode"))


def _unsupported_worktree_paths(
    workspace: Workspace,
    gitlink_paths: set[str] | None = None,
) -> set[str]:
    result: set[str] = set()
    gitlink_paths = gitlink_paths or set()
    for current, directories, files in os.walk(workspace.root, topdown=True, followlinks=False):
        current_path = Path(current)
        kept_directories: list[str] = []
        for name in directories:
            path = (current_path / name).relative_to(workspace.root).as_posix()
            if name != ".git" and path not in gitlink_paths and not any(
                path.startswith(f"{gitlink}/") for gitlink in gitlink_paths
            ):
                kept_directories.append(name)
        directories[:] = kept_directories
        for name in (*directories, *files):
            path = current_path / name
            relative = path.relative_to(workspace.root).as_posix()
            if relative in gitlink_paths or any(
                relative.startswith(f"{gitlink}/") for gitlink in gitlink_paths
            ):
                continue
            try:
                mode = os.lstat(path).st_mode
            except FileNotFoundError:
                continue
            if stat.S_ISFIFO(mode) or stat.S_ISSOCK(mode) or stat.S_ISCHR(mode) or stat.S_ISBLK(mode):
                result.add(path.relative_to(workspace.root).as_posix())
    return result


def _identity(value: object) -> object:
    if isinstance(value, dict):
        return {key: _identity(nested) for key, nested in value.items() if key not in {"patch"}}
    if isinstance(value, list):
        return [_identity(item) for item in value]
    return value


def _snapshot_id(value: dict[str, object], extra: dict[str, object]) -> str:
    encoded = json.dumps(
        {"output": _identity(value), "identity": _identity(extra)},
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _identity_file(workspace: Workspace, relative: str) -> dict[str, object]:
    endpoint, _ = _worktree_endpoint(workspace, relative)
    return endpoint


def _capture_identity(
    workspace: Workspace,
    *,
    change: str | None,
    base: str | None,
    support: list[str],
    resolved_base: str | None,
    head: str | None,
    allow: set[str] | None,
    index: dict[str, tuple[str, str]],
    index_flags: dict[str, str],
) -> dict[str, object]:
    touched_relative = f".cash-skills/state/touched/{change}.json" if change else None
    config = _git(workspace, "config", "--null", "--list")
    return {
        "root": str(workspace.root.resolve()),
        "selector": {
            "change": change,
            "base": base,
            "support": support,
            "allowlist": sorted(allow or set(), key=lambda item: item.encode("utf-8")),
        },
        "revisions": {"base": resolved_base, "head": head},
        "index": {
            path: {"mode": entry[0], "oid": entry[1], "flag": index_flags.get(path, "H")}
            for path, entry in sorted(index.items(), key=lambda item: item[0].encode("utf-8"))
        },
        "touched": _identity_file(workspace, touched_relative) if touched_relative else None,
        "git_config_digest": hashlib.sha256(config).hexdigest(),
    }


def _attributes(workspace: Workspace, paths: set[str]) -> dict[str, object]:
    """Observe effective attributes without invoking filters or worktree diff."""
    ordered = sorted(paths, key=lambda path: path.encode("utf-8"))
    stdin = b"".join(path.encode("utf-8") + b"\0" for path in ordered)
    effective: dict[str, dict[str, dict[str, str]]] = {}
    for layer, flags in (("worktree", ()), ("index", ("--cached",))):
        values = _git(workspace, "check-attr", *flags, "--all", "-z", "--stdin", input_bytes=stdin).decode("utf-8").split("\0")
        by_path: dict[str, dict[str, str]] = {}
        for offset in range(0, len(values) - 1, 3):
            path, attribute, value = values[offset:offset + 3]
            by_path.setdefault(path, {})[attribute] = value
        effective[layer] = by_path
    sources = {".gitattributes"}
    for path in ordered:
        sources.update((parent / ".gitattributes").as_posix() for parent in Path(path).parents)
    # Local attribute source identities also bind edits whose effective values
    # happen to stay equal. Global/info inputs are represented by effective data.
    return {"effective": effective, "sources": {path: _identity_file(workspace, path) for path in sorted(sources)}}


def _conversion_paths(workspace: Workspace, attributes: dict[str, object]) -> set[str]:
    paths: set[str] = set()
    for values in attributes["effective"].values():
        for path, attrs in values.items():
            if any(attrs.get(key, "unspecified") not in {"unspecified", "unset"} for key in ("filter", "text", "eol", "crlf", "working-tree-encoding", "ident")):
                paths.add(path)
    autocrlf = _git(workspace, "config", "--get", "core.autocrlf", check=False).strip().lower()
    if autocrlf in {b"true", b"input"}:
        paths.add("*")
    return paths


def _capture(
    workspace: Workspace,
    *,
    change: str | None,
    base: str | None,
    support: list[str],
) -> dict[str, object]:
    head = _head(workspace)
    resolved_base = _ensure_base(workspace, base, head) if base else None
    allow_error: CashError | None = None
    if change:
        try:
            allow = _allowlist(workspace, change)
        except CashError as error:
            allow = set()
            allow_error = error
    else:
        allow = None
    index_error: CashError | None = None
    try:
        index = _index_entries(workspace)
        index_flags = _index_flags(workspace)
    except CashError as error:
        if error.code != "scope_insufficient":
            raise
        index = {}
        index_flags = {}
        index_error = error
    head_tree = _tree_entries(workspace, head) if head else {}
    base_tree = _tree_entries(workspace, resolved_base) if resolved_base else {}
    status_records = _parse_index_status(workspace, head)
    candidate_names: set[str] = set()
    rename_by_path: dict[str, str | None] = {}
    limitations: list[str] = []
    if index_error is not None:
        limitations.append(f"{index_error.code}: {index_error.message}")
    if allow_error is not None:
        limitations.append(f"{allow_error.code}: {allow_error.message}")
    for record in status_records:
        path = str(record["path"])
        old_path = record.get("old_path")
        if record.get("unmerged"):
            limitations.append(f"unmerged index: {path}")
        candidate_names.add(path)
        rename_by_path[path] = old_path if isinstance(old_path, str) else None
        if isinstance(old_path, str):
            candidate_names.add(old_path)
            rename_by_path[old_path] = path
    gitlink_paths = {
        path
        for entries in (head_tree, index, base_tree)
        for path, entry in entries.items()
        if entry[0] == "160000"
    }
    unsupported_paths = _unsupported_worktree_paths(workspace, gitlink_paths)
    candidate_names.update(unsupported_paths)
    if resolved_base:
        for new_path, old_path in _committed_renames(
            workspace,
            resolved_base,
            head or resolved_base,
        ).items():
            candidate_names.add(new_path)
            candidate_names.add(old_path)
            rename_by_path.setdefault(new_path, old_path)
            rename_by_path.setdefault(old_path, new_path)
        candidate_names.update(set(base_tree) ^ set(head_tree))
        for path in set(base_tree) & set(head_tree):
            if base_tree[path] != head_tree[path]:
                candidate_names.add(path)
    for path, index_entry in index.items():
        if allow is not None and path not in allow and not (
            rename_by_path.get(path) is not None
            and rename_by_path[path] in allow
        ):
            continue
        worktree, worktree_bytes = _worktree_endpoint(workspace, path)
        index_endpoint, index_bytes = _git_endpoint(workspace, index_entry)
        if not _equivalent(worktree, index_endpoint) or worktree_bytes != index_bytes:
            candidate_names.add(path)
    if allow is not None:
        allowed_candidates = set(allow)
        for path in tuple(candidate_names):
            old_path = rename_by_path.get(path)
            if path not in allow and old_path not in allow:
                candidate_names.discard(path)
                continue
            if old_path is not None and (
                path not in allow or old_path not in allow
            ):
                limitations.append(f"attribution limitation: rename endpoint outside allowlist: {old_path}")
                allowed_candidates.add(old_path)
        candidate_names |= allowed_candidates & candidate_names
    files: list[dict[str, object]] = []
    candidate_identities: dict[str, object] = {}
    observed_paths = candidate_names | set(support)
    attributes = _attributes(workspace, observed_paths)
    conversions = _conversion_paths(workspace, attributes)
    for path in sorted(candidate_names, key=lambda item: item.encode("utf-8")):
        old_path = rename_by_path.get(path)
        layers: dict[str, object] = {}
        if resolved_base and (path in base_tree or path in head_tree):
            layers["committed"] = _layer(workspace, path, base_tree.get(path), head_tree.get(path))
        index_entry = index.get(path)
        worktree, worktree_bytes = _worktree_endpoint(workspace, path)
        head_entry = head_tree.get(path)
        candidate_identities[path] = {
            "base": base_tree.get(path) if resolved_base else None,
            "head": head_entry,
            "index": index_entry,
            "worktree": worktree,
        }
        if path in index or path in head_tree:
            if head_entry != index_entry:
                layers["staged"] = _layer(workspace, path, head_entry, index_entry)
            if index_entry is None:
                old_endpoint, old_bytes = {"type": "absent"}, None
            else:
                old_endpoint, old_bytes = _git_endpoint(workspace, index_entry)
            if worktree["type"] != "absent" or index_entry is not None:
                if not _equivalent(worktree, old_endpoint) or (worktree_bytes != old_bytes):
                    layers["unstaged"] = _layer(
                        workspace,
                        path,
                        None,
                        None,
                        old_worktree=old_endpoint,
                        new_worktree=worktree,
                        old_bytes=old_bytes,
                        new_bytes=worktree_bytes,
                    )
        if path not in index and worktree["type"] != "absent":
            layers["untracked"] = _layer(
                workspace,
                path,
                None,
                None,
                old_worktree={"type": "absent"},
                new_worktree=worktree,
                old_bytes=None,
                new_bytes=worktree_bytes,
            )
        if path in conversions or ("*" in conversions and b"\r\n" in (worktree_bytes or b"")):
            limitations.append(f"content_conversion_unverified: {path}")
            for name in ("unstaged", "untracked"):
                if name in layers:
                    layers[name]["patch"] = None
                    layers[name]["limitations"].append("content_conversion_unverified")
        if any(
            endpoint.get("type") in {"unsupported", "directory", "gitlink"}
            for layer in layers.values()
            for endpoint in (layer["old"], layer["new"])
        ):
            limitations.append(f"unsupported filesystem type: {path}")
        for layer in layers.values():
            for limitation in layer["limitations"]:
                limitations.append(f"{limitation}: {path}")
        if layers:
            files.append({"path": path, "old_path": old_path, "layers": layers})
    supporting: list[dict[str, object]] = []
    for path in sorted(set(support), key=lambda item: item.encode("utf-8")):
        endpoint, content = _worktree_endpoint(workspace, path)
        if endpoint["type"] in {"unsupported", "directory", "gitlink"}:
            limitations.append(f"unsupported supporting filesystem type: {path}")
        current_support = _support_endpoint(endpoint, content)
        supporting_item = {
            "path": path,
            "identity": endpoint,
            "content": current_support["content"],
            "layers": _support_layers(
                workspace,
                path,
                base_entry=base_tree.get(path) if resolved_base else None,
                head_entry=head_tree.get(path),
                index_entry=index.get(path),
                worktree=endpoint,
                worktree_bytes=content,
                include_base=resolved_base is not None,
            ),
        }
        for layer_name, layer in supporting_item["layers"].items():
            for side, value in layer.items():
                for limitation in value["limitations"]:
                    limitations.append(f"{limitation}: {path} ({layer_name}.{side})")
        if path in conversions or ("*" in conversions and b"\r\n" in (content or b"")):
            limitations.append(f"content_conversion_unverified: {path} (support)")
        supporting.append(supporting_item)
    source = (
        "touched-base-worktree" if change and resolved_base else
        "touched-worktree" if change else
        "base-worktree" if resolved_base else "worktree"
    )
    if limitations:
        status = "insufficient"
    elif files:
        status = "resolved"
    else:
        status = "empty"
    payload: dict[str, object] = {
        "schema_version": 1,
        "status": status,
        "scope_source": source,
        "change": change,
        "base_revision": resolved_base,
        "head_revision": head,
        "files": files,
        "supporting_files": supporting,
        "limitations": sorted(set(limitations), key=lambda item: item.encode("utf-8")),
        "snapshot_id": None,
    }
    if status in {"resolved", "empty"}:
        payload["snapshot_id"] = _snapshot_id(
            payload,
            {**_capture_identity(
                workspace,
                change=change,
                base=base,
                support=support,
                resolved_base=resolved_base,
                head=head,
                allow=allow,
                index=index,
                index_flags=index_flags,
            ), "candidates": candidate_identities, "attributes": attributes},
        )
    return payload


def scope_payload(
    workspace: Workspace,
    *,
    change: str | None = None,
    base: str | None = None,
    support: list[str] | None = None,
    check_snapshot: str | None = None,
) -> dict[str, object]:
    workspace.assert_readable()
    support_values = sorted(
        {_canonical_path(value) for value in (support or [])},
        key=lambda item: item.encode("utf-8"),
    )
    if check_snapshot is not None:
        if re.fullmatch(r"[0-9a-f]{64}", check_snapshot) is None:
            raise CashError("invalid_arguments", "--check-snapshot must be lowercase 64-character hex.")
        captured = _capture(workspace, change=change, base=base, support=support_values)
        if captured["status"] == "insufficient" or captured["snapshot_id"] != check_snapshot:
            raise CashError("scope_stale", "Scope snapshot no longer matches the workspace.", 2)
        return {"schema_version": 1, "snapshot_id": check_snapshot, "valid": True}
    first = _capture(workspace, change=change, base=base, support=support_values)
    if first["status"] in {"resolved", "empty"}:
        second = _capture(workspace, change=change, base=base, support=support_values)
        if first["snapshot_id"] != second["snapshot_id"]:
            raise CashError("scope_unstable", "Scope changed during capture.", 2)
    return first


def execute(arguments: Sequence[str]) -> int:
    change: str | None = None
    base: str | None = None
    snapshot: str | None = None
    support: list[str] = []
    json_seen = False
    index = 0
    while index < len(arguments):
        value = arguments[index]
        if value in {"--change", "--base", "--support", "--check-snapshot"}:
            if index + 1 >= len(arguments) or arguments[index + 1].startswith("--"):
                raise CashError("invalid_arguments", f"{value} requires a value.")
            candidate = arguments[index + 1]
            if value == "--change":
                if change is not None:
                    raise CashError("invalid_arguments", "Duplicate --change.")
                change = candidate
            elif value == "--base":
                if base is not None:
                    raise CashError("invalid_arguments", "Duplicate --base.")
                base = candidate
            elif value == "--check-snapshot":
                if snapshot is not None:
                    raise CashError("invalid_arguments", "Duplicate --check-snapshot.")
                snapshot = candidate
            else:
                support.append(candidate)
            index += 2
            continue
        if value == "--json":
            if json_seen:
                raise CashError("invalid_arguments", "Duplicate --json.")
            json_seen = True
            index += 1
            continue
        raise CashError("invalid_arguments", f"Unknown scope option or positional argument: {value}")
    workspace = Workspace.discover(
        os.getcwd(),
        launcher_root=os.environ.get("CASH_PROJECT_ROOT"),
    )
    workspace.assert_readable()
    print(json.dumps(scope_payload(workspace, change=change, base=base, support=support, check_snapshot=snapshot), ensure_ascii=False, separators=(",", ":")))
    return 0
