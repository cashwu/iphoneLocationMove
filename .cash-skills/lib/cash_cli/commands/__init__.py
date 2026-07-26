from __future__ import annotations

from collections.abc import Sequence

from . import analyze, archive, create, discovery, drift, lifecycle, search, tasks, validate


def execute(command: str, arguments: Sequence[str]) -> int:
    if command in {"list", "status", "instructions"}:
        return discovery.execute(command, arguments)
    if command == "new":
        return create.execute(arguments)
    if command in {"task", "in-progress", "touched"}:
        return tasks.execute(command, arguments)
    if command in {"park", "unpark"}:
        return lifecycle.execute(command, arguments)
    if command == "validate":
        return validate.execute(arguments)
    if command == "analyze":
        return analyze.execute(arguments)
    if command == "drift":
        return drift.execute(arguments)
    if command == "search":
        return search.execute(arguments)
    if command in {"sync", "archive"}:
        return archive.execute(command, arguments)
    raise LookupError(command)
