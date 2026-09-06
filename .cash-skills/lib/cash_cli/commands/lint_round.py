from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from collections.abc import Iterable, Sequence
from pathlib import Path

from ..errors import CashError
from ..workspace import Workspace


ROUND_NAME = re.compile(r"(propose|apply)-r([1-9][0-9]*)\.md\Z")
CHANGE_NAME = re.compile(r"[a-z][a-z0-9-]*\Z")
DECISIONS = {"passed", "next_round", "aborted"}
ROUND_TYPES = {"full", "micro"}
SECTIONS = ("Reviewer Findings", "Rating", "Fix Actions", "Decision")
PROTECTED_PATHS = {
    ".claude/skills/cash-propose/SKILL.md",
    ".claude/skills/cash-apply/SKILL.md",
    ".agents/skills/cash-propose/SKILL.md",
    ".agents/skills/cash-apply/SKILL.md",
    ".cash.yaml",
    "scripts/cash-skills/blocks/review-gate.md",
    "scripts/cash-skills/generate.fish",
    "scripts/cash-skills/variant-rules.yaml",
    "scripts/cash-skills/tests/skill-checks.fish",
    "scripts/cash-cli/tests/cli-checks.fish",
    "openspec/specs/",
}


def _round_files(change: Path) -> dict[str, list[tuple[int, Path]]]:
    result = {"propose": [], "apply": []}
    reviews = change / "reviews"
    if not reviews.is_dir():
        return result
    for path in reviews.iterdir():
        match = ROUND_NAME.fullmatch(path.name)
        if match and path.is_file():
            result[match.group(1)].append((int(match.group(2)), path))
    for values in result.values():
        values.sort(key=lambda item: item[0])
    return result


def _section(text: str, name: str) -> str | None:
    marker = f"## {name}"
    lines = text.splitlines()
    try:
        start = lines.index(marker) + 1
    except ValueError:
        return None
    end = next((i for i in range(start, len(lines)) if lines[i].startswith("## ")), len(lines))
    return "\n".join(lines[start:end])


def _decision(text: str) -> str | None:
    body = _section(text, "Decision")
    if body is None:
        return None
    for line in body.splitlines():
        value = line.strip().replace("`", "")
        if value:
            return value if value in DECISIONS else None
    return None


def _round_type(text: str) -> str | None:
    body = _section(text, "Rating")
    if body is None:
        return None
    matches: list[str] = []
    for line in body.splitlines():
        value = line.strip()
        if value.startswith("-"):
            value = value[1:].strip()
        value = value.replace("`", "")
        if not value.startswith("round_type"):
            continue
        separator = ":" if ":" in value else "：" if "：" in value else None
        if separator is None:
            continue
        token = value.split(separator, 1)[1].replace("`", "").strip()
        matches.append(token)
    return matches[0] if len(matches) == 1 and matches[0] in ROUND_TYPES else None


def _check(check_id: str, status: str, detail: str) -> dict[str, str]:
    return {"id": check_id, "status": status, "detail": detail}


def _structure_checks(files: dict[str, list[tuple[int, Path]]]) -> tuple[list[dict[str, str]], dict[Path, str | None]]:
    checks: list[dict[str, str]] = []
    parsed: dict[Path, str | None] = {}
    texts: dict[Path, str | None] = {}
    all_files = [path for values in files.values() for _, path in values]
    if not all_files:
        return [_check(item, "skip", "no round files") for item in ("round_file_schema", "decision_value", "round_type_position")], parsed
    schema_failures: list[str] = []
    decision_failures: list[str] = []
    for path in all_files:
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            text = None
        texts[path] = text
        if text is None:
            schema_failures.append(f"{path.name}: unable to read round file")
            decision_failures.append(path.name)
            parsed[path] = None
            continue
        missing = [f"## {name}" for name in SECTIONS if _section(text, name) is None]
        if missing:
            schema_failures.append(f"{path.name}: missing {', '.join(missing)}")
        decision = _decision(text)
        parsed[path] = decision
        if decision is None:
            decision_failures.append(path.name)
    checks.append(_check("round_file_schema", "fail" if schema_failures else "pass", "; ".join(schema_failures) or "all round files have required sections"))
    checks.append(_check("decision_value", "fail" if decision_failures else "pass", ", ".join(decision_failures) or "all decision values are valid"))
    position_failures: list[str] = []
    for skill, values in files.items():
        if not values:
            continue
        numbers = [number for number, _ in values]
        if numbers[0] != 1:
            position_failures.append(f"{skill}: missing r1")
            continue
        expected_number = 1
        run_position = 0
        previous_decision: str | None = None
        for number, path in values:
            if number != expected_number:
                position_failures.append(f"{path.name}: missing r{expected_number}")
                expected_number = number
            if previous_decision in DECISIONS - {"next_round"}:
                run_position = 1
            elif run_position == 0:
                run_position = 1
            else:
                run_position += 1
            expected = "full" if run_position == 1 or run_position == 4 else "micro"
            actual = _round_type(texts.get(path) or "")
            if actual is None or actual != expected:
                position_failures.append(f"{path.name}: expected {expected}, got {actual or 'unparseable'}")
            previous_decision = parsed.get(path)
            if previous_decision is None and number != numbers[-1]:
                position_failures.append(f"{path.name}: decision prevents run boundary derivation")
            expected_number = number + 1
    checks.append(_check("round_type_position", "fail" if position_failures else "pass", "; ".join(position_failures) or "round types match derived positions"))
    return checks, parsed


def _git_changed(workspace: Workspace) -> set[str]:
    try:
        result = subprocess.run(
            ["git", "-C", str(workspace.root), "status", "--porcelain=v1", "-z", "--untracked-files=all"],
            check=True,
            capture_output=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise CashError("git_error", "Git invocation failed.", 1) from error
    changed: set[str] = set()
    records = result.stdout.decode("utf-8").split("\0")
    index = 0
    while index < len(records):
        item = records[index]
        if not item:
            index += 1
            continue
        status = item[:2]
        changed.add(item[3:] if len(item) >= 3 else item)
        if "R" in status or "C" in status:
            index += 1
            if index < len(records) and records[index]:
                changed.add(records[index])
        index += 1
    return changed


def _declared_paths(change: Path) -> set[str]:
    def declared_path_tokens(text: str) -> set[str]:
        text = re.split(r"\bVerification\s*:", text, maxsplit=1, flags=re.IGNORECASE)[0]
        values = set(re.findall(r"`([^`]+)`", text))
        plain = re.sub(r"`[^`]+`", "", text)
        values.update(re.findall(r"(?<![\w./-])(?:\.?[A-Za-z0-9_-][A-Za-z0-9_.-]*(?:/[A-Za-z0-9_.-]+)*/?)(?![\w./-])", plain))
        return {
            value.rstrip("/")
            for value in values
            if value and value != "(none)" and ("/" in value or "." in value or value.startswith("."))
        }

    def explicit_scope_paths(text: str) -> set[str]:
        text = text.strip()
        label = re.match(r"^(?:New|Modified|Removed)\s*[:：]\s*(.*)$", text, re.IGNORECASE)
        if label:
            text = label.group(1).strip()
        elif re.match(r"^[A-Za-z][A-Za-z0-9 _-]*\s*:", text):
            return set()
        if not text or text == "(none)":
            return set()
        values: set[str] = set()
        for part in text.split(","):
            value = part.strip().strip("`")
            if not value or value == "(none)" or re.search(r"\s", value):
                return set()
            if not re.fullmatch(r"(?:\.?[A-Za-z0-9_-][A-Za-z0-9_.-]*(?:/[A-Za-z0-9_.-]+)*/?)", value):
                return set()
            values.add(value.rstrip("/"))
        return values

    paths: set[str] = set()
    proposal = change / "proposal.md"
    if proposal.is_file():
        lines = proposal.read_text(encoding="utf-8").splitlines()
        in_impact = False
        in_affected = False
        affected_indent = 0
        verification_indent: int | None = None
        example_indent: int | None = None
        ignored_scope_indent: int | None = None
        fenced = False
        for line in lines:
            if re.match(r"^\s*(```|~~~)", line):
                fenced = not fenced
                continue
            if fenced:
                continue
            indent = len(line) - len(line.lstrip(" "))
            if line == "## Impact":
                in_impact = True
                continue
            if in_impact and line.startswith("## "):
                break
            if example_indent is not None:
                if line.strip() and indent <= example_indent:
                    example_indent = None
                else:
                    continue
            if verification_indent is not None:
                if line.strip() and indent <= verification_indent:
                    verification_indent = None
                else:
                    continue
            if ignored_scope_indent is not None:
                if line.strip() and indent <= ignored_scope_indent:
                    ignored_scope_indent = None
                else:
                    continue
            if in_impact and re.match(r"^\s*[-*]\s+Verification\s*:", line, re.IGNORECASE):
                verification_indent = indent
                continue
            if in_impact and re.match(r"^\s*[-*]\s+Example\s*:", line, re.IGNORECASE):
                example_indent = indent
                continue
            if in_impact and re.match(r"^\s*[-*]\s+Affected code\s*:", line, re.IGNORECASE):
                in_affected = True
                affected_indent = indent
                paths.update(explicit_scope_paths(re.split(r"Affected code\s*:", line, maxsplit=1, flags=re.IGNORECASE)[1]))
                continue
            if in_affected and line.strip() and indent <= affected_indent:
                in_affected = False
            if in_affected:
                stripped = line.strip()
                if not stripped.startswith(("-", "*")) or re.match(r"[-*]\s+(?:Verification|Example)\s*:", stripped, re.IGNORECASE):
                    continue
                body = re.sub(r"^[-*]\s+", "", stripped)
                if re.match(r"^(?:New|Modified|Removed)\s*[:：]", body, re.IGNORECASE):
                    paths.update(explicit_scope_paths(body))
                    continue
                candidate_paths = explicit_scope_paths(body)
                if not candidate_paths:
                    ignored_scope_indent = indent
                    continue
                paths.update(candidate_paths)
    tasks = change / "tasks.md"
    if tasks.is_file():
        fenced = False
        for line in tasks.read_text(encoding="utf-8").splitlines():
            if re.match(r"^\s*(```|~~~)", line):
                fenced = not fenced
                continue
            task_match = re.match(r"^\s*-\s+(?:\[[ xX]\]\s*|\d+(?:\.\d+)*\s+)(.*)$", line)
            if fenced or task_match is None:
                continue
            delivery = re.search(r"(?:^|[;；]|\s)delivery\s*:", task_match.group(1), re.IGNORECASE)
            if delivery is None:
                continue
            value = task_match.group(1)[delivery.end():]
            value = re.split(r"[;；]", value, maxsplit=1)[0]
            paths.update(part.strip().strip("`") for part in value.split(",") if part.strip())
    return {path.rstrip("/") for path in paths if path and path != "(none)"}


def _enumerate_changes(workspace: Workspace) -> list[tuple[str, Path, bool]]:
    result: list[tuple[str, Path, bool]] = []
    for entry in workspace.changes.iterdir() if workspace.changes.is_dir() else ():
        if entry.name in {"archive", ".parked"} or not entry.is_dir() or not CHANGE_NAME.fullmatch(entry.name):
            continue
        result.append((entry.name, entry, False))
    if workspace.parked.is_dir():
        for entry in workspace.parked.iterdir():
            if entry.is_dir() and CHANGE_NAME.fullmatch(entry.name):
                result.append((entry.name, entry, True))
    return result


def _active(files: dict[str, list[tuple[int, Path]]], parsed: dict[Path, str | None]) -> bool:
    for values in files.values():
        if values:
            _, path = values[-1]
            if parsed.get(path) == "next_round":
                return True
    return False


def _grader_check(workspace: Workspace, *, active: bool, declarations: set[str]) -> dict[str, str]:
    if not active:
        return _check("grader_immutability", "skip", "review loop is not active")
    changed = _git_changed(workspace)
    violations: list[str] = []
    for path in changed:
        protected = path in PROTECTED_PATHS or path.startswith("openspec/specs/")
        if protected and not any(path == declared or path.startswith(declared.rstrip("/") + "/") for declared in declarations):
            violations.append(path)
    return _check("grader_immutability", "fail" if violations else "pass", ", ".join(sorted(violations)) or "protected changes are covered")


def _payload(change: str, checks: Iterable[dict[str, str]]) -> dict[str, object]:
    values = list(checks)
    return {"ok": not any(item["status"] == "fail" for item in values), "change": change, "checks": values}


def execute(arguments: Sequence[str]) -> int:
    json_mode = "--json" in arguments
    hook = "--hook" in arguments
    positional = [value for value in arguments if not value.startswith("--")]
    if hook and positional:
        raise CashError("invalid_arguments", "lint-round --hook does not accept a change name.")
    if not hook and len(positional) != 1:
        raise CashError("invalid_arguments", "lint-round requires a change name or --hook.")
    if any(value.startswith("-") and value not in {"--hook", "--json"} for value in arguments):
        raise CashError("invalid_arguments", "Unknown lint-round option.")
    try:
        workspace = Workspace.discover(os.getcwd(), launcher_root=os.environ.get("CASH_PROJECT_ROOT"))
        enumerated = _enumerate_changes(workspace)
        targets = enumerated if hook else []
        if not hook:
            name = positional[0]
            if not CHANGE_NAME.fullmatch(name):
                raise CashError("change_not_found", f"Change not found: {name}", 2)
            matching = [item for item in enumerated if item[0] == name and not item[2]]
            if not matching:
                raise CashError("change_not_found", f"Change not found: {name}", 2)
            targets = matching
        all_declarations = set()
        for name, path, parked in enumerated:
            if not parked:
                all_declarations.update(_declared_paths(path))
        results: list[dict[str, object]] = []
        for name, path, parked in targets:
            files = _round_files(path)
            checks, parsed = _structure_checks(files)
            checks.append(_grader_check(workspace, active=(not parked and _active(files, parsed)), declarations=all_declarations))
            if hook:
                results.append({"change": name, "checks": checks, "ok": not any(item["status"] == "fail" for item in checks)})
            else:
                results = [_payload(name, checks)]
        if hook:
            ok = all(bool(item["ok"]) for item in results)
            flat = [{"change": item["change"], **check} for item in results for check in item["checks"]]
            output: dict[str, object] = {"ok": ok, "checks": flat}
            stop_hook_active = False
            if sys.stdin is not None:
                raw = sys.stdin.read()
                if raw.strip():
                    try:
                        stop_hook_active = bool(json.loads(raw).get("stop_hook_active", False))
                    except (json.JSONDecodeError, AttributeError, TypeError) as error:
                        raise RuntimeError(f"invalid hook input: {error}") from error
            if not ok:
                failed = [
                    f"{item['change']}:{item['id']}: {item['detail']}"
                    for item in flat
                    if item["status"] == "fail"
                ]
                print("; ".join(failed), file=sys.stderr)
            if json_mode:
                print(json.dumps(output, ensure_ascii=False, separators=(",", ":")))
            elif not ok:
                pass
            if not ok:
                return 1 if stop_hook_active else 2
            return 0
        output = results[0]
        if json_mode:
            print(json.dumps(output, ensure_ascii=False, separators=(",", ":")))
        else:
            for check in output["checks"]:
                print(f"{check['id']}: {check['status']} — {check['detail']}")
        return 0 if output["ok"] else 2
    except CashError as error:
        if hook:
            print(f"gate_unavailable: error[{error.code}]: {error.message}", file=sys.stderr)
            return 1
        raise
    except Exception as error:
        if hook:
            print(f"gate_unavailable: {error}", file=sys.stderr)
            return 1
        raise CashError("execution_error", str(error), 1) from error
