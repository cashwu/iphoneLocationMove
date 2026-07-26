from __future__ import annotations

import os
from collections.abc import Sequence

from ..errors import CashError
from ..workspace import Workspace


def _move_change(
    workspace: Workspace,
    name: str,
    *,
    to_parked: bool,
) -> None:
    active = workspace.change_path(name)
    parked = workspace.change_path(name, parked=True)
    source = active if to_parked else parked
    destination = parked if to_parked else active
    source_relative = workspace.relative(source)
    destination_relative = workspace.relative(destination)
    if not workspace.is_dir(source_relative):
        location = "active" if to_parked else "parked"
        raise CashError("change_not_found", f"{location.capitalize()} change not found: {name}")
    if workspace.exists(destination_relative):
        raise CashError("change_identity_collision", f"Destination identity exists: {name}")
    destination_parent = os.path.dirname(destination_relative)
    if destination_parent:
        workspace.ensure_directory(destination_parent)
    transaction = workspace.transaction()
    transaction.move(source_relative, destination_relative)
    transaction.commit()


def park_change(workspace: Workspace, name: str) -> None:
    _move_change(workspace, name, to_parked=True)


def unpark_change(workspace: Workspace, name: str) -> None:
    _move_change(workspace, name, to_parked=False)


def execute(command: str, arguments: Sequence[str]) -> int:
    if len(arguments) != 1:
        raise CashError("invalid_arguments", f"{command} requires one change name.")
    workspace = Workspace.discover(
        os.getcwd(),
        launcher_root=os.environ.get("CASH_PROJECT_ROOT"),
    )
    workspace.recover()
    if command == "park":
        park_change(workspace, arguments[0])
    else:
        unpark_change(workspace, arguments[0])
    return 0
