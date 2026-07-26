from __future__ import annotations

import json
import os
import re
from collections.abc import Iterator, Sequence
from pathlib import Path

from ..errors import CashError
from ..workspace import Workspace


def _tokens(value: str) -> list[str]:
    return [token for token in re.findall(r"\w+", value.casefold()) if token]


def _is_archived_review(parts: tuple[str, ...]) -> bool:
    return (
        parts[:3] == ("openspec", "changes", "archive")
        and "reviews" in parts[3:]
    )


def _documents(
    workspace: Workspace,
    scope: str,
) -> Iterator[tuple[str, str]]:
    if scope == "specs":
        if workspace.is_dir("openspec/specs"):
            yield from workspace.walk_text_files("openspec/specs")
        return
    if scope == "active":
        yield from workspace.walk_text_files(
            "openspec",
            exclude_directory=_is_archived_review,
        )
        return
    yield from workspace.walk_text_files("openspec")


def _title(text: str, fallback: str) -> str:
    for line in text.splitlines():
        if line.startswith("#"):
            value = line.lstrip("#").strip()
            if value:
                return value
    return fallback


def _excerpt(text: str, tokens: list[str], *, limit: int = 240) -> str:
    folded = text.casefold()
    positions = [folded.find(token) for token in tokens]
    matches = [position for position in positions if position >= 0]
    start = max(0, (min(matches) if matches else 0) - 60)
    value = " ".join(text[start : start + limit].split())
    return value[:limit]


def search_payload(
    workspace: Workspace,
    query: str,
    *,
    limit: int,
    scope: str = "active",
) -> dict[str, object]:
    tokens = _tokens(query)
    if not tokens:
        raise CashError("invalid_query", "Search query must contain text.")
    if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= 100:
        raise CashError("invalid_limit", "Search limit must be between 1 and 100.")
    if scope not in {"specs", "active", "all"}:
        raise CashError("invalid_scope", "Search scope must be specs, active, or all.")
    results: list[dict[str, object]] = []
    for relative, text in _documents(workspace, scope):
        title = _title(text, Path(relative).name)
        folded_path = relative.casefold()
        folded_title = title.casefold()
        folded_body = text.casefold()
        raw_score = 0
        for token in tokens:
            raw_score += folded_path.count(token) * 5
            raw_score += folded_title.count(token) * 3
            raw_score += folded_body.count(token)
        if raw_score == 0:
            continue
        results.append(
            {
                "path": relative,
                "title": title,
                "excerpt": _excerpt(text, tokens),
                "score": round(raw_score / (len(tokens) * 5), 6),
            }
        )
    results.sort(
        key=lambda item: (
            -item["score"],
            item["path"].encode("utf-8"),
            item["title"],
            item["excerpt"],
        )
    )
    return {"results": results[:limit]}


def execute(arguments: Sequence[str]) -> int:
    positional: list[str] = []
    limit_value: str | None = None
    scope = "active"
    index = 0
    while index < len(arguments):
        value = arguments[index]
        if value in {"--limit", "--scope"}:
            if index + 1 >= len(arguments) or arguments[index + 1].startswith("-"):
                code = "invalid_limit" if value == "--limit" else "invalid_scope"
                raise CashError(code, f"{value} requires a value.")
            if value == "--limit":
                limit_value = arguments[index + 1]
            else:
                scope = arguments[index + 1]
            index += 2
            continue
        if value == "--json":
            index += 1
            continue
        if value.startswith("--"):
            raise CashError("invalid_arguments", f"Unknown option: {value}")
        positional.append(value)
        index += 1
    if len(positional) != 1:
        raise CashError("invalid_arguments", "search requires exactly one query.")
    query = positional[0]
    try:
        limit = int(limit_value) if limit_value is not None else 10
    except ValueError as error:
        raise CashError("invalid_limit", "--limit requires an integer.") from error
    workspace = Workspace.discover(
        os.getcwd(),
        launcher_root=os.environ.get("CASH_PROJECT_ROOT"),
    )
    workspace.assert_readable()
    payload = search_payload(workspace, query, limit=limit, scope=scope)
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    return 0
