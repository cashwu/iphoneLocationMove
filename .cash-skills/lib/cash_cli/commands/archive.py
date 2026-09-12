from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import re
import stat
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from ..errors import CashError
from ..spec_merge import SyncPlan, build_sync_plan, digest, manifest_bytes
from ..validation import validate_change
from ..workspace import Workspace
from ..workflow import read_change_metadata
from .discovery import _artifact_states, _tasks
from .tasks import load_or_import_touched


def sync_change(workspace: Workspace, name: str) -> dict[str, object]:
    workspace.recover()
    plan = build_sync_plan(workspace, name)
    if not plan.writes and plan.already_synced and not plan.delta_digests:
        return {
            "change": name,
            "already_synced": False,
            "changed_capabilities": [],
            "status": "no_delta_specs",
        }
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
    status = _legacy_cleanup_status(workspace, touched)
    if status == "removed":
        transaction.delete(touched["legacy_import"]["path"])
    return status


def _legacy_cleanup_status(
    workspace: Workspace,
    touched: dict[str, object],
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
    return "removed"


@dataclass(slots=True)
class ArchivePlan:
    name: str
    archived_id: str
    archived_path: str
    flags: dict[str, bool]
    sync_plan: SyncPlan
    touched: dict[str, object]
    legacy_cleanup: str
    incomplete_artifacts: list[dict[str, object]]
    incomplete_tasks: list[dict[str, object]]
    validation_findings: list[dict[str, str]]
    spec_updates: list[dict[str, object]]
    warnings: list[dict[str, object]]
    cleanup_plan: dict[str, object]
    fingerprints: dict[str, object]
    preview_id: str


def _path_fingerprint(
    workspace: Workspace,
    relative: str,
    *,
    recurse_directories: bool = True,
) -> dict[str, object]:
    """Return a deterministic identity for a managed path without writing it."""
    kind = workspace.path_kind(relative)
    if kind == "missing":
        return {"kind": "missing"}
    metadata = workspace.stat(relative)
    identity: dict[str, object] = {
        "kind": kind,
        "mode": stat.S_IMODE(metadata.st_mode),
        "st_dev": metadata.st_dev,
        "st_ino": metadata.st_ino,
        "st_nlink": metadata.st_nlink,
    }
    if kind == "file":
        content = workspace.read_bytes(relative)
        identity["sha256"] = digest(content)
        identity["size"] = len(content)
        return identity
    if kind == "directory" and not recurse_directories:
        identity.pop("st_nlink")
        return identity
    if kind != "directory":
        return identity
    entries: dict[str, object] = {}
    for name, _ in workspace.list_directory(relative):
        child = f"{relative}/{name}"
        entries[name] = _path_fingerprint(workspace, child)
    identity["entries"] = entries
    return identity


def _plan_fingerprints(
    workspace: Workspace,
    name: str,
    sync_plan: SyncPlan,
    touched: dict[str, object],
    archived_path: str,
) -> dict[str, object]:
    archive_parent = Path(archived_path).parent.as_posix()
    paths = {
        f"openspec/changes/{name}",
        f".cash-skills/state/touched/{name}.json",
        f".cash-skills/state/snapshots/{name}.json",
        f".cash-skills/state/sync/{name}.json",
        f".spectra/touched/{name}.json",
        archived_path,
        *sync_plan.master_before,
        *sync_plan.master_after,
    }
    provenance = touched.get("legacy_import")
    if isinstance(provenance, dict) and isinstance(provenance.get("path"), str):
        paths.add(provenance["path"])
    fingerprints = {
        relative: _path_fingerprint(workspace, relative)
        for relative in sorted(paths, key=lambda value: value.encode("utf-8"))
    }
    fingerprints[archive_parent] = _path_fingerprint(
        workspace,
        archive_parent,
        recurse_directories=False,
    )
    return dict(
        sorted(fingerprints.items(), key=lambda item: item[0].encode("utf-8"))
    )


def _state_disposition(workspace: Workspace, relative: str) -> str:
    return "delete" if workspace.exists(relative) else "absent"


def _cleanup_warnings(plan: ArchivePlan) -> list[dict[str, object]]:
    if plan.legacy_cleanup == "preserved_drift":
        provenance = plan.touched.get("legacy_import")
        path = provenance.get("path") if isinstance(provenance, dict) else None
        return [
            {
                "code": "legacy_cleanup_preserved",
                "message": "Legacy touched state changed after import and was preserved.",
                "path": path,
            }
        ]
    return []


def _archive_warnings(
    incomplete_artifacts: list[dict[str, object]],
    incomplete_tasks: list[dict[str, object]],
    validation_findings: list[dict[str, str]],
    cleanup_warnings: list[dict[str, object]],
    *,
    no_delta_specs: bool = False,
) -> list[dict[str, object]]:
    warnings: list[dict[str, object]] = list(cleanup_warnings)
    if incomplete_artifacts:
        warnings.append(
            {
                "code": "incomplete_artifacts",
                "message": "One or more archive artifacts are incomplete.",
            }
        )
    if incomplete_tasks:
        warnings.append(
            {
                "code": "incomplete_tasks",
                "message": "One or more archive tasks are incomplete.",
            }
        )
    if validation_findings:
        warnings.append(
            {
                "code": "validation_findings",
                "message": "Archive validation reported findings.",
            }
        )
    if no_delta_specs:
        warnings.append(
            {
                "code": "no_delta_specs",
                "message": "This no-spec change has no delta specs to apply.",
            }
        )
    return warnings


def _canonical_json(value: object) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def build_archive_plan(
    workspace: Workspace,
    name: str,
    *,
    skip_specs: bool = False,
    no_validate: bool = False,
    mark_tasks_complete: bool = False,
    archive_date: dt.date | None = None,
    reject_collision: bool = True,
) -> ArchivePlan:
    """Build all archive inputs once; this function never mutates the workspace."""
    change = workspace.change_path(name)
    change_relative = workspace.relative(change)
    if not workspace.is_dir(change_relative):
        raise CashError("change_not_found", f"Active change not found: {name}")

    selected_date = archive_date or dt.date.today()
    archived_id = f"{selected_date.isoformat()}-{name}"
    archived_path = f"openspec/changes/archive/{archived_id}"
    destination_exists = workspace.exists(archived_path)
    if destination_exists and reject_collision:
        raise CashError(
            "archive_collision",
            "Archive destination already exists.",
            path=archived_path,
        )

    metadata = read_change_metadata(workspace, name)
    validation_findings = validate_change(workspace, name)
    if metadata.schema == "no-spec":
        for conflict in validation_findings:
            if conflict["code"] == "schema_artifact_conflict" and conflict["path"] == f"{change_relative}/specs":
                raise CashError(conflict["code"], conflict["message"], 2, conflict["path"])
        # A preview can display proposal conflicts, but checked execution rejects
        # them regardless of flags. A no-spec plan never contains spec writes.
        sync_plan = SyncPlan(writes={}, delta_digests={}, master_before={}, master_after={}, already_synced=True)
    else:
        sync_plan = build_sync_plan(workspace, name)
    artifact_states = _artifact_states(workspace, change)
    incomplete_artifacts = [
        state for state in artifact_states if state["status"] != "done"
    ]
    tasks = _tasks(workspace, change)
    incomplete_tasks = [task for task in tasks if not task["done"]]
    touched = load_or_import_touched(workspace, name)
    legacy_cleanup = _legacy_cleanup_status(workspace, touched)

    flags = {
        "skip_specs": skip_specs,
        "no_validate": no_validate,
        "mark_tasks_complete": mark_tasks_complete,
    }
    spec_updates: list[dict[str, object]] = []
    for relative in sorted(sync_plan.master_after, key=lambda value: value.encode("utf-8")):
        capability = relative.split("/")[2]
        delta_relative = f"openspec/changes/{name}/specs/{capability}/spec.md"
        master_after = sync_plan.master_after[relative]
        if skip_specs:
            master_after = (
                digest(workspace.read_bytes(relative))
                if workspace.is_file(relative)
                else None
            )
        spec_updates.append(
            {
                "capability": capability,
                "action": (
                    "skipped"
                    if skip_specs
                    else "already_synced"
                    if sync_plan.already_synced
                    else "apply"
                ),
                "delta_digest": sync_plan.delta_digests[delta_relative],
                "master_before": sync_plan.master_before[relative],
                "master_after": master_after,
            }
        )

    cleanup_plan = {
        "cash_touched_state": _state_disposition(
            workspace,
            f".cash-skills/state/touched/{name}.json",
        ),
        "cash_snapshot_state": _state_disposition(
            workspace,
            f".cash-skills/state/snapshots/{name}.json",
        ),
        "cash_sync_state": _state_disposition(
            workspace,
            f".cash-skills/state/sync/{name}.json",
        ),
        "legacy_touched_state": legacy_cleanup,
        "touched_files": list(touched["files"]),
    }
    fingerprints = _plan_fingerprints(
        workspace,
        name,
        sync_plan,
        touched,
        archived_path,
    )
    identity = {
        "version": 1,
        "change": name,
        "archived_id": archived_id,
        "archived_path": archived_path,
        "flags": flags,
        "sync_plan": {
            "delta_digests": sync_plan.delta_digests,
            "master_before": sync_plan.master_before,
            "master_after": sync_plan.master_after,
            "already_synced": sync_plan.already_synced,
        },
        "incomplete_artifacts": incomplete_artifacts,
        "incomplete_tasks": incomplete_tasks,
        "validation_findings": validation_findings,
        "spec_updates": spec_updates,
        "cleanup_plan": cleanup_plan,
        "fingerprints": fingerprints,
        "destination_exists": destination_exists,
    }
    preview_id = hashlib.sha256(_canonical_json(identity)).hexdigest()
    cleanup_warnings = _cleanup_warnings(
        ArchivePlan(
            name=name,
            archived_id=archived_id,
            archived_path=archived_path,
            flags=flags,
            sync_plan=sync_plan,
            touched=touched,
            legacy_cleanup=legacy_cleanup,
            incomplete_artifacts=incomplete_artifacts,
            incomplete_tasks=incomplete_tasks,
            validation_findings=validation_findings,
            spec_updates=spec_updates,
            warnings=[],
            cleanup_plan=cleanup_plan,
            fingerprints=fingerprints,
            preview_id=preview_id,
        )
    )
    return ArchivePlan(
        name=name,
        archived_id=archived_id,
        archived_path=archived_path,
        flags=flags,
        sync_plan=sync_plan,
        touched=touched,
        legacy_cleanup=legacy_cleanup,
        incomplete_artifacts=incomplete_artifacts,
        incomplete_tasks=incomplete_tasks,
        validation_findings=validation_findings,
        spec_updates=spec_updates,
        warnings=_archive_warnings(
            incomplete_artifacts,
            incomplete_tasks,
            validation_findings,
            cleanup_warnings,
            no_delta_specs=metadata.schema == "no-spec",
        ),
        cleanup_plan=cleanup_plan,
        fingerprints=fingerprints,
        preview_id=preview_id,
    )


def archive_preview(
    workspace: Workspace,
    name: str,
    *,
    skip_specs: bool = False,
    no_validate: bool = False,
    mark_tasks_complete: bool = False,
) -> dict[str, object]:
    try:
        workspace.assert_readable()
    except CashError as error:
        raise CashError(error.code, error.message, 2, error.path) from error
    plan = build_archive_plan(
        workspace,
        name,
        skip_specs=skip_specs,
        no_validate=no_validate,
        mark_tasks_complete=mark_tasks_complete,
    )
    return {
        "schema_version": 1,
        "change": plan.name,
        "preview_id": plan.preview_id,
        "archived_id": plan.archived_id,
        "archived_path": plan.archived_path,
        "flags": plan.flags,
        "incomplete_artifacts": plan.incomplete_artifacts,
        "incomplete_tasks": plan.incomplete_tasks,
        "validation_findings": plan.validation_findings,
        "spec_updates": plan.spec_updates,
        "warnings": plan.warnings,
        "cleanup_plan": plan.cleanup_plan,
    }


def _execute_archive_plan(workspace: Workspace, plan: ArchivePlan) -> dict[str, object]:
    schema_conflicts = [
        finding
        for finding in plan.validation_findings
        if finding["code"] == "schema_artifact_conflict"
    ]
    if schema_conflicts:
        finding = schema_conflicts[0]
        raise CashError("schema_artifact_conflict", finding["message"], path=finding["path"])
    if plan.validation_findings and not plan.flags["no_validate"]:
        finding = plan.validation_findings[0]
        raise CashError("validation_failed", finding["message"], path=finding["path"])
    if plan.incomplete_tasks and not plan.flags["mark_tasks_complete"]:
        raise CashError("tasks_incomplete", "Complete tasks or use --mark-tasks-complete.")

    skip_specs = plan.flags["skip_specs"]
    mark_tasks_complete = plan.flags["mark_tasks_complete"]
    name = plan.name
    transaction = workspace.transaction()
    if mark_tasks_complete:
        transaction.write(
            f"openspec/changes/{name}/tasks.md",
            _completed_tasks_bytes(workspace, name),
        )
    if not skip_specs and not plan.sync_plan.already_synced:
        for relative, content in plan.sync_plan.writes.items():
            workspace.ensure_directory(os.path.dirname(relative))
            transaction.write(relative, content)
    legacy_cleanup = _legacy_cleanup(workspace, plan.touched, transaction)
    touched_relative = f".cash-skills/state/touched/{name}.json"
    snapshot_relative = f".cash-skills/state/snapshots/{name}.json"
    sync_relative = f".cash-skills/state/sync/{name}.json"
    for relative in (touched_relative, snapshot_relative, sync_relative):
        if workspace.is_file(relative):
            transaction.delete(relative)
    archive_manifest = {
        "version": 1,
        "change": name,
        "destination": plan.archived_path,
        "specs_synced": not skip_specs,
        "delta_digests": plan.sync_plan.delta_digests,
        "master_digests": (
            plan.sync_plan.master_after
            if not skip_specs
            else {
                relative: (
                    digest(workspace.read_bytes(relative))
                    if workspace.is_file(relative)
                    else None
                )
                for relative in plan.sync_plan.master_after
            }
        ),
        "touched_digest": hashlib.sha256(
            json.dumps(plan.touched, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        ).hexdigest(),
        "touched_files": list(plan.touched["files"]),
        "legacy_cleanup": legacy_cleanup,
    }
    transaction.write(
        f"openspec/changes/{name}/archive-manifest.json",
        (
            json.dumps(archive_manifest, ensure_ascii=False, separators=(",", ":"))
            + "\n"
        ).encode("utf-8"),
    )
    workspace.ensure_directory(os.path.dirname(plan.archived_path))
    transaction.move(f"openspec/changes/{name}", plan.archived_path)
    transaction.commit()

    applied_specs = [
        update["capability"]
        for update in plan.spec_updates
        if update["action"] == "apply"
    ]
    specs_status = (
        "no_delta_specs"
        if not plan.spec_updates
        else "skipped"
        if skip_specs
        else "already_synced"
        if plan.sync_plan.already_synced
        else "applied"
    )
    cleanup_warnings = _cleanup_warnings(plan)
    return {
        "schema_version": 1,
        "change": name,
        "preview_id": plan.preview_id,
        "archived_id": plan.archived_id,
        "archived_path": plan.archived_path,
        "applied_specs": applied_specs,
        "specs_status": specs_status,
        "cleanup_warnings": cleanup_warnings,
        "legacy_cleanup": legacy_cleanup,
        "destination": plan.archived_path,
        "specsSynced": bool(plan.spec_updates) and not skip_specs,
        "changedCapabilities": applied_specs,
        "legacyCleanup": legacy_cleanup,
    }


def _legacy_archive_result(result: dict[str, object]) -> dict[str, object]:
    return {
        "change": result["change"],
        "destination": result["destination"],
        "specsSynced": result["specsSynced"],
        "changedCapabilities": result["changedCapabilities"],
        "legacyCleanup": result["legacyCleanup"],
    }


def archive_change(
    workspace: Workspace,
    name: str,
    *,
    skip_specs: bool = False,
    no_validate: bool = False,
    mark_tasks_complete: bool = False,
) -> dict[str, object]:
    workspace.recover()
    plan = build_archive_plan(
        workspace,
        name,
        skip_specs=skip_specs,
        no_validate=no_validate,
        mark_tasks_complete=mark_tasks_complete,
    )
    return _legacy_archive_result(_execute_archive_plan(workspace, plan))


def _parse_archive_arguments(arguments: Sequence[str]) -> dict[str, object]:
    name: str | None = None
    check_preview: str | None = None
    preview = False
    json_mode = False
    skip_specs = False
    no_validate = False
    mark_tasks_complete = False
    index = 0
    while index < len(arguments):
        value = arguments[index]
        if value == "--json":
            json_mode = True
        elif value == "--preview":
            preview = True
        elif value == "--skip-specs":
            skip_specs = True
        elif value == "--no-validate":
            no_validate = True
        elif value == "--mark-tasks-complete":
            mark_tasks_complete = True
        elif value == "--check-preview":
            if check_preview is not None or index + 1 >= len(arguments):
                raise CashError("invalid_arguments", "--check-preview requires one preview identity.")
            check_preview = arguments[index + 1]
            index += 1
        elif value.startswith("--"):
            raise CashError("invalid_arguments", f"Unknown archive option: {value}")
        elif name is None:
            name = value
        else:
            raise CashError("invalid_arguments", "archive requires one change name.")
        index += 1
    if name is None:
        raise CashError("invalid_arguments", "archive requires one change name.")
    if preview and check_preview is not None:
        raise CashError("invalid_arguments", "--preview and --check-preview are mutually exclusive.")
    if (preview or check_preview is not None) and not json_mode:
        raise CashError("invalid_arguments", "Preview and checked archive require --json.")
    if check_preview is not None and not re.fullmatch(r"[0-9a-f]{64}", check_preview):
        raise CashError("invalid_arguments", "--check-preview must be lowercase 64-character hex.")
    return {
        "name": name,
        "preview": preview,
        "check_preview": check_preview,
        "json": json_mode,
        "skip_specs": skip_specs,
        "no_validate": no_validate,
        "mark_tasks_complete": mark_tasks_complete,
    }


def execute(command: str, arguments: Sequence[str]) -> int:
    if command == "sync":
        names = [value for value in arguments if not value.startswith("--")]
        if len(names) != 1:
            raise CashError("invalid_arguments", f"{command} requires one change name.")
        workspace = Workspace.discover(
            os.getcwd(),
            launcher_root=os.environ.get("CASH_PROJECT_ROOT"),
        )
        result = sync_change(workspace, names[0])
        if "--json" in arguments:
            print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
        else:
            print(f"{command} complete: {names[0]}")
        return 0

    parsed = _parse_archive_arguments(arguments)
    workspace = Workspace.discover(
        os.getcwd(),
        launcher_root=os.environ.get("CASH_PROJECT_ROOT"),
    )
    name = parsed["name"]
    flags = {
        "skip_specs": parsed["skip_specs"],
        "no_validate": parsed["no_validate"],
        "mark_tasks_complete": parsed["mark_tasks_complete"],
    }
    if parsed["preview"]:
        result = archive_preview(workspace, name, **flags)
    elif parsed["check_preview"] is not None:
        try:
            workspace.assert_readable()
            plan = build_archive_plan(
                workspace,
                name,
                reject_collision=False,
                **flags,
            )
        except CashError as error:
            raise CashError(
                "archive_preview_stale",
                f"Archive preview is stale: {error.message}",
                path=error.path,
            ) from error
        if plan.preview_id != parsed["check_preview"]:
            raise CashError(
                "archive_preview_stale",
                "Archive preview no longer matches the current workspace.",
            )
        result = _execute_archive_plan(workspace, plan)
    else:
        result = archive_change(workspace, name, **flags)
    if parsed["json"]:
        print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    else:
        print(f"{command} complete: {name}")
    return 0
