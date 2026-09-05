from __future__ import annotations

import copy
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


_TASK = re.compile(r"^- \[([ xX])\] (\[P\] )?(.+)$")
_TASK_LABEL = re.compile(r"([0-9]+(?:\.[0-9]+)*)\s+")
_RESERVED_TASK_ID = "review-loop"
_IGNORED_PREFIXES = (
    ".cash-skills/state/",
    ".cash-skills/receipt.tsv",
    "openspec/changes/",
)


def _run_git(workspace: Workspace, *arguments: str) -> bytes:
    try:
        return subprocess.run(
            ["git", "-C", str(workspace.root), *arguments],
            check=True,
            capture_output=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as error:
        raise CashError("git_error", "Git invocation failed.", 1) from error


def _worktree_fingerprint(workspace: Workspace, relative: str) -> tuple[str, str]:
    path = workspace.root / relative
    try:
        metadata = os.lstat(path)
    except FileNotFoundError:
        return "absent", "absent"
    mode = f"{stat.S_IMODE(metadata.st_mode):04o}"
    if stat.S_ISREG(metadata.st_mode):
        digest = hashlib.sha256(workspace.read_bytes(relative)).hexdigest()
        return digest, mode
    if stat.S_ISLNK(metadata.st_mode):
        digest = hashlib.sha256(os.readlink(path).encode("utf-8")).hexdigest()
        return f"symlink:{digest}", mode
    return f"type:{stat.S_IFMT(metadata.st_mode):o}", mode


def _index_fingerprint(workspace: Workspace, relative: str) -> str:
    value = _run_git(workspace, "ls-files", "--stage", "-z", "--", relative)
    if not value:
        return "absent"
    return hashlib.sha256(value).hexdigest()


def git_fingerprints(workspace: Workspace) -> dict[str, dict[str, str]]:
    output = _run_git(
        workspace,
        "status",
        "--porcelain=v2",
        "-z",
        "--untracked-files=all",
    )
    records = output.decode("utf-8", errors="strict").split("\0")
    result: dict[str, dict[str, str]] = {}
    index = 0
    while index < len(records):
        record = records[index]
        index += 1
        if not record:
            continue
        kind = record[0]
        paths: list[tuple[str, str]] = []
        if kind == "1":
            fields = record.split(" ", 8)
            paths.append((fields[8], fields[1]))
        elif kind == "2":
            fields = record.split(" ", 9)
            destination = fields[9]
            if index >= len(records):
                raise CashError("git_status_invalid", "Rename record is incomplete.", 1)
            source = records[index]
            index += 1
            paths.extend(((destination, fields[1]), (source, "rename-source")))
        elif kind == "u":
            fields = record.split(" ", 10)
            paths.append((fields[10], fields[1]))
        elif kind in {"?", "!"}:
            paths.append((record[2:], kind))
        else:
            raise CashError("git_status_invalid", f"Unsupported porcelain record: {kind}", 1)
        for relative, state in paths:
            if relative.startswith(_IGNORED_PREFIXES):
                continue
            worktree, mode = _worktree_fingerprint(workspace, relative)
            result[relative] = {
                "path": relative,
                "worktree": worktree,
                "index": _index_fingerprint(workspace, relative),
                "mode": mode,
                "state": state,
            }
    return dict(sorted(result.items(), key=lambda item: item[0].encode("utf-8")))


def _state_relative(kind: str, name: str) -> str:
    return f".cash-skills/state/{kind}/{name}.json"


def _json_bytes(value: dict[str, object]) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n"
    ).encode("utf-8")


def _read_json(workspace: Workspace, relative: str) -> dict[str, object]:
    try:
        value = json.loads(workspace.read_text(relative))
    except (json.JSONDecodeError, TypeError) as error:
        raise CashError("state_invalid", f"Malformed state: {relative}") from error
    if not isinstance(value, dict):
        raise CashError("state_invalid", f"State must be an object: {relative}")
    return value


def _validate_snapshot(value: dict[str, object], name: str) -> None:
    if set(value) != {"version", "change", "paths"}:
        raise CashError("snapshot_invalid", "Snapshot shape is invalid.")
    if value["version"] != 1 or value["change"] != name or not isinstance(value["paths"], list):
        raise CashError("snapshot_invalid", "Snapshot identity is invalid.")
    required = {"path", "worktree", "index", "mode", "state"}
    paths = value["paths"]
    if any(not isinstance(item, dict) or set(item) != required for item in paths):
        raise CashError("snapshot_invalid", "Snapshot path entry is invalid.")
    names = [item["path"] for item in paths]
    if names != sorted(set(names), key=lambda path: path.encode("utf-8")):
        raise CashError("snapshot_invalid", "Snapshot paths are not canonical.")


def start_in_progress(workspace: Workspace, name: str) -> dict[str, object]:
    if not workspace.is_dir(workspace.relative(workspace.change_path(name))):
        raise CashError("change_not_found", f"Active change not found: {name}")
    relative = _state_relative("snapshots", name)
    if workspace.exists(relative):
        snapshot = _read_json(workspace, relative)
        _validate_snapshot(snapshot, name)
        return snapshot
    workspace.ensure_directory(".cash-skills/state/snapshots")
    snapshot = {
        "version": 1,
        "change": name,
        "paths": list(git_fingerprints(workspace).values()),
    }
    transaction = workspace.transaction()
    transaction.write(relative, _json_bytes(snapshot))
    transaction.commit()
    return snapshot


def _safe_source_path(value: object) -> str:
    candidate = Path(value) if isinstance(value, str) else None
    if (
        not isinstance(value, str)
        or not value
        or candidate is None
        or candidate.is_absolute()
        or ".." in candidate.parts
        or value.startswith(".git/")
        or value.startswith(".cash-skills/state/")
    ):
        raise CashError("touched_invalid", "Touched path is unsafe.")
    return value


def _validate_touched(value: dict[str, object], name: str) -> dict[str, object]:
    if set(value) != {"version", "change", "legacy_import", "touched", "files"}:
        raise CashError("touched_invalid", "Touched state shape is invalid.")
    if value["version"] != 1 or value["change"] != name:
        raise CashError("touched_invalid", "Touched state identity is invalid.")
    if not isinstance(value["touched"], list) or not isinstance(value["files"], list):
        raise CashError("touched_invalid", "Touched arrays are invalid.")
    task_ids: set[str] = set()
    union: set[str] = set()
    for item in value["touched"]:
        if not isinstance(item, dict) or set(item) != {"task_id", "task_desc", "files"}:
            raise CashError("touched_invalid", "Touched task entry is invalid.")
        task_id = item["task_id"]
        if not isinstance(task_id, str) or not task_id or task_id in task_ids:
            raise CashError("touched_invalid", "Touched task id is invalid.")
        if not isinstance(item["task_desc"], str) or not isinstance(item["files"], list):
            raise CashError("touched_invalid", "Touched task value is invalid.")
        files = [_safe_source_path(path) for path in item["files"]]
        if files != sorted(set(files), key=lambda path: path.encode("utf-8")):
            raise CashError("touched_invalid", "Touched task files are not canonical.")
        task_ids.add(task_id)
        union.update(files)
    files = [_safe_source_path(path) for path in value["files"]]
    if files != sorted(union, key=lambda path: path.encode("utf-8")):
        raise CashError("touched_invalid", "Touched aggregate is invalid.")
    provenance = value["legacy_import"]
    if provenance is not None:
        if not isinstance(provenance, dict) or set(provenance) != {
            "path",
            "sha256",
            "st_dev",
            "st_ino",
        }:
            raise CashError("touched_invalid", "Legacy provenance is invalid.")
        _safe_source_path(provenance["path"])
        if (
            not isinstance(provenance["sha256"], str)
            or len(provenance["sha256"]) != 64
            or not isinstance(provenance["st_dev"], int)
            or not isinstance(provenance["st_ino"], int)
            or provenance["st_dev"] < 0
            or provenance["st_ino"] <= 0
        ):
            raise CashError("touched_invalid", "Legacy provenance values are invalid.")
    return value


def _import_legacy(workspace: Workspace, name: str, relative: str) -> dict[str, object]:
    before = workspace.stat(relative)
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        raise CashError("legacy_touched_invalid", "Legacy touched state is unsafe.")
    content = workspace.read_bytes(relative)
    after = workspace.stat(relative)
    if (before.st_dev, before.st_ino) != (after.st_dev, after.st_ino):
        raise CashError("legacy_touched_invalid", "Legacy touched identity changed.")
    try:
        legacy = json.loads(content)
    except json.JSONDecodeError as error:
        raise CashError("legacy_touched_invalid", "Legacy touched JSON is malformed.") from error
    if not isinstance(legacy, dict) or set(legacy) != {"change", "touched"}:
        raise CashError("legacy_touched_invalid", "Legacy touched shape is invalid.")
    if legacy["change"] != name or not isinstance(legacy["touched"], list):
        raise CashError("legacy_touched_invalid", "Legacy touched identity is invalid.")
    touched: list[dict[str, object]] = []
    task_ids: set[str] = set()
    union: set[str] = set()
    for item in legacy["touched"]:
        if not isinstance(item, dict) or set(item) != {"task_id", "task_desc", "files"}:
            raise CashError("legacy_touched_invalid", "Legacy task shape is invalid.")
        task_id = item["task_id"]
        if not isinstance(task_id, str) or not task_id or task_id in task_ids:
            raise CashError("legacy_touched_invalid", "Legacy task id is invalid.")
        if not isinstance(item["task_desc"], str) or not isinstance(item["files"], list):
            raise CashError("legacy_touched_invalid", "Legacy task values are invalid.")
        files = sorted(
            {_safe_source_path(path) for path in item["files"]},
            key=lambda path: path.encode("utf-8"),
        )
        if len(files) != len(item["files"]):
            raise CashError("legacy_touched_invalid", "Legacy task files contain duplicates.")
        touched.append({"task_id": task_id, "task_desc": item["task_desc"], "files": files})
        task_ids.add(task_id)
        union.update(files)
    return {
        "version": 1,
        "change": name,
        "legacy_import": {
            "path": relative,
            "sha256": hashlib.sha256(content).hexdigest(),
            "st_dev": before.st_dev,
            "st_ino": before.st_ino,
        },
        "touched": touched,
        "files": sorted(union, key=lambda path: path.encode("utf-8")),
    }


def _realign_touched_attribution(
    workspace: Workspace,
    name: str,
    touched: dict[str, object],
) -> tuple[dict[str, object], bool]:
    try:
        tasks_relative = next(
            (
                relative
                for relative in (
                    f"openspec/changes/{name}/tasks.md",
                    f"openspec/changes/.parked/{name}/tasks.md",
                )
                if workspace.exists(relative)
            ),
            None,
        )
        if tasks_relative is None:
            return touched, False
        entries = _task_entries(workspace.read_text(tasks_relative))
    except (CashError, OSError):
        return touched, False

    task_ids_by_description = {description: task_id for _, task_id, description, _ in entries}
    aligned = copy.deepcopy(touched)
    legacy = touched["legacy_import"] is not None
    for item in aligned["touched"]:
        if item["task_id"] == _RESERVED_TASK_ID:
            continue
        task_id = task_ids_by_description.get(item["task_desc"])
        if task_id is None:
            if legacy:
                continue
            raise CashError(
                "touched_invalid",
                f"Touched task description is absent from tasks.md: {item['task_desc']}",
            )
        item["task_id"] = task_id

    task_ids = [item["task_id"] for item in aligned["touched"]]
    if len(task_ids) != len(set(task_ids)):
        if legacy:
            return touched, False
        raise CashError("touched_invalid", "Touched task ids collide after realignment.")
    aligned["touched"].sort(key=lambda item: item["task_id"].encode("utf-8"))
    return aligned, aligned != touched


def load_or_import_touched(workspace: Workspace, name: str) -> dict[str, object]:
    value, _ = _load_or_import_touched(workspace, name)
    return value


def _load_or_import_touched(
    workspace: Workspace,
    name: str,
) -> tuple[dict[str, object], bool]:
    relative = _state_relative("touched", name)
    if workspace.exists(relative):
        touched = _validate_touched(_read_json(workspace, relative), name)
        return _realign_touched_attribution(workspace, name, touched)
    legacy_relative = f".spectra/touched/{name}.json"
    if workspace.exists(legacy_relative):
        value = _import_legacy(workspace, name, legacy_relative)
    else:
        value = {
            "version": 1,
            "change": name,
            "legacy_import": None,
            "touched": [],
            "files": [],
        }
    return value, False


def ensure_touched(workspace: Workspace, name: str) -> dict[str, object]:
    relative = _state_relative("touched", name)
    value, changed = _load_or_import_touched(workspace, name)
    exists = workspace.exists(relative)
    if exists and not changed:
        return value
    workspace.ensure_directory(".cash-skills/state/touched")
    transaction = workspace.transaction()
    transaction.write(relative, _json_bytes(value))
    transaction.commit()
    return value


def _task_entries(content: str) -> list[tuple[int, str, str, bool]]:
    entries: list[tuple[int, str, str, bool]] = []
    labels: set[str] = set()
    for line_index, line in enumerate(content.splitlines()):
        match = _TASK.fullmatch(line)
        if match is None:
            continue
        label_match = _TASK_LABEL.match(match.group(3))
        if label_match is None or label_match.group(1) in labels:
            raise CashError("task_id_invalid", "Task labels must be present and unique.")
        labels.add(label_match.group(1))
        entries.append(
            (
                line_index,
                str(len(entries) + 1),
                match.group(3),
                match.group(1).lower() == "x",
            )
        )
    return entries


def mark_task_done(
    workspace: Workspace,
    name: str,
    task_id: str,
    paths: Sequence[str] | None = None,
) -> dict[str, object]:
    change = workspace.change_path(name)
    tasks_relative = f"openspec/changes/{name}/tasks.md"
    content = workspace.read_text(tasks_relative)
    entries = _task_entries(content)
    matches = [entry for entry in entries if entry[1] == task_id]
    if len(matches) != 1:
        raise CashError("task_not_found", f"Unknown or duplicate task id: {task_id}")
    line_index, _, description, already_done = matches[0]
    if paths is None and _TASK.fullmatch(content.splitlines()[line_index]).group(2):
        raise CashError("invalid_arguments", "Parallel tasks require --path or --no-files.")
    snapshot_relative = _state_relative("snapshots", name)
    if not workspace.exists(snapshot_relative):
        raise CashError(
            "snapshot_missing",
            "Run in-progress add before completing tasks.",
        )
    snapshot = _read_json(workspace, snapshot_relative)
    _validate_snapshot(snapshot, name)
    baseline = {item["path"]: item for item in snapshot["paths"]}
    current = git_fingerprints(workspace)
    changed = sorted(
        [
            path
            for path, fingerprint in current.items()
            if baseline.get(path) != fingerprint
        ],
        key=lambda path: path.encode("utf-8"),
    )
    if paths is not None:
        prior = load_or_import_touched(workspace, name)
        prior_files = {
            path
            for entry in prior["touched"]
            if entry["task_id"] == task_id
            for path in entry["files"]
        }
        selected = set()
        for path in paths:
            canonical = _safe_source_path(path)
            if (
                canonical != Path(canonical).as_posix()
                or canonical.startswith(_IGNORED_PREFIXES)
                or canonical not in current and canonical not in baseline and canonical not in prior_files
            ):
                raise CashError("touched_invalid", "Explicit task path must be canonical and have dirty, snapshot, or same-task attribution evidence.")
            selected.add(canonical)
        changed = sorted(selected, key=lambda path: path.encode("utf-8"))
    touched = ensure_touched(workspace, name)
    items = list(touched["touched"])
    existing = next((item for item in items if item["task_id"] == task_id), None)
    if existing is None:
        items.append({"task_id": task_id, "task_desc": description, "files": changed})
    else:
        existing["files"] = sorted(
            set(existing["files"]) | set(changed),
            key=lambda path: path.encode("utf-8"),
        )
    items.sort(key=lambda item: item["task_id"].encode("utf-8"))
    union = sorted(
        {path for item in items for path in item["files"]},
        key=lambda path: path.encode("utf-8"),
    )
    updated_touched = {
        "version": 1,
        "change": name,
        "legacy_import": touched["legacy_import"],
        "touched": items,
        "files": union,
    }
    lines = content.splitlines(keepends=True)
    if not already_done:
        lines[line_index] = lines[line_index].replace("- [ ]", "- [x]", 1)
    # Explicit completion consumes only this task's paths. Sibling task edits
    # remain available to later completion calls, including automatic ones.
    next_baseline = current
    if paths is not None:
        next_baseline = baseline.copy()
        for path in changed:
            if path in current:
                next_baseline[path] = current[path]
            else:
                next_baseline.pop(path, None)
    updated_snapshot = {
        "version": 1,
        "change": name,
        "paths": [
            next_baseline[path]
            for path in sorted(next_baseline, key=lambda path: path.encode("utf-8"))
        ],
    }
    transaction = workspace.transaction()
    transaction.write(tasks_relative, "".join(lines).encode("utf-8"))
    transaction.write(_state_relative("touched", name), _json_bytes(updated_touched))
    transaction.write(snapshot_relative, _json_bytes(updated_snapshot))
    transaction.commit()
    return updated_touched


def execute(command: str, arguments: Sequence[str]) -> int:
    workspace = Workspace.discover(
        os.getcwd(),
        launcher_root=os.environ.get("CASH_PROJECT_ROOT"),
    )
    workspace.recover()
    if command == "in-progress":
        if len(arguments) != 2 or arguments[0] != "add":
            raise CashError("invalid_arguments", "Expected in-progress add <name>.")
        start_in_progress(workspace, arguments[1])
        return 0
    if command == "touched":
        if len(arguments) == 2 and arguments[0] == "ensure":
            ensure_touched(workspace, arguments[1])
            return 0
        if (
            len(arguments) < 4
            or arguments[0] != "record"
            or len(arguments[2:]) % 2 != 0
            or any(arguments[index] != "--path" for index in range(2, len(arguments), 2))
        ):
            raise CashError(
                "invalid_arguments",
                "Expected touched record <name> --path <path> [--path <path> ...].",
            )
        name = arguments[1]
        if not workspace.is_dir(workspace.relative(workspace.change_path(name))):
            raise CashError("change_not_found", f"Active change not found: {name}")
        relative = _state_relative("touched", name)
        if not workspace.exists(relative):
            raise CashError(
                "touched_invalid",
                "Run touched ensure before recording paths.",
            )
        touched = _validate_touched(_read_json(workspace, relative), name)
        touched, attribution_changed = _realign_touched_attribution(
            workspace,
            name,
            touched,
        )
        paths: list[str] = []
        for index in range(3, len(arguments), 2):
            canonical_path = _safe_source_path(Path(arguments[index]).as_posix())
            if canonical_path.startswith(("openspec/changes/", ".cash-skills/receipt.tsv")):
                raise CashError("touched_invalid", "Touched path is ignored.")
            if workspace.path_kind(canonical_path) != "file":
                raise CashError("touched_invalid", "Touched path must be a file.")
            paths.append(canonical_path)

        items = list(touched["touched"])
        review_index = next(
            (
                index
                for index, item in enumerate(items)
                if item["task_id"] == _RESERVED_TASK_ID
            ),
            None,
        )
        review_files = set(paths)
        if review_index is not None:
            review_files.update(items[review_index]["files"])
        review_entry = {
            "task_id": _RESERVED_TASK_ID,
            "task_desc": "Review loop outputs",
            "files": sorted(review_files, key=lambda path: path.encode("utf-8")),
        }
        if review_index is None:
            items.append(review_entry)
        else:
            items[review_index] = review_entry
        updated = {
            "version": 1,
            "change": name,
            "legacy_import": touched["legacy_import"],
            "touched": items,
            "files": sorted(
                {path for item in items for path in item["files"]},
                key=lambda path: path.encode("utf-8"),
            ),
        }
        if attribution_changed or updated != touched:
            transaction = workspace.transaction()
            transaction.write(relative, _json_bytes(updated))
            transaction.commit()
        return 0
    if not arguments or arguments[0] != "done":
        raise CashError("invalid_arguments", "Expected task done --change <name> <task-id>.")
    name = task_id = None
    paths: list[str] = []
    no_files = output_json = False
    index = 1
    while index < len(arguments):
        argument = arguments[index]
        if argument in {"--change", "--path"}:
            if index + 1 >= len(arguments):
                raise CashError("invalid_arguments", f"{argument} requires a value.")
            value = arguments[index + 1]
            if argument == "--change":
                if name is not None:
                    raise CashError("invalid_arguments", "Duplicate --change.")
                name = value
            else:
                paths.append(value)
            index += 2
            continue
        if argument == "--no-files" and not no_files:
            no_files = True
        elif argument == "--json" and not output_json:
            output_json = True
        elif not argument.startswith("-") and task_id is None:
            task_id = argument
        else:
            raise CashError("invalid_arguments", f"Unexpected task argument: {argument}")
        index += 1
    if not name or task_id is None or (no_files and paths):
        raise CashError("invalid_arguments", "Expected task done --change <name> <task-id> [--path <path> ... | --no-files] [--json].")
    value = mark_task_done(workspace, name, task_id, paths if paths or no_files else None)
    if output_json:
        print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))
    return 0
