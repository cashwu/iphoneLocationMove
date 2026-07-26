from __future__ import annotations

import json
import os
from collections.abc import Sequence

from ..errors import CashError
from ..validation import validate_all, validate_change
from ..workspace import Workspace


def execute(arguments: Sequence[str]) -> int:
    workspace = Workspace.discover(
        os.getcwd(),
        launcher_root=os.environ.get("CASH_PROJECT_ROOT"),
    )
    workspace.assert_readable()
    json_mode = "--json" in arguments
    if "--all" in arguments:
        results = validate_all(workspace)
        findings = [
            {"change": result["name"], **finding}
            for result in results
            for finding in result["findings"]
        ]
        payload: dict[str, object] = {
            "valid": not findings,
            "changes": results,
            "findings": findings,
        }
    else:
        names = [value for value in arguments if not value.startswith("--")]
        if len(names) != 1:
            raise CashError("invalid_arguments", "validate requires a change name or --all.")
        findings = validate_change(workspace, names[0])
        payload = {
            "valid": not findings,
            "change": names[0],
            "findings": findings,
        }
    if json_mode:
        print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    elif findings:
        for item in findings:
            print(f"{item['path']}: {item['code']}: {item['message']}")
    else:
        print("Validation passed.")
    return 0 if not findings else 2
