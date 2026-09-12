from __future__ import annotations

import datetime as dt
import json
import os
import re
import subprocess
from collections.abc import Sequence

from ..errors import CashError
from ..workspace import Workspace
from .discovery import _change_directory, _created, _tasks, dormancy_payload


_CODE_SPAN = re.compile(r"`([^`\r\n]+)`")


def _git(workspace: Workspace, *arguments: str) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", str(workspace.root), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise CashError("git_error", "Git invocation failed.", 1) from error
    return result.stdout


def _impact_paths(workspace: Workspace, change) -> list[str]:
    relative = workspace.relative(change / "proposal.md")
    if not workspace.is_file(relative):
        return []
    return sorted(
        {
            value
            for value in _CODE_SPAN.findall(workspace.read_text(relative))
            if "/" in value
        },
        key=lambda value: value.encode("utf-8"),
    )


def _has_head(workspace: Workspace) -> bool:
    try:
        result = subprocess.run(
            ["git", "-C", str(workspace.root), "rev-parse", "--verify", "HEAD"],
            check=False,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise CashError("git_error", "Git invocation failed.", 1) from error
    if result.returncode == 0:
        return True
    stderr = result.stderr or ""
    if isinstance(stderr, bytes):
        stderr = stderr.decode("utf-8", errors="replace")
    if any(
        marker in stderr
        for marker in (
            "Needed a single revision",
            "ambiguous argument 'HEAD'",
            "unknown revision",
            "bad revision 'HEAD'",
        )
    ):
        return False
    raise CashError("git_error", "Git invocation failed.", 1)


def drift_payload(
    workspace: Workspace,
    name: str,
    *,
    observation_timestamp: object | None = None,
) -> dict[str, object]:
    change = _change_directory(workspace, name)
    created = _created(workspace, change)
    has_head = _has_head(workspace)
    dormancy = dormancy_payload(
        workspace,
        change,
        created=created,
        has_head=has_head,
        observation_timestamp=observation_timestamp,
    )
    if has_head:
        last_commit_output = _git(
            workspace,
            "log",
            "-1",
            "--format=%H",
            "--",
            workspace.relative(change),
        ).strip()
        commits_text = _git(
            workspace,
            "rev-list",
            "--count",
            f"--since={created.isoformat()}",
            "HEAD",
        ).strip()
        commits_since_created = int(commits_text or "0")
    else:
        last_commit_output = ""
        commits_since_created = 0
    dirty_output = _git(
        workspace,
        "status",
        "--porcelain",
        "--untracked-files=all",
    )
    dirty_paths = {
        line[3:].split(" -> ")[-1]
        for line in dirty_output.splitlines()
        if len(line) > 3
    }
    impact_paths = _impact_paths(workspace, change)
    broken = [
        {
            "anchor": path,
            "category": "affected-code",
            "reason": "Declared impact path does not exist.",
        }
        for path in impact_paths
        if not workspace.exists(path)
    ]
    tasks = _tasks(workspace, change)
    blocked: list[dict[str, object]] = []
    for task in tasks:
        paths = sorted(
            {
                item["anchor"]
                for item in broken
                if item["anchor"] in task["description"]
            },
            key=lambda value: value.encode("utf-8"),
        )
        if paths and not task["done"]:
            blocked.append(
                {
                    "id": task["id"],
                    "description": task["description"],
                    "paths": paths,
                }
            )
    matching_dirty = sorted(
        set(impact_paths) & dirty_paths,
        key=lambda value: value.encode("utf-8"),
    )
    # Use the same UTC observation used by dormancy so injected observations
    # keep the complete drift decision deterministic.
    days_old = int(dormancy["age_days"])
    staleness_score = min(40, days_old * 2)
    anchor_score = min(40, len(broken) * 10)
    dirty_score = min(20, len(matching_dirty) * 5)
    dimensions = [
        {
            "kind": "staleness",
            "status": f"{days_old} day(s) old",
            "score": staleness_score,
            "contributes_to_total": True,
        },
        {
            "kind": "broken-anchors",
            "status": f"{len(broken)} missing path(s)",
            "score": anchor_score,
            "contributes_to_total": True,
        },
        {
            "kind": "dirty-impact",
            "status": f"{len(matching_dirty)} dirty impact path(s)",
            "score": dirty_score,
            "contributes_to_total": True,
        },
    ]
    total = sum(
        dimension["score"]
        for dimension in dimensions
        if dimension["contributes_to_total"]
    )
    if total < 30:
        severity = "light"
        action_kind = "apply"
    elif total < 60:
        severity = "medium"
        action_kind = "ingest"
    else:
        severity = "heavy"
        action_kind = "ingest"
    recommended_action = {
        "action_kind": action_kind,
        "change_name": name,
        "flags": [],
    }
    recommendation = f"cash-{action_kind} {recommended_action['change_name']}"
    return {
        "change_id": name,
        "created": created.isoformat(),
        "last_commit": last_commit_output or None,
        "commits_since_created": commits_since_created,
        "dimensions": dimensions,
        "broken_anchors": broken,
        "tasks_maybe_resolved": [],
        "tasks_blocked_external": blocked,
        "total_score": total,
        "severity": severity,
        "primary_recommendation": recommendation,
        "dormancy": dormancy,
        "recommended_action": recommended_action,
    }


def render_report(payload: dict[str, object]) -> str:
    lines = [
        f"Drift report: {payload['change_id']}",
        f"Severity: {payload['severity']}",
        f"Total score: {payload['total_score']}",
        "Dimensions:",
    ]
    lines.extend(
        f"- {item['kind']}: {item['status']} (score {item['score']})"
        for item in payload["dimensions"]
    )
    lines.append("Broken anchors:")
    lines.extend(
        (
            f"- {item['anchor']}: {item['reason']}"
            for item in payload["broken_anchors"]
        ),
    )
    if not payload["broken_anchors"]:
        lines.append("- none")
    lines.append("Task collisions:")
    lines.extend(
        (
            f"- {item['id']}: {', '.join(item['paths'])}"
            for item in payload["tasks_blocked_external"]
        ),
    )
    if not payload["tasks_blocked_external"]:
        lines.append("- none")
    dormancy = payload["dormancy"]
    lines.append(
        "Dormancy: "
        f"{dormancy['status']} ({dormancy['reason']}; "
        f"age_days={dormancy['age_days']}, idle_days={dormancy['idle_days']})"
    )
    action = payload["recommended_action"]
    lines.append(
        "Recommended action: "
        f"{action['action_kind']} {action['change_name']} "
        f"(flags={action['flags']})"
    )
    lines.append(f"Primary recommendation: {payload['primary_recommendation']}")
    return "\n".join(lines) + "\n"


def execute(arguments: Sequence[str]) -> int:
    names = [value for value in arguments if not value.startswith("--")]
    if len(names) != 1:
        raise CashError("invalid_arguments", "drift requires one change name.")
    workspace = Workspace.discover(
        os.getcwd(),
        launcher_root=os.environ.get("CASH_PROJECT_ROOT"),
    )
    workspace.assert_readable()
    payload = drift_payload(workspace, names[0])
    if "--json" in arguments:
        print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    else:
        print(render_report(payload), end="")
    return 0
