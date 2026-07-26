from __future__ import annotations

import datetime as dt
import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path

from .errors import CashError
from .workspace import Workspace


_SECTION = re.compile(r"## (ADDED|MODIFIED|REMOVED|RENAMED) Requirements")
_REQUIREMENT = re.compile(r"### Requirement: (.+)")
_RENAME_FROM = re.compile(r"- FROM: `### Requirement: (.+)`")
_RENAME_TO = re.compile(r"- TO: `### Requirement: (.+)`")
_CODE_SPAN = re.compile(r"`([^`\r\n]+)`")
_TRACE = re.compile(r"\n*<!-- @trace\n.*?-->\n*", re.DOTALL)
_VERIFICATION_CLAUSE = re.compile(
    r"(?:[；;,，]\s*)?(?:並)?以\s+|(?:verification targets?|驗證目標)\s*[:：]\s*",
    re.IGNORECASE,
)


@dataclass(slots=True)
class Delta:
    added: dict[str, str]
    modified: dict[str, str]
    removed: set[str]
    renamed: dict[str, str]


@dataclass(slots=True)
class SyncPlan:
    writes: dict[str, bytes]
    delta_digests: dict[str, str]
    master_before: dict[str, str | None]
    master_after: dict[str, str]
    already_synced: bool


def digest(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def parse_delta(text: str, *, path: str) -> Delta:
    lines = text.splitlines(keepends=True)
    current_section = ""
    current_title: str | None = None
    current_start = 0
    blocks: dict[str, dict[str, str]] = {
        "ADDED": {},
        "MODIFIED": {},
        "REMOVED": {},
    }

    def close(end: int) -> None:
        nonlocal current_title
        if current_title is None:
            return
        block = "".join(lines[current_start:end]).strip() + "\n"
        target = blocks[current_section]
        if current_title in target:
            raise CashError("requirement_collision", f"Duplicate {current_section} requirement: {current_title}", path=path)
        target[current_title] = block
        current_title = None

    for index, line in enumerate(lines):
        stripped = line.rstrip("\n")
        section = _SECTION.fullmatch(stripped)
        if section is not None:
            close(index)
            current_section = section.group(1)
            continue
        requirement = _REQUIREMENT.fullmatch(stripped)
        if requirement is not None:
            close(index)
            if current_section not in blocks:
                raise CashError("delta_invalid", "Requirement appears outside ADDED/MODIFIED/REMOVED.", path=path)
            current_title = requirement.group(1)
            current_start = index
    close(len(lines))
    renamed: dict[str, str] = {}
    for index, line in enumerate(lines):
        source = _RENAME_FROM.fullmatch(line.rstrip("\n"))
        if source is None:
            continue
        next_line = lines[index + 1].rstrip("\n") if index + 1 < len(lines) else ""
        destination = _RENAME_TO.fullmatch(next_line)
        if destination is None or source.group(1) in renamed:
            raise CashError("rename_invalid", "RENAMED entries require unique FROM/TO pairs.", path=path)
        renamed[source.group(1)] = destination.group(1)
    return Delta(
        added=blocks["ADDED"],
        modified=blocks["MODIFIED"],
        removed=set(blocks["REMOVED"]),
        renamed=renamed,
    )


def _master(text: str) -> tuple[str, list[tuple[str, str]]]:
    lines = text.splitlines(keepends=True)
    starts = [
        (index, match.group(1))
        for index, line in enumerate(lines)
        if (match := _REQUIREMENT.fullmatch(line.rstrip("\n"))) is not None
    ]
    if not starts:
        return text.rstrip() + "\n\n", []
    prefix = "".join(lines[: starts[0][0]]).rstrip() + "\n\n"
    blocks: list[tuple[str, str]] = []
    for position, (start, title) in enumerate(starts):
        end = starts[position + 1][0] if position + 1 < len(starts) else len(lines)
        blocks.append((title, "".join(lines[start:end]).strip() + "\n"))
    return prefix, blocks


def _trace(change: str, code_paths: list[str], test_paths: list[str]) -> str:
    lines = [
        "<!-- @trace",
        f"source: {change}",
        f"updated: {dt.date.today().isoformat()}",
        "code:",
    ]
    lines.extend(f"  - {path}" for path in code_paths)
    lines.append("tests:")
    lines.extend(f"  - {path}" for path in test_paths)
    lines.append("-->")
    return "\n".join(lines) + "\n"


def _with_trace(block: str, trace: str) -> str:
    cleaned = _TRACE.sub("\n", block).rstrip()
    return f"{cleaned}\n\n{trace}"


def _paths_in_section(workspace: Workspace, path: Path, heading: str) -> list[str]:
    relative = workspace.relative(path)
    if not workspace.is_file(relative):
        return []
    lines = workspace.read_text(relative).splitlines()
    active = False
    values: list[str] = []
    for line in lines:
        if line == heading:
            active = True
            continue
        if active and line.startswith("## "):
            break
        if active:
            values.extend(value for value in _CODE_SPAN.findall(line) if "/" in value)
    return sorted(set(values), key=lambda value: value.encode("utf-8"))


def _verification_path(value: str) -> str | None:
    token = value.split(maxsplit=1)[0]
    if token == "cli-checks.fish":
        return "scripts/cash-cli/tests/cli-checks.fish"
    if token == "skill-checks.fish":
        return "scripts/cash-skills/tests/skill-checks.fish"
    if "/" in token and (
        "/tests/" in f"/{token}"
        or Path(token).name.startswith("test_")
        or token.endswith((".fish", ".sh"))
    ):
        return token
    return None


def _task_paths(workspace: Workspace, path: Path) -> list[str]:
    relative = workspace.relative(path)
    if not workspace.is_file(relative):
        return []
    values: set[str] = set()
    for line in workspace.read_text(relative).splitlines():
        clause = _VERIFICATION_CLAUSE.search(line)
        if clause is None:
            continue
        for value in _CODE_SPAN.findall(line[clause.end() :]):
            if (target := _verification_path(value)) is not None:
                values.add(target)
    return sorted(
        values,
        key=lambda value: value.encode("utf-8"),
    )


def _merge(
    master_text: str,
    delta: Delta,
    *,
    trace: str,
    path: str,
) -> str:
    prefix, ordered = _master(master_text)
    titles = [title for title, _ in ordered]
    if len(titles) != len(set(titles)):
        raise CashError("requirement_collision", "Master spec contains duplicate requirement titles.", path=path)
    master = dict(ordered)
    operations: dict[str, set[str]] = {}
    for operation, values in (
        ("MODIFIED", delta.modified),
        ("REMOVED", delta.removed),
        ("ADDED", delta.added),
        ("RENAMED", delta.renamed),
    ):
        for title in values:
            operations.setdefault(title, set()).add(operation)
    for title, kinds in operations.items():
        if len(kinds) > 1 and kinds != {"MODIFIED", "RENAMED"}:
            raise CashError("requirement_collision", f"Illegal operation collision for: {title}", path=path)
    for title in set(delta.modified) | delta.removed | set(delta.renamed):
        if title not in master:
            raise CashError("requirement_identity_mismatch", f"Requirement not found: {title}", path=path)
    for title in delta.added:
        if title in master:
            raise CashError("requirement_collision", f"ADDED requirement exists: {title}", path=path)
    rename_destinations: dict[str, str] = {}
    for source, destination in delta.renamed.items():
        if destination in master and destination != source:
            raise CashError("requirement_collision", f"RENAMED destination exists: {destination}", path=path)
        if destination in delta.added:
            raise CashError("requirement_collision", f"RENAMED destination collides with ADDED: {destination}", path=path)
        if destination in rename_destinations:
            raise CashError(
                "requirement_collision",
                f"RENAMED destination is claimed by multiple renames: {destination}",
                path=path,
            )
        rename_destinations[destination] = source

    for title, block in delta.modified.items():
        master[title] = _with_trace(block, trace)
    for title in delta.removed:
        del master[title]
        ordered = [(existing, block) for existing, block in ordered if existing != title]
    for title, block in delta.added.items():
        master[title] = _with_trace(block, trace)
        ordered.append((title, master[title]))
    for source, destination in delta.renamed.items():
        block = master.pop(source)
        renamed_block = re.sub(
            rf"\A### Requirement: {re.escape(source)}",
            f"### Requirement: {destination}",
            block,
            count=1,
        )
        master[destination] = _with_trace(renamed_block, trace)
        ordered = [
            (destination if title == source else title, block)
            for title, block in ordered
        ]
    rendered: list[str] = []
    seen: set[str] = set()
    for title, _ in ordered:
        if title in seen or title not in master:
            continue
        rendered.append(master[title].rstrip())
        seen.add(title)
    for title in delta.added:
        if title not in seen:
            rendered.append(master[title].rstrip())
            seen.add(title)
    return prefix + "\n\n".join(rendered).rstrip() + "\n"


def build_sync_plan(workspace: Workspace, name: str) -> SyncPlan:
    change = workspace.change_path(name)
    delta_paths = [
        workspace.root / relative
        for relative in workspace.spec_files(workspace.relative(change / "specs"))
    ]
    if not delta_paths:
        raise CashError("delta_missing", "Change has no delta specs.")
    delta_digests = {
        workspace.relative(path): digest(workspace.read_bytes(workspace.relative(path)))
        for path in delta_paths
    }
    manifest_relative = f".cash-skills/state/sync/{name}.json"
    if workspace.is_file(manifest_relative):
        try:
            manifest = json.loads(workspace.read_text(manifest_relative))
        except json.JSONDecodeError as error:
            raise CashError("sync_manifest_invalid", "Sync manifest is malformed.") from error
        if manifest.get("delta_digests") != delta_digests:
            raise CashError("sync_manifest_mismatch", "Delta inputs changed after sync.")
        for relative, expected in manifest.get("master_after", {}).items():
            if not workspace.is_file(relative) or digest(workspace.read_bytes(relative)) != expected:
                raise CashError("sync_manifest_mismatch", "Master spec changed after sync.", path=relative)
        return SyncPlan(
            writes={},
            delta_digests=delta_digests,
            master_before=manifest["master_before"],
            master_after=manifest["master_after"],
            already_synced=True,
        )

    code_paths = _paths_in_section(workspace, change / "proposal.md", "## Impact")
    test_paths = _task_paths(workspace, change / "tasks.md")
    trace = _trace(name, code_paths, test_paths)
    writes: dict[str, bytes] = {}
    before: dict[str, str | None] = {}
    after: dict[str, str] = {}
    for delta_path in delta_paths:
        capability = delta_path.parent.name
        master_relative = f"openspec/specs/{capability}/spec.md"
        if workspace.is_file(master_relative):
            master_bytes = workspace.read_bytes(master_relative)
            master_text = master_bytes.decode("utf-8")
            before[master_relative] = digest(master_bytes)
        else:
            master_text = (
                f"# {capability} Specification\n\n"
                "## Purpose\n\n"
                f"{capability} capability.\n\n"
                "## Requirements\n\n"
            )
            before[master_relative] = None
        delta = parse_delta(
            workspace.read_text(workspace.relative(delta_path)),
            path=workspace.relative(delta_path),
        )
        merged = _merge(master_text, delta, trace=trace, path=master_relative).encode("utf-8")
        writes[master_relative] = merged
        after[master_relative] = digest(merged)
    return SyncPlan(
        writes=writes,
        delta_digests=delta_digests,
        master_before=before,
        master_after=after,
        already_synced=False,
    )


def manifest_bytes(name: str, plan: SyncPlan) -> bytes:
    value = {
        "version": 1,
        "change": name,
        "delta_digests": plan.delta_digests,
        "master_before": plan.master_before,
        "master_after": plan.master_after,
    }
    return (
        json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n"
    ).encode("utf-8")
