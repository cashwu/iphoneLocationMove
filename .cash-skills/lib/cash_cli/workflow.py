from __future__ import annotations

import re
from dataclasses import dataclass

from .errors import CashError
from .resources import ARTIFACTS_BY_ID, ARTIFACT_GRAPH, NO_SPEC_ARTIFACT_GRAPH, ArtifactResource
from .workspace import Workspace


_SCHEMA_VALUES = {"spec-driven", "no-spec"}
_TASK_ORDER_VALUES = {"document", "dependency"}
_KEY = re.compile(r"([a-z][a-z0-9_-]*):(.*)\Z")
_TASK = re.compile(r"^- \[([ xX])\] (\[P\] )?(.+)$")
_LABEL = re.compile(r"^(\d+(?:\.\d+)*)\s+(.+)$")
_AFTER = re.compile(r"^\[after: ([^\]]*)\] (\S.*)$")
_AFTER_LIKE = re.compile(r"\[after\b")
_LABEL_VALUE = re.compile(r"\d+(?:\.\d+)*\Z")


@dataclass(frozen=True, slots=True)
class ChangeMetadata:
    schema: str
    task_order: str


@dataclass(frozen=True, slots=True)
class TaskEntry:
    line_index: int
    ordinal: str
    label: str
    description: str
    done: bool
    parallel: bool
    after: tuple[str, ...]


def read_change_metadata(workspace: Workspace, name: str) -> ChangeMetadata:
    active = workspace.change_path(name)
    parked = workspace.change_path(name, parked=True)
    active_relative = workspace.relative(active)
    parked_relative = workspace.relative(parked)
    active_exists = workspace.is_dir(active_relative)
    parked_exists = workspace.is_dir(parked_relative)
    if active_exists and parked_exists:
        raise CashError("change_identity_collision", f"Change exists as active and parked: {name}")
    if active_exists:
        relative = f"{active_relative}/.openspec.yaml"
    elif parked_exists:
        relative = f"{parked_relative}/.openspec.yaml"
    else:
        relative = f"openspec/changes/{name}/.openspec.yaml"
    if not workspace.is_file(relative):
        raise CashError(
            "change_metadata_invalid",
            "Change metadata is missing.",
            2,
            relative,
        )
    values: dict[str, list[str]] = {}
    for line_number, line in enumerate(workspace.read_text(relative).splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line != line.lstrip() or ":" not in line:
            continue
        match = _KEY.fullmatch(line)
        if match is None:
            continue
        key, suffix = match.groups()
        if key not in {"schema", "task_order"}:
            continue
        if not suffix.startswith(" "):
            raise CashError(
                "change_metadata_invalid",
                "Change metadata values require a single space after the colon.",
                2,
                f"{relative}:{line_number}",
            )
        values.setdefault(key, []).append(suffix[1:])
    schema_values = values.get("schema", [])
    order_values = values.get("task_order", [])
    if len(schema_values) != 1 or schema_values[0] not in _SCHEMA_VALUES:
        raise CashError(
            "change_metadata_invalid",
            "Change metadata schema must be exactly spec-driven or no-spec.",
            2,
            relative,
        )
    if len(order_values) > 1 or (
        order_values and order_values[0] not in _TASK_ORDER_VALUES
    ):
        raise CashError(
            "change_metadata_invalid",
            "Change metadata task_order must be document or dependency.",
            2,
            relative,
        )
    return ChangeMetadata(schema_values[0], order_values[0] if order_values else "document")


def graph_for_metadata(metadata: ChangeMetadata) -> tuple[ArtifactResource, ...]:
    if metadata.schema == "no-spec":
        return NO_SPEC_ARTIFACT_GRAPH
    return ARTIFACT_GRAPH


def graph_for_change(workspace: Workspace, name: str) -> tuple[ArtifactResource, ...]:
    return graph_for_metadata(read_change_metadata(workspace, name))


def artifact_for_change(
    workspace: Workspace,
    name: str,
    artifact_id: str,
) -> ArtifactResource:
    try:
        artifact = ARTIFACTS_BY_ID[artifact_id]
    except KeyError as error:
        raise CashError("unknown_artifact", f"Unknown artifact: {artifact_id}") from error
    graph = {entry.id: entry for entry in graph_for_change(workspace, name)}
    if artifact_id not in graph:
        raise CashError(
            "artifact_not_in_schema",
            f"Artifact is not part of the {read_change_metadata(workspace, name).schema} schema: {artifact_id}",
            2,
            f"openspec/changes/{name}/.openspec.yaml",
        )
    return graph[artifact_id]


def validate_task_order(metadata: ChangeMetadata) -> None:
    if metadata.task_order not in _TASK_ORDER_VALUES:
        raise CashError("change_metadata_invalid", "Change metadata task_order must be document or dependency.")


def parse_task_entries(content: str, *, task_order: str = "document") -> list[TaskEntry]:
    entries: list[TaskEntry] = []
    labels: set[str] = set()
    for line_index, line in enumerate(content.splitlines()):
        match = _TASK.fullmatch(line)
        if match is None:
            continue
        description = match.group(3)
        label_match = _LABEL.fullmatch(description)
        if label_match is None:
            raise CashError("task_id_invalid", "Task labels must be present and unique.")
        label, remainder = label_match.groups()
        if label in labels:
            code = "task_dependency_invalid" if task_order == "dependency" else "task_id_invalid"
            raise CashError(code, "Task labels must be present and unique.")
        labels.add(label)
        after: tuple[str, ...] = ()
        if _AFTER_LIKE.search(remainder):
            marker = _AFTER.fullmatch(remainder)
            if marker is None or len(_AFTER_LIKE.findall(remainder)) != 1:
                raise CashError("task_dependency_invalid", "Task dependency declaration is malformed.")
            raw = marker.group(1)
            if not raw or ", " in raw and any(not value for value in raw.split(", ")):
                raise CashError("task_dependency_invalid", "Task dependency declaration is empty or malformed.")
            values = raw.split(", ")
            if any(_LABEL_VALUE.fullmatch(value) is None for value in values):
                raise CashError("task_dependency_invalid", "Task dependency reference is malformed.")
            if len(values) != len(set(values)):
                raise CashError("task_dependency_invalid", "Task dependency references must be unique.")
            after = tuple(values)
        if task_order == "document" and after:
            raise CashError("task_order_mismatch", "Dependency declarations require task_order: dependency.")
        entries.append(TaskEntry(
            line_index=line_index,
            ordinal=str(len(entries) + 1),
            label=label,
            description=description,
            done=match.group(1).lower() == "x",
            parallel=match.group(2) is not None,
            after=after,
        ))
    if task_order == "dependency":
        known = {entry.label for entry in entries}
        by_label = {entry.label: entry for entry in entries}
        for entry in entries:
            for dependency in entry.after:
                if dependency not in known:
                    raise CashError("task_dependency_invalid", f"Unknown task dependency: {dependency}")
                if dependency == entry.label:
                    raise CashError("task_dependency_invalid", f"Task cannot depend on itself: {entry.label}")
            if entry.done and any(not by_label[dependency].done for dependency in entry.after):
                raise CashError("task_dependency_invalid", f"Completed task still depends on pending task: {entry.label}")
        visiting: set[str] = set()
        visited: set[str] = set()
        def visit(label: str) -> None:
            if label in visiting:
                raise CashError("task_dependency_invalid", "Task dependency cycle detected.")
            if label in visited:
                return
            visiting.add(label)
            for dependency in by_label[label].after:
                visit(dependency)
            visiting.remove(label)
            visited.add(label)
        for entry in entries:
            visit(entry.label)
    return entries


def task_schedule(content: str, *, task_order: str = "document") -> dict[str, object]:
    entries = parse_task_entries(content, task_order=task_order)
    by_label = {entry.label: entry for entry in entries}
    dependencies = {
        entry.ordinal: [
            by_label[label].ordinal
            for label in sorted(entry.after, key=lambda value: int(by_label[value].ordinal))
        ]
        for entry in entries
    }
    ready: list[str] = []
    if task_order == "dependency":
        ready = [
            entry.ordinal
            for entry in entries
            if not entry.done and all(by_label[label].done for label in entry.after)
        ]
    else:
        for index, entry in enumerate(entries):
            if entry.done:
                continue
            if any(not prior.done for prior in entries[:index]):
                break
            ready.append(entry.ordinal)
            if not entry.parallel:
                break
            for following in entries[index + 1:]:
                if following.done or not following.parallel:
                    break
                ready.append(following.ordinal)
            break
    blocked = [entry.ordinal for entry in entries if not entry.done and entry.ordinal not in ready]
    return {
        "mode": task_order,
        "ready_ids": ready,
        "blocked_ids": blocked,
        "dependencies": dependencies,
    }
