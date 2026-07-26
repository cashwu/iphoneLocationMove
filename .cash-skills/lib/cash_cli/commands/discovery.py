from __future__ import annotations

import datetime as dt
import json
import os
import re
from collections.abc import Sequence
from pathlib import Path

from ..errors import CashError
from ..resources import (
    APPLY_INSTRUCTION,
    ARTIFACT_GRAPH,
    ARTIFACTS_BY_ID,
    DISCIPLINES,
    LOCALE,
)
from ..workspace import Workspace


_TASK = re.compile(r"^- \[([ xX])\] (\[P\] )?(.+)$")
_EXISTING_PATH = re.compile(
    r"(?:Modified|Existing)(?: file)?:\s*`([^`]+)`",
    re.IGNORECASE,
)


def _change_directory(workspace: Workspace, name: str) -> Path:
    active = workspace.change_path(name)
    parked = workspace.change_path(name, parked=True)
    active_exists = workspace.is_dir(workspace.relative(active))
    parked_exists = workspace.is_dir(workspace.relative(parked))
    if active_exists and parked_exists:
        raise CashError("change_identity_collision", f"Change exists as active and parked: {name}")
    if active_exists:
        return active
    if parked_exists:
        return parked
    raise CashError("change_not_found", f"Change not found: {name}")


def _artifact_path(change: Path, artifact_id: str) -> Path:
    artifact = ARTIFACTS_BY_ID[artifact_id]
    if artifact_id == "specs":
        return change / "specs"
    return change / artifact.output_path


def _artifact_done(workspace: Workspace, change: Path, artifact_id: str) -> bool:
    path = _artifact_path(change, artifact_id)
    relative = workspace.relative(path)
    if artifact_id == "specs":
        return workspace.is_dir(relative) and bool(workspace.spec_files(relative))
    return workspace.is_file(relative)


def _artifact_states(workspace: Workspace, change: Path) -> list[dict[str, object]]:
    done = {
        artifact.id: _artifact_done(workspace, change, artifact.id)
        for artifact in ARTIFACT_GRAPH
    }
    states: list[dict[str, object]] = []
    for artifact in ARTIFACT_GRAPH:
        missing = [
            dependency
            for dependency in artifact.dependencies
            if not done[dependency]
        ]
        if done[artifact.id]:
            status = "done"
        elif missing:
            status = "blocked"
        else:
            status = "ready"
        states.append(
            {
                "id": artifact.id,
                "outputPath": artifact.output_path,
                "status": status,
                "missingDeps": missing,
            }
        )
    return states


def _tasks(workspace: Workspace, change: Path) -> list[dict[str, object]]:
    relative = workspace.relative(change / "tasks.md")
    if not workspace.is_file(relative):
        return []
    tasks: list[dict[str, object]] = []
    for line in workspace.read_text(relative).splitlines():
        match = _TASK.fullmatch(line)
        if match is None:
            continue
        tasks.append(
            {
                "id": str(len(tasks) + 1),
                "description": match.group(3),
                "done": match.group(1).lower() == "x",
                "parallel": match.group(2) is not None,
            }
        )
    return tasks


def _summary(workspace: Workspace, change: Path) -> str:
    relative = workspace.relative(change / "proposal.md")
    if not workspace.is_file(relative):
        return ""
    lines = workspace.read_text(relative).splitlines()
    in_summary = False
    paragraphs: list[str] = []
    for line in lines:
        if line == "## Summary":
            in_summary = True
            continue
        if in_summary and line.startswith("## "):
            break
        if in_summary and line.strip():
            paragraphs.append(line.strip())
    summary = " ".join(paragraphs)
    if len(summary) > 80:
        return summary[:79].rstrip() + "…"
    return summary


def _change_entry(workspace: Workspace, change: Path) -> dict[str, object]:
    tasks = _tasks(workspace, change)
    completed = sum(1 for task in tasks if task["done"])
    if tasks and completed == len(tasks):
        status = "complete"
    elif tasks:
        status = "in-progress"
    else:
        status = "no-tasks"
    return {
        "name": change.name,
        "status": status,
        "summary": _summary(workspace, change),
        "completedTasks": completed,
        "totalTasks": len(tasks),
    }


def list_payload(workspace: Workspace, *, parked: bool) -> dict[str, object]:
    parent = workspace.parked if parked else workspace.changes
    parent_relative = workspace.relative(parent)
    key = "parked" if parked else "changes"
    if not workspace.is_dir(parent_relative):
        return {key: []}
    ignored = {"archive", ".parked"} if not parked else set()
    changes = [
        parent / name
        for name, kind in workspace.list_directory(parent_relative)
        if name not in ignored
        and kind == "directory"
        and re.fullmatch(r"[a-z][a-z0-9-]*", name)
    ]
    changes.sort(key=lambda path: path.name.encode("utf-8"))
    return {key: [_change_entry(workspace, change) for change in changes]}


def status_payload(workspace: Workspace, name: str) -> dict[str, object]:
    change = _change_directory(workspace, name)
    artifacts = _artifact_states(workspace, change)
    return {
        "changeName": name,
        "schemaName": "spec-driven",
        "isComplete": all(
            artifact["status"] == "done"
            for artifact in artifacts
            if artifact["id"] in {"tasks"}
        ),
        "applyRequires": ["tasks"],
        "artifacts": artifacts,
    }


def _relation(workspace: Workspace, change: Path, artifact_id: str) -> dict[str, object]:
    artifact = ARTIFACTS_BY_ID[artifact_id]
    return {
        "id": artifact.id,
        "done": _artifact_done(workspace, change, artifact.id),
        "path": artifact.output_path,
        "description": artifact.description,
    }


def artifact_instruction_payload(
    workspace: Workspace,
    name: str,
    artifact_id: str,
) -> dict[str, object]:
    change = _change_directory(workspace, name)
    try:
        artifact = ARTIFACTS_BY_ID[artifact_id]
    except KeyError as error:
        raise CashError("unknown_artifact", f"Unknown artifact: {artifact_id}") from error
    cash_config, openspec_config = workspace.load_config()
    del cash_config
    rules = openspec_config["rules"].get(artifact_id, [])
    unlock_ids = [
        candidate.id
        for candidate in ARTIFACT_GRAPH
        if artifact_id in candidate.dependencies
    ]
    return {
        "changeName": name,
        "artifactId": artifact_id,
        "schemaName": "spec-driven",
        "changeDir": str(change),
        "outputPath": artifact.output_path,
        "description": artifact.description,
        "instruction": artifact.description,
        "locale": LOCALE,
        "template": artifact.template,
        "context": openspec_config["context"],
        "rules": list(rules),
        "dependencies": [
            _relation(workspace, change, dependency)
            for dependency in artifact.dependencies
        ],
        "unlocks": [
            _relation(workspace, change, unlocked)
            for unlocked in unlock_ids
        ],
    }


def _created(workspace: Workspace, change: Path) -> dt.date:
    relative = workspace.relative(change / ".openspec.yaml")
    if not workspace.is_file(relative):
        return dt.date.today()
    for line in workspace.read_text(relative).splitlines():
        if line.startswith("created: "):
            try:
                return dt.date.fromisoformat(line[9:])
            except ValueError:
                break
    return dt.date.today()


def _preflight(workspace: Workspace, change: Path) -> dict[str, object]:
    missing: list[dict[str, str]] = []
    drifted: set[str] = set()
    created = _created(workspace, change)
    created_timestamp = dt.datetime.combine(created, dt.time.min).timestamp()
    for artifact_name in ("proposal.md", "design.md", "tasks.md"):
        artifact = change / artifact_name
        artifact_relative = workspace.relative(artifact)
        if not workspace.is_file(artifact_relative):
            continue
        for relative in _EXISTING_PATH.findall(workspace.read_text(artifact_relative)):
            if relative.startswith("/") or ".." in Path(relative).parts:
                continue
            if not workspace.exists(relative):
                missing.append({"path": relative, "source": artifact_name})
            elif workspace.stat(relative).st_mtime > created_timestamp:
                drifted.add(relative)
    days_old = max(0, (dt.date.today() - created).days)
    if missing:
        status = "critical"
    elif drifted or days_old > 5:
        status = "warnings"
    else:
        status = "clean"
    return {
        "status": status,
        "missingFiles": sorted(missing, key=lambda item: (item["path"], item["source"])),
        "driftedFiles": sorted(drifted, key=lambda value: value.encode("utf-8")),
        "staleness": {
            "daysOld": days_old,
            "isStale": days_old > 5,
        },
    }


def apply_payload(workspace: Workspace, name: str) -> dict[str, object]:
    change = _change_directory(workspace, name)
    tasks = _tasks(workspace, change)
    complete = sum(1 for task in tasks if task["done"])
    missing = [
        artifact_id
        for artifact_id in ("tasks",)
        if not _artifact_done(workspace, change, artifact_id)
    ]
    if missing:
        state = "blocked"
    elif tasks and complete == len(tasks):
        state = "all_done"
    else:
        state = "ready"
    context_files: dict[str, str] = {}
    for artifact in ARTIFACT_GRAPH:
        if not _artifact_done(workspace, change, artifact.id):
            continue
        if artifact.id == "specs":
            context_files[artifact.id] = str(change / artifact.output_path)
        else:
            context_files[artifact.id] = str(_artifact_path(change, artifact.id))
    return {
        "changeName": name,
        "changeDir": str(change),
        "schemaName": "spec-driven",
        "contextFiles": context_files,
        "progress": {
            "total": len(tasks),
            "complete": complete,
            "remaining": len(tasks) - complete,
        },
        "tasks": tasks,
        "missingArtifacts": missing,
        "state": state,
        "locale": LOCALE,
        "instruction": APPLY_INSTRUCTION,
        "preflight": _preflight(workspace, change),
    }


def skill_payload(skill: str) -> dict[str, object]:
    instruction = DISCIPLINES.get(skill)
    if instruction is None:
        raise CashError("unknown_command", f"Unknown discipline: {skill}")
    return {
        "skill": skill,
        "locale": LOCALE,
        "instruction": instruction,
    }


def _workspace() -> Workspace:
    workspace = Workspace.discover(
        os.getcwd(),
        launcher_root=os.environ.get("CASH_PROJECT_ROOT"),
    )
    workspace.assert_readable()
    return workspace


def _option(arguments: Sequence[str], name: str) -> str:
    try:
        index = arguments.index(name)
        value = arguments[index + 1]
    except (ValueError, IndexError) as error:
        raise CashError("invalid_arguments", f"{name} requires a value.") from error
    if value.startswith("--"):
        raise CashError("invalid_arguments", f"{name} requires a value.")
    return value


def _emit(payload: dict[str, object]) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


def execute(command: str, arguments: Sequence[str]) -> int:
    workspace = _workspace()
    if command == "list":
        _emit(list_payload(workspace, parked="--parked" in arguments))
        return 0
    if command == "status":
        _emit(status_payload(workspace, _option(arguments, "--change")))
        return 0
    if "--skill" in arguments:
        _emit(skill_payload(_option(arguments, "--skill")))
        return 0
    if not arguments:
        raise CashError("invalid_arguments", "instructions requires a mode.")
    mode = arguments[0]
    if mode == "apply":
        _emit(apply_payload(workspace, _option(arguments, "--change")))
    else:
        _emit(
            artifact_instruction_payload(
                workspace,
                _option(arguments, "--change"),
                mode,
            )
        )
    return 0
