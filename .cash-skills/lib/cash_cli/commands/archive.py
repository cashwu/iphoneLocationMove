from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import stat
from collections.abc import Sequence

from ..errors import CashError
from ..spec_merge import SyncPlan, build_sync_plan, digest, manifest_bytes
from ..validation import validate_change
from ..workspace import Workspace
from .discovery import _tasks
from .tasks import load_or_import_touched


def sync_change(workspace: Workspace, name: str) -> dict[str, object]:
    workspace.recover()
    plan = build_sync_plan(workspace, name)
    if plan.already_synced:
        return {
            "change": name,
            "already_synced": True,
            "changed_capabilities": [],
        }
    workspace.ensure_directory(".cash-skills/state/sync")
    for relative in plan.writes:
        workspace.ensure_directory(os.path.dirname(relative))
    transaction = workspace.transaction()
    for relative, content in plan.writes.items():
        transaction.write(relative, content)
    transaction.write(
        f".cash-skills/state/sync/{name}.json",
        manifest_bytes(name, plan),
    )
    transaction.commit()
    return {
        "change": name,
        "already_synced": False,
        "changed_capabilities": [
            relative.split("/")[2]
            for relative in plan.writes
        ],
    }


def _completed_tasks_bytes(workspace: Workspace, name: str) -> bytes:
    relative = f"openspec/changes/{name}/tasks.md"
    content = workspace.read_text(relative)
    return content.replace("- [ ]", "- [x]").encode("utf-8")


def _legacy_cleanup(
    workspace: Workspace,
    touched: dict[str, object],
    transaction,
) -> str:
    provenance = touched["legacy_import"]
    if provenance is None:
        return "not_imported"
    relative = provenance["path"]
    if not workspace.exists(relative):
        return "missing"
    try:
        metadata = workspace.stat(relative)
        content = workspace.read_bytes(relative)
    except (OSError, CashError):
        return "preserved_drift"
    if (
        not stat.S_ISREG(metadata.st_mode)
        or metadata.st_nlink != 1
        or metadata.st_dev != provenance["st_dev"]
        or metadata.st_ino != provenance["st_ino"]
        or hashlib.sha256(content).hexdigest() != provenance["sha256"]
    ):
        return "preserved_drift"
    transaction.delete(relative)
    return "removed"


def archive_change(
    workspace: Workspace,
    name: str,
    *,
    skip_specs: bool = False,
    no_validate: bool = False,
    mark_tasks_complete: bool = False,
) -> dict[str, object]:
    workspace.recover()
    change = workspace.change_path(name)
    if not workspace.is_dir(workspace.relative(change)):
        raise CashError("change_not_found", f"Active change not found: {name}")
    destination_relative = (
        f"openspec/changes/archive/{dt.date.today().isoformat()}-{name}"
    )
    if workspace.exists(destination_relative):
        raise CashError("archive_collision", "Archive destination already exists.", path=destination_relative)
    plan = build_sync_plan(workspace, name)
    if not no_validate:
        findings = validate_change(workspace, name)
        if findings:
            raise CashError("validation_failed", findings[0]["message"], path=findings[0]["path"])
    tasks = _tasks(workspace, change)
    if any(not task["done"] for task in tasks) and not mark_tasks_complete:
        raise CashError("tasks_incomplete", "Complete tasks or use --mark-tasks-complete.")

    touched = load_or_import_touched(workspace, name)
    transaction = workspace.transaction()
    if mark_tasks_complete:
        transaction.write(
            f"openspec/changes/{name}/tasks.md",
            _completed_tasks_bytes(workspace, name),
        )
    if not skip_specs and not plan.already_synced:
        for relative, content in plan.writes.items():
            workspace.ensure_directory(os.path.dirname(relative))
            transaction.write(relative, content)
    legacy_cleanup = _legacy_cleanup(workspace, touched, transaction)
    touched_relative = f".cash-skills/state/touched/{name}.json"
    snapshot_relative = f".cash-skills/state/snapshots/{name}.json"
    sync_relative = f".cash-skills/state/sync/{name}.json"
    for relative in (touched_relative, snapshot_relative, sync_relative):
        if workspace.is_file(relative):
            transaction.delete(relative)
    archive_manifest = {
        "version": 1,
        "change": name,
        "destination": destination_relative,
        "specs_synced": not skip_specs,
        "delta_digests": plan.delta_digests,
        "master_digests": (
            plan.master_after
            if not skip_specs
            else {
                relative: (
                    digest(workspace.read_bytes(relative))
                    if workspace.is_file(relative)
                    else None
                )
                for relative in plan.master_after
            }
        ),
        "touched_digest": hashlib.sha256(
            json.dumps(touched, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        ).hexdigest(),
        "touched_files": list(touched["files"]),
        "legacy_cleanup": legacy_cleanup,
    }
    transaction.write(
        f"openspec/changes/{name}/archive-manifest.json",
        (
            json.dumps(archive_manifest, ensure_ascii=False, separators=(",", ":"))
            + "\n"
        ).encode("utf-8"),
    )
    workspace.ensure_directory(os.path.dirname(destination_relative))
    transaction.move(
        f"openspec/changes/{name}",
        destination_relative,
    )
    transaction.commit()
    return {
        "change": name,
        "destination": destination_relative,
        "specsSynced": not skip_specs,
        "changedCapabilities": [
            relative.split("/")[2]
            for relative in plan.writes
            if not skip_specs
        ],
        "legacyCleanup": legacy_cleanup,
    }


def execute(command: str, arguments: Sequence[str]) -> int:
    names = [value for value in arguments if not value.startswith("--")]
    if len(names) != 1:
        raise CashError("invalid_arguments", f"{command} requires one change name.")
    workspace = Workspace.discover(
        os.getcwd(),
        launcher_root=os.environ.get("CASH_PROJECT_ROOT"),
    )
    if command == "sync":
        result = sync_change(workspace, names[0])
    else:
        result = archive_change(
            workspace,
            names[0],
            skip_specs="--skip-specs" in arguments,
            no_validate="--no-validate" in arguments,
            mark_tasks_complete="--mark-tasks-complete" in arguments,
        )
    if "--json" in arguments:
        print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    else:
        print(f"{command} complete: {names[0]}")
    return 0
