from __future__ import annotations

import json
import os
import re
from collections.abc import Sequence

from ..errors import CashError
from ..validation import validate_change
from ..workspace import Workspace
from .discovery import _artifact_done, _change_directory, _tasks


_REQUIREMENT = re.compile(r"### Requirement: (.+)")
_SCENARIO = re.compile(r"#### Scenario: (.+)")
_CODE_SPAN = re.compile(r"`([^`\r\n]+)`")


def _spec_text(workspace: Workspace, change) -> str:
    relative = workspace.relative(change / "specs")
    return "\n".join(
        workspace.read_text(path)
        for path in workspace.spec_files(relative)
    )


def analyze_payload(workspace: Workspace, name: str) -> dict[str, object]:
    change = _change_directory(workspace, name)
    available = [
        artifact_id
        for artifact_id in ("proposal", "design", "specs", "tasks")
        if _artifact_done(workspace, change, artifact_id)
    ]
    missing = [
        artifact_id
        for artifact_id in ("proposal", "design", "specs", "tasks")
        if artifact_id not in available
    ]
    findings: list[dict[str, object]] = []
    dimension_findings: dict[str, list[dict[str, object]]] = {
        "Coverage": [],
        "Consistency": [],
        "Ambiguity": [],
        "Gaps": [],
    }

    if {"specs", "tasks"}.issubset(available):
        specs = _spec_text(workspace, change)
        task_text = workspace.read_text(workspace.relative(change / "tasks.md"))
        for title in _REQUIREMENT.findall(specs):
            if title not in task_text:
                dimension_findings["Coverage"].append(
                    {
                        "dimension": "Coverage",
                        "severity": "Warning",
                        "location": "tasks.md",
                        "summary": f"Requirement '{title}' has no matching task",
                        "recommendation": f"Add a task that references '{title}'",
                    }
                )

    if len(available) == 4:
        for validation in validate_change(workspace, name):
            dimension_findings["Consistency"].append(
                {
                    "dimension": "Consistency",
                    "severity": "Critical",
                    "location": validation["path"],
                    "summary": validation["message"],
                    "recommendation": f"Resolve validation finding {validation['code']}",
                }
            )

    if "specs" in available:
        specs = _spec_text(workspace, change)
        lines = specs.splitlines()
        scenarios = [
            (index, match.group(1))
            for index, line in enumerate(lines)
            if (match := _SCENARIO.fullmatch(line)) is not None
        ]
        for position, (start, scenario) in enumerate(scenarios):
            end = scenarios[position + 1][0] if position + 1 < len(scenarios) else len(lines)
            if not any(line.startswith("##### Example:") for line in lines[start + 1 : end]):
                dimension_findings["Ambiguity"].append(
                    {
                        "dimension": "Ambiguity",
                        "severity": "Suggestion",
                        "location": "specs",
                        "summary": f"Scenario '{scenario}' has no concrete examples",
                        "recommendation": "Add ##### Example: with concrete GIVEN/WHEN/THEN data",
                    }
                )
        for number, line in enumerate(lines, start=1):
            if re.search(r"\b(?:may|should)\b", line):
                dimension_findings["Ambiguity"].append(
                    {
                        "dimension": "Ambiguity",
                        "severity": "Suggestion",
                        "location": f"specs:{number}",
                        "summary": "Vague lowercase normative language found",
                        "recommendation": "Use SHALL/SHALL NOT for normative behavior",
                    }
                )

    if {"proposal", "tasks"}.issubset(available):
        proposal = workspace.read_text(workspace.relative(change / "proposal.md"))
        task_text = workspace.read_text(workspace.relative(change / "tasks.md"))
        for path in (value for value in _CODE_SPAN.findall(proposal) if "/" in value):
            if path not in task_text:
                dimension_findings["Gaps"].append(
                    {
                        "dimension": "Gaps",
                        "severity": "Warning",
                        "location": "proposal.md",
                        "summary": f"Impact path has no task coverage: {path}",
                        "recommendation": f"Reference {path} from a concrete task",
                    }
                )

    dimensions: list[dict[str, object]] = []
    requirements = {
        "Coverage": {"specs", "tasks"},
        "Consistency": {"proposal", "design", "specs", "tasks"},
        "Ambiguity": {"specs"},
        "Gaps": {"proposal", "tasks"},
    }
    finding_id = 0
    for dimension in ("Coverage", "Consistency", "Ambiguity", "Gaps"):
        current = dimension_findings[dimension]
        if not requirements[dimension].issubset(available):
            status = "Skipped (insufficient artifacts)"
        elif current:
            status = f"{len(current)} issue(s) found"
        else:
            status = "Clean"
        dimensions.append(
            {
                "dimension": dimension,
                "status": status,
                "finding_count": len(current),
            }
        )
        for item in current:
            finding_id += 1
            findings.append({"id": f"F-{finding_id}", **item})
    return {
        "change_id": name,
        "dimensions": dimensions,
        "findings": findings,
        "artifacts_analyzed": available,
        "artifacts_missing": missing,
    }


def execute(arguments: Sequence[str]) -> int:
    names = [value for value in arguments if not value.startswith("--")]
    if len(names) != 1:
        raise CashError("invalid_arguments", "analyze requires one change name.")
    workspace = Workspace.discover(
        os.getcwd(),
        launcher_root=os.environ.get("CASH_PROJECT_ROOT"),
    )
    workspace.assert_readable()
    payload = analyze_payload(workspace, names[0])
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    return 0
