from __future__ import annotations

import re
from pathlib import Path

from .workspace import Workspace


_OPERATIONS = {
    "## ADDED Requirements": "ADDED",
    "## MODIFIED Requirements": "MODIFIED",
    "## REMOVED Requirements": "REMOVED",
    "## RENAMED Requirements": "RENAMED",
}
_REQUIREMENT = re.compile(r"### Requirement: (.+)")
_SCENARIO = re.compile(r"#### Scenario: (.+)")
_TASK = re.compile(r"^- \[[ xX]\](?: \[P\])? ([0-9]+(?:\.[0-9]+)*)\s+(.+)$")
_RENAME_FROM = re.compile(r"- FROM: `### Requirement: (.+)`")
_RENAME_TO = re.compile(r"- TO: `### Requirement: (.+)`")


def finding(code: str, path: str, message: str) -> dict[str, str]:
    return {"code": code, "path": path, "message": message}


def _master_titles(workspace: Workspace, capability: str) -> set[str] | None:
    relative = f"openspec/specs/{capability}/spec.md"
    if not workspace.is_file(relative):
        return None
    return {
        match.group(1)
        for line in workspace.read_text(relative).splitlines()
        if (match := _REQUIREMENT.fullmatch(line)) is not None
    }


def _requirement_blocks(lines: list[str]) -> list[tuple[str, str, int, int]]:
    operation = ""
    blocks: list[tuple[str, str, int, int]] = []
    current: tuple[str, str, int] | None = None
    for index, line in enumerate(lines):
        if line in _OPERATIONS:
            if current is not None:
                blocks.append((*current, index))
                current = None
            operation = _OPERATIONS[line]
            continue
        match = _REQUIREMENT.fullmatch(line)
        if match is not None:
            if current is not None:
                blocks.append((*current, index))
            current = (operation, match.group(1), index)
    if current is not None:
        blocks.append((*current, len(lines)))
    return blocks


def validate_delta_spec(
    workspace: Workspace,
    path: Path,
    capability: str,
    *,
    identities_already_applied: bool = False,
) -> list[dict[str, str]]:
    relative = workspace.relative(path)
    lines = workspace.read_text(relative).splitlines()
    findings: list[dict[str, str]] = []
    sections = [line for line in lines if line.startswith("## ") and line.endswith(" Requirements")]
    if not sections or any(section not in _OPERATIONS for section in sections):
        findings.append(finding("delta_operation_invalid", relative, "Delta operation heading is invalid."))
    master_titles = _master_titles(workspace, capability)
    seen: dict[tuple[str, str], int] = {}
    operations_by_title: dict[str, set[str]] = {}
    for operation, title, start, end in _requirement_blocks(lines):
        if not operation or operation == "RENAMED":
            findings.append(
                finding("requirement_section_invalid", f"{relative}:{start + 1}", "Requirement is outside a supported section.")
            )
            continue
        key = (operation, title)
        seen[key] = seen.get(key, 0) + 1
        operations_by_title.setdefault(title, set()).add(operation)
        if seen[key] > 1:
            findings.append(
                finding("duplicate_requirement", f"{relative}:{start + 1}", f"Duplicate {operation} requirement: {title}")
            )
        block = lines[start + 1 : end]
        if not any(_SCENARIO.fullmatch(line) for line in block):
            findings.append(
                finding("spec_missing_scenario", f"{relative}:{start + 1}", f"Requirement has no scenario: {title}")
            )
        prose = "\n".join(block)
        if operation in {"ADDED", "MODIFIED"} and not re.search(r"(?:SHALL|MUST)", prose):
            findings.append(
                finding("normative_verb_missing", f"{relative}:{start + 1}", f"Requirement lacks SHALL/MUST: {title}")
            )
        if (
            not identities_already_applied
            and operation in {"MODIFIED", "REMOVED"}
            and master_titles is not None
            and title not in master_titles
        ):
            findings.append(
                finding(
                    "requirement_identity_mismatch",
                    f"{relative}:{start + 1}",
                    f"Requirement title does not exist byte-for-byte in master spec: {title}",
                )
            )
    rename_sources: list[tuple[str, int]] = []
    added_titles = {
        title
        for title, operations in operations_by_title.items()
        if "ADDED" in operations
    }
    rename_destinations: dict[str, str] = {}
    for index, line in enumerate(lines):
        match = _RENAME_FROM.fullmatch(line)
        if match is None:
            continue
        rename_sources.append((match.group(1), index))
        next_line = lines[index + 1] if index + 1 < len(lines) else ""
        destination_match = _RENAME_TO.fullmatch(next_line)
        if destination_match is None:
            findings.append(
                finding("rename_pair_invalid", f"{relative}:{index + 1}", "RENAMED FROM must be followed by TO.")
            )
        else:
            destination = destination_match.group(1)
            if destination in rename_destinations:
                findings.append(
                    finding(
                        "operation_collision",
                        f"{relative}:{index + 2}",
                        f"RENAMED destination is claimed by multiple renames: {destination}",
                    )
                )
            else:
                rename_destinations[destination] = match.group(1)
            if destination in added_titles:
                findings.append(
                    finding(
                        "operation_collision",
                        f"{relative}:{index + 2}",
                        f"RENAMED destination collides with ADDED: {destination}",
                    )
                )
            if (
                not identities_already_applied
                and master_titles is not None
                and destination != match.group(1)
                and destination in master_titles
            ):
                findings.append(
                    finding(
                        "operation_collision",
                        f"{relative}:{index + 2}",
                        f"RENAMED destination already exists in master spec: {destination}",
                    )
                )
        if (
            not identities_already_applied
            and master_titles is not None
            and match.group(1) not in master_titles
        ):
            findings.append(
                finding(
                    "requirement_identity_mismatch",
                    f"{relative}:{index + 1}",
                    f"RENAMED FROM title does not exist byte-for-byte in master spec: {match.group(1)}",
                )
            )
        operations_by_title.setdefault(match.group(1), set()).add("RENAMED")
    if "## RENAMED Requirements" in lines and not rename_sources:
        findings.append(finding("rename_pair_invalid", relative, "RENAMED section has no FROM/TO pair."))
    for title, operations in operations_by_title.items():
        if "REMOVED" in operations and "RENAMED" in operations:
            findings.append(
                finding("operation_collision", relative, f"REMOVED and RENAMED collide for: {title}")
            )
    return findings


def validate_tasks(workspace: Workspace, path: Path) -> list[dict[str, str]]:
    relative = workspace.relative(path)
    labels: set[str] = set()
    findings: list[dict[str, str]] = []
    count = 0
    for number, line in enumerate(workspace.read_text(relative).splitlines(), start=1):
        if not line.startswith("- ["):
            continue
        match = _TASK.fullmatch(line)
        if match is None:
            findings.append(finding("task_syntax_invalid", f"{relative}:{number}", "Task checkbox syntax is invalid."))
            continue
        count += 1
        label = match.group(1)
        if label in labels:
            findings.append(finding("duplicate_task_id", f"{relative}:{number}", f"Duplicate task id: {label}"))
        labels.add(label)
    if count == 0:
        findings.append(finding("tasks_empty", relative, "tasks.md has no tasks."))
    return findings


def validate_change(workspace: Workspace, name: str) -> list[dict[str, str]]:
    change = workspace.change_path(name)
    change_relative = workspace.relative(change)
    if not workspace.is_dir(change_relative):
        return [finding("change_not_found", f"openspec/changes/{name}", "Active change does not exist.")]
    findings: list[dict[str, str]] = []
    required = {
        ".openspec.yaml": ("schema: spec-driven",),
        "proposal.md": ("## Summary", "## Capabilities", "## Impact"),
        "design.md": ("## Implementation Contract",),
        "tasks.md": ("## ",),
    }
    for artifact_relative, headings in required.items():
        relative = f"{change_relative}/{artifact_relative}"
        path = workspace.root / relative
        if not workspace.is_file(relative):
            findings.append(finding("artifact_missing", relative, "Required artifact is missing."))
            continue
        content = workspace.read_text(relative)
        for heading in headings:
            if heading not in content:
                findings.append(
                    finding("heading_missing", workspace.relative(path), f"Missing required heading or field: {heading}")
                )
    tasks = change / "tasks.md"
    if workspace.is_file(workspace.relative(tasks)):
        findings.extend(validate_tasks(workspace, tasks))
    specs_relative = f"{change_relative}/specs"
    sync_manifest_relative = f".cash-skills/state/sync/{name}.json"
    identities_already_applied = False
    if workspace.is_file(sync_manifest_relative):
        from .spec_merge import build_sync_plan

        identities_already_applied = build_sync_plan(workspace, name).already_synced
    spec_paths = [
        workspace.root / relative
        for relative in workspace.spec_files(specs_relative)
    ] if workspace.is_dir(specs_relative) else []
    if not spec_paths:
        findings.append(finding("artifact_missing", f"openspec/changes/{name}/specs", "At least one delta spec is required."))
    for path in spec_paths:
        findings.extend(
            validate_delta_spec(
                workspace,
                path,
                path.parent.name,
                identities_already_applied=identities_already_applied,
            )
        )
    return findings


def validate_all(workspace: Workspace) -> list[dict[str, object]]:
    names = sorted(
        (
            name
            for name, kind in workspace.list_directory("openspec/changes")
            if kind == "directory"
            and name not in {"archive", ".parked"}
            and re.fullmatch(r"[a-z][a-z0-9-]*", name)
        ),
        key=lambda value: value.encode("utf-8"),
    )
    return [
        {"name": name, "findings": validate_change(workspace, name)}
        for name in names
    ]
