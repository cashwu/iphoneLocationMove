from __future__ import annotations

import re
from dataclasses import dataclass


_LOCALE = re.compile(r"[A-Za-z][A-Za-z0-9_-]*\Z")
_ARTIFACT_ID = re.compile(r"[a-z][a-z0-9-]*\Z")
_FORBIDDEN_YAML = ("'", '"', "&", "*", "!", "{", "}", "[", "]")


@dataclass(slots=True)
class ConfigError(ValueError):
    path: str
    field: str
    message: str

    def __post_init__(self) -> None:
        ValueError.__init__(self, f"{self.path}: {self.field}: {self.message}")


def _lines(text: str, *, path: str) -> list[str]:
    if "\r" in text:
        raise ConfigError(path, "encoding", "only UTF-8 with LF line endings is allowed")
    if "\t" in text:
        raise ConfigError(path, "indentation", "tabs are not allowed")
    return text.splitlines()


def _is_ignored(line: str) -> bool:
    stripped = line.strip()
    return not stripped or stripped.startswith("#")


def _reject_yaml_features(value: str, *, path: str, field: str) -> None:
    # A plain YAML scalar may legitimately contain these characters mid-text;
    # only a LEADING indicator changes how a real YAML parser reads the value
    # (flow collection, quoted scalar, anchor, alias, tag). Rejecting them
    # anywhere would reject ordinary prose such as "use [P] markers".
    # ` #` still begins a trailing comment at any position, so it stays rejected.
    if " #" in value or value.startswith(_FORBIDDEN_YAML):
        raise ConfigError(path, field, "unsupported YAML syntax")


def parse_cash_config(text: str, *, path: str) -> dict[str, object]:
    allowed = {"locale", "tdd", "audit", "parallel_tasks"}
    parsed: dict[str, object] = {}
    for number, line in enumerate(_lines(text, path=path), start=1):
        if _is_ignored(line):
            continue
        if line != line.lstrip() or ": " not in line:
            raise ConfigError(path, f"line {number}", "expected unindented key: value")
        key, value = line.split(": ", 1)
        if key not in allowed:
            raise ConfigError(path, key or f"line {number}", "unknown key")
        if key in parsed:
            raise ConfigError(path, key, "duplicate key")
        if not value:
            raise ConfigError(path, key, "value is required")
        _reject_yaml_features(value, path=path, field=key)
        if key == "locale":
            if _LOCALE.fullmatch(value) is None:
                raise ConfigError(path, key, "invalid locale")
            parsed[key] = value
        else:
            if value not in {"true", "false"}:
                raise ConfigError(path, key, "expected lowercase true or false")
            parsed[key] = value == "true"
    return parsed


def parse_openspec_config(text: str, *, path: str) -> dict[str, object]:
    lines = _lines(text, path=path)
    parsed: dict[str, object] = {"context": "", "rules": {}}
    seen: set[str] = set()
    index = 0
    while index < len(lines):
        line = lines[index]
        index += 1
        if _is_ignored(line):
            continue
        if line == "schema: spec-driven":
            if "schema" in seen:
                raise ConfigError(path, "schema", "duplicate key")
            parsed["schema"] = "spec-driven"
            seen.add("schema")
            continue
        if line == "context: |":
            if "context" in seen:
                raise ConfigError(path, "context", "duplicate key")
            seen.add("context")
            content: list[str] = []
            while index < len(lines):
                candidate = lines[index]
                if candidate.startswith("  ") and not candidate.startswith("    "):
                    content.append(candidate[2:])
                    index += 1
                    continue
                if not candidate.strip() or candidate.lstrip().startswith("#"):
                    index += 1
                    continue
                break
            parsed["context"] = "\n".join(content)
            continue
        if line == "rules:":
            if "rules" in seen:
                raise ConfigError(path, "rules", "duplicate key")
            seen.add("rules")
            rules: dict[str, list[str]] = {}
            while index < len(lines):
                candidate = lines[index]
                if not candidate.strip() or candidate.lstrip().startswith("#"):
                    index += 1
                    continue
                match = re.fullmatch(r"  ([a-z][a-z0-9-]*):", candidate)
                if match is None:
                    break
                artifact = match.group(1)
                if _ARTIFACT_ID.fullmatch(artifact) is None or artifact in rules:
                    raise ConfigError(path, artifact, "invalid or duplicate artifact key")
                index += 1
                items: list[str] = []
                while index < len(lines) and lines[index].startswith("    - "):
                    item = lines[index][6:]
                    if not item:
                        raise ConfigError(path, artifact, "empty rule")
                    _reject_yaml_features(item, path=path, field=artifact)
                    items.append(item)
                    index += 1
                rules[artifact] = items
            parsed["rules"] = rules
            continue
        raise ConfigError(path, f"line {index}", "unsupported openspec config syntax")
    if parsed.get("schema") != "spec-driven":
        raise ConfigError(path, "schema", "schema: spec-driven is required")
    return parsed
