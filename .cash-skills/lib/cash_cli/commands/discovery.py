from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import re
import subprocess
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
from ..workflow import (
    artifact_for_change,
    graph_for_change,
    parse_task_entries,
    read_change_metadata,
    task_schedule,
)


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


def _artifact_path_for_graph(change: Path, artifact: object) -> Path:
    artifact_id = artifact.id
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
    graph = graph_for_change(workspace, change.name)
    done = {
        artifact.id: _artifact_done(workspace, change, artifact.id)
        for artifact in graph
    }
    states: list[dict[str, object]] = []
    for artifact in graph:
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
    metadata = read_change_metadata(workspace, change.name)
    return [
        {
            "id": entry.ordinal,
            "description": entry.description,
            "done": entry.done,
            "parallel": entry.parallel,
        }
        for entry in parse_task_entries(
            workspace.read_text(relative),
            task_order=metadata.task_order,
        )
    ]


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
    metadata = read_change_metadata(workspace, name)
    artifacts = _artifact_states(workspace, change)
    return {
        "changeName": name,
        "schemaName": metadata.schema,
        "isComplete": all(
            artifact["status"] == "done"
            for artifact in artifacts
            if artifact["id"] in {"tasks"}
        ),
        "applyRequires": ["tasks"],
        "artifacts": artifacts,
    }


def _relation(workspace: Workspace, change: Path, artifact_id: str) -> dict[str, object]:
    artifact = artifact_for_change(workspace, change.name, artifact_id)
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
    *,
    omit_context: bool = False,
) -> dict[str, object]:
    change = _change_directory(workspace, name)
    artifact = artifact_for_change(workspace, name, artifact_id)
    metadata = read_change_metadata(workspace, name)
    graph = graph_for_change(workspace, name)
    cash_config, openspec_config = workspace.load_config()
    del cash_config
    rules = openspec_config["rules"].get(artifact_id, [])
    unlock_ids = [
        candidate.id
        for candidate in graph
        if artifact_id in candidate.dependencies
    ]
    context = openspec_config["context"]
    context_ref = hashlib.sha256(
        json.dumps(
            {"version": 1, "context": context},
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
    ).hexdigest()
    payload = {
        "changeName": name,
        "artifactId": artifact_id,
        "schemaName": metadata.schema,
        "changeDir": str(change),
        "outputPath": artifact.output_path,
        "description": artifact.description,
        "instruction": artifact.description,
        "locale": LOCALE,
        "template": artifact.template,
        "contextRef": context_ref,
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
    if not omit_context:
        payload["context"] = context
    return payload


def _created(workspace: Workspace, change: Path) -> dt.date:
    """Read the strict change creation date used by dormancy decisions."""
    relative = workspace.relative(change / ".openspec.yaml")
    if not workspace.is_file(relative):
        raise CashError(
            "change_metadata_invalid",
            "Change metadata must contain exactly one canonical created date.",
            2,
            relative,
        )
    values: list[str] = []
    for line in workspace.read_text(relative).splitlines():
        match = re.fullmatch(r"created:(?: (.*))?", line)
        if match is not None:
            values.append(match.group(1) or "")
    if len(values) != 1 or not values[0] or re.fullmatch(r"\d{4}-\d{2}-\d{2}", values[0]) is None:
        raise CashError(
            "change_metadata_invalid",
            "Change metadata must contain exactly one canonical created date.",
            2,
            relative,
        )
    try:
        created = dt.date.fromisoformat(values[0])
    except ValueError as error:
        raise CashError(
            "change_metadata_invalid",
            "Change metadata created date is not calendar-valid.",
            2,
            relative,
        ) from error
    if created.isoformat() != values[0]:
        raise CashError(
            "change_metadata_invalid",
            "Change metadata created date is not canonical.",
            2,
            relative,
        )
    return created


def _preflight_created(workspace: Workspace, change: Path) -> dt.date:
    """Retain the preflight staleness fallback, separate from dormancy."""
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


def _git_output(workspace: Workspace, *arguments: str) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", str(workspace.root), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise CashError("git_error", "Git invocation failed.", 1) from error
    return result.stdout


def _git_has_head(workspace: Workspace) -> bool:
    try:
        result = subprocess.run(
            ["git", "-C", str(workspace.root), "rev-parse", "--verify", "HEAD"],
            check=False,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise CashError("git_error", "Git invocation failed.", 1) from error
    if result.returncode == 0:
        return True
    stderr = result.stderr or ""
    if isinstance(stderr, bytes):
        stderr = stderr.decode("utf-8", errors="replace")
    if any(
        marker in stderr
        for marker in (
            "Needed a single revision",
            "ambiguous argument 'HEAD'",
            "unknown revision",
            "bad revision 'HEAD'",
        )
    ):
        return False
    raise CashError("git_error", "Git invocation failed.", 1)


def _observation_date(observation_timestamp: object | None) -> dt.date:
    if observation_timestamp is None:
        return dt.datetime.now(dt.timezone.utc).date()
    if isinstance(observation_timestamp, dt.datetime):
        value = observation_timestamp
        if value.tzinfo is None:
            value = value.replace(tzinfo=dt.timezone.utc)
        return value.astimezone(dt.timezone.utc).date()
    if isinstance(observation_timestamp, dt.date):
        return observation_timestamp
    if isinstance(observation_timestamp, (int, float)):
        return dt.datetime.fromtimestamp(
            observation_timestamp,
            tz=dt.timezone.utc,
        ).date()
    raise TypeError("observation_timestamp must be a date, datetime, or Unix timestamp")


def dormancy_payload(
    workspace: Workspace,
    change: Path,
    *,
    observation_timestamp: object | None = None,
    created: dt.date | None = None,
    has_head: bool | None = None,
) -> dict[str, object]:
    """Compute the single CLI-owned dormancy contract for drift and apply."""
    created = _created(workspace, change) if created is None else created
    observation_date = _observation_date(observation_timestamp)
    age_days = max(0, (observation_date - created).days)
    if has_head is None:
        has_head = _git_has_head(workspace)
    if not has_head:
        return {
            "status": "unknown",
            "reason": "git_history_unavailable",
            "age_days": age_days,
            "idle_days": None,
        }
    commit_timestamp = _git_output(
        workspace,
        "log",
        "-1",
        "--format=%ct",
        "--",
        workspace.relative(change),
    ).strip()
    if commit_timestamp:
        try:
            commit_date = dt.datetime.fromtimestamp(
                int(commit_timestamp),
                tz=dt.timezone.utc,
            ).date()
        except (TypeError, ValueError, OSError, OverflowError) as error:
            raise CashError("git_error", "Git invocation failed.", 1) from error
        idle_days = max(0, (observation_date - commit_date).days)
        has_change_commit = True
    else:
        idle_days = age_days
        has_change_commit = False
    if age_days > 5 and idle_days >= 3:
        status = "triggered"
        reason = "age_and_idle_threshold_met"
    elif age_days <= 5:
        status = "fresh"
        reason = "age_threshold_not_met"
    elif has_change_commit:
        status = "fresh"
        reason = "recent_change_commit"
    else:
        status = "fresh"
        reason = "recent_change_commit"
    return {
        "status": status,
        "reason": reason,
        "age_days": age_days,
        "idle_days": idle_days,
    }


def _preflight(workspace: Workspace, change: Path) -> dict[str, object]:
    missing: list[dict[str, str]] = []
    drifted: set[str] = set()
    created = _preflight_created(workspace, change)
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


def apply_payload(
    workspace: Workspace,
    name: str,
    *,
    observation_timestamp: object | None = None,
    summary: bool = False,
    compact: bool = False,
) -> dict[str, object]:
    if summary and compact:
        raise CashError("invalid_arguments", "--summary and --compact are mutually exclusive.")
    change = _change_directory(workspace, name)
    metadata = read_change_metadata(workspace, name)
    graph = graph_for_change(workspace, name)
    dormancy = dormancy_payload(
        workspace,
        change,
        observation_timestamp=observation_timestamp,
    )
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
    for artifact in graph:
        if not _artifact_done(workspace, change, artifact.id):
            continue
        if artifact.id == "specs":
            context_files[artifact.id] = str(change / artifact.output_path)
        else:
            context_files[artifact.id] = str(_artifact_path(change, artifact.id))
    payload = {
        "changeName": name,
        "changeDir": str(change),
        "schemaName": metadata.schema,
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
        "dormancy": dormancy,
    }
    if summary:
        return {
            key: payload[key]
            for key in (
                "changeName",
                "changeDir",
                "schemaName",
                "state",
                "progress",
                "missingArtifacts",
            )
        }
    if compact:
        compact_payload = dict(payload)
        compact_payload.pop("tasks", None)
        tasks_relative = workspace.relative(change / "tasks.md")
        compact_payload["schedule"] = task_schedule(
            workspace.read_text(tasks_relative) if workspace.is_file(tasks_relative) else "",
            task_order=metadata.task_order,
        )
        return compact_payload
    return payload


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
    change: str | None = None
    summary = compact = omit_context = False
    json_seen = False
    index = 1
    while index < len(arguments):
        value = arguments[index]
        if value == "--change":
            if change is not None or index + 1 >= len(arguments) or arguments[index + 1].startswith("--"):
                raise CashError("invalid_arguments", "--change requires one value.")
            change = arguments[index + 1]
            index += 2
            continue
        if value == "--json":
            if json_seen:
                raise CashError("invalid_arguments", "Duplicate --json.")
            json_seen = True
            index += 1
            continue
        if value == "--summary":
            if mode != "apply" or summary:
                raise CashError("invalid_arguments", "--summary is only valid once for apply.")
            summary = True
            index += 1
            continue
        if value == "--compact":
            if mode != "apply" or compact:
                raise CashError("invalid_arguments", "--compact is only valid once for apply.")
            compact = True
            index += 1
            continue
        if value == "--omit-context":
            if mode == "apply" or omit_context:
                raise CashError("invalid_arguments", "--omit-context is only valid once for artifact instructions.")
            omit_context = True
            index += 1
            continue
        raise CashError("invalid_arguments", "Unknown or inapplicable instructions flag.")
    if change is None:
        raise CashError("invalid_arguments", "--change requires one value.")
    if summary and compact:
        raise CashError("invalid_arguments", "--summary and --compact are mutually exclusive.")
    if mode == "apply":
        _emit(
            apply_payload(
                workspace,
                name=change,
                summary=summary,
                compact=compact,
            )
        )
    else:
        _emit(
            artifact_instruction_payload(
                workspace,
                change,
                mode,
                omit_context=omit_context,
            )
        )
    return 0
