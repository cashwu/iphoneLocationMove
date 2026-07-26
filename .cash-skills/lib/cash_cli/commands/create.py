from __future__ import annotations

import datetime as dt
import os
import re
import sys
from collections.abc import Sequence

from ..errors import CashError
from ..resources import ARTIFACTS_BY_ID
from ..workspace import Workspace
from .discovery import _artifact_done


_SLUG = re.compile(r"[a-z][a-z0-9-]*\Z")


def create_change(workspace: Workspace, name: str, *, agent: str) -> None:
    active = workspace.change_path(name)
    parked = workspace.change_path(name, parked=True)
    archive_collision = any(
        kind == "directory" and candidate.endswith(f"-{name}")
        for candidate, kind in workspace.list_directory("openspec/changes/archive")
    )
    if (
        workspace.exists(workspace.relative(active))
        or workspace.exists(workspace.relative(parked))
        or archive_collision
    ):
        raise CashError("change_identity_collision", f"Change identity already exists: {name}")
    workspace.ensure_directory("openspec/changes")
    os.mkdir(active, 0o755)
    metadata = (
        "schema: spec-driven\n"
        f"created: {dt.date.today().isoformat()}\n"
        f"created_by: {agent}\n"
    ).encode("utf-8")
    try:
        transaction = workspace.transaction()
        transaction.write(
            f"openspec/changes/{name}/.openspec.yaml",
            metadata,
        )
        transaction.commit()
    except Exception:
        try:
            active.rmdir()
        except OSError:
            pass
        raise


def create_artifact(
    workspace: Workspace,
    name: str,
    artifact_id: str,
    capability: str | None,
    content: bytes,
) -> None:
    if artifact_id == "spec":
        artifact_id = "specs"
    change = workspace.change_path(name)
    if not workspace.is_dir(workspace.relative(change)):
        raise CashError("change_not_found", f"Active change not found: {name}")
    artifact = ARTIFACTS_BY_ID.get(artifact_id)
    if artifact is None:
        raise CashError("unknown_artifact", f"Unknown artifact: {artifact_id}")
    missing = [
        dependency
        for dependency in artifact.dependencies
        if not _artifact_done(workspace, change, dependency)
    ]
    if missing:
        raise CashError(
            "artifact_dependencies_missing",
            f"Missing dependencies: {', '.join(missing)}",
        )
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError as error:
        raise CashError("invalid_encoding", "Artifact stdin must be UTF-8.") from error
    if not text.strip():
        raise CashError("invalid_artifact", "Artifact stdin must not be empty.")
    if artifact_id == "specs":
        if capability is None or _SLUG.fullmatch(capability) is None:
            raise CashError("invalid_capability", "A safe capability slug is required.")
        parent = f"openspec/changes/{name}/specs/{capability}"
        workspace.ensure_directory(parent)
        relative = f"{parent}/spec.md"
    else:
        if capability is not None:
            raise CashError("invalid_arguments", "Capability is only valid for specs.")
        relative = f"openspec/changes/{name}/{artifact.output_path}"
    if workspace.exists(relative):
        raise CashError("artifact_collision", f"Artifact already exists: {relative}")
    transaction = workspace.transaction()
    transaction.write(relative, content)
    transaction.commit()


def _option(arguments: Sequence[str], name: str) -> str:
    try:
        return arguments[arguments.index(name) + 1]
    except (ValueError, IndexError) as error:
        raise CashError("invalid_arguments", f"{name} requires a value.") from error


def execute(arguments: Sequence[str]) -> int:
    workspace = Workspace.discover(
        os.getcwd(),
        launcher_root=os.environ.get("CASH_PROJECT_ROOT"),
    )
    workspace.recover()
    if len(arguments) < 2:
        raise CashError("invalid_arguments", "new requires change or artifact arguments.")
    mode = arguments[0]
    if mode == "change":
        create_change(workspace, arguments[1], agent=_option(arguments, "--agent"))
        return 0
    if mode != "artifact":
        raise CashError("unknown_command", f"Unknown new mode: {mode}")
    artifact_id = arguments[1]
    positional: list[str] = []
    index = 2
    while index < len(arguments):
        value = arguments[index]
        if value == "--change":
            index += 2
            continue
        if value == "--stdin":
            index += 1
            continue
        if value.startswith("--"):
            raise CashError("invalid_arguments", f"Unknown option: {value}")
        positional.append(value)
        index += 1
    if len(positional) > 1:
        raise CashError("invalid_arguments", "new artifact accepts at most one capability.")
    capability = positional[0] if positional else None
    if "--stdin" not in arguments:
        raise CashError("invalid_arguments", "new artifact requires --stdin.")
    create_artifact(
        workspace,
        _option(arguments, "--change"),
        artifact_id,
        capability,
        sys.stdin.buffer.read(),
    )
    return 0
