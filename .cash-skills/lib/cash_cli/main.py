from __future__ import annotations

import json
import sys
from collections.abc import Callable, Sequence

from .errors import CashError


Handler = Callable[[Sequence[str]], int]


def emit_json(value: dict[str, object]) -> None:
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))


def _not_implemented(arguments: Sequence[str]) -> int:
    del arguments
    raise CashError(
        "command_not_implemented",
        "This Cash CLI command is not implemented yet.",
    )


def _discovery(command: str, arguments: Sequence[str]) -> int:
    from .commands import execute

    return execute(command, arguments)


def _list(arguments: Sequence[str]) -> int:
    return _discovery("list", arguments)


def _status(arguments: Sequence[str]) -> int:
    return _discovery("status", arguments)


def _instructions(arguments: Sequence[str]) -> int:
    return _discovery("instructions", arguments)


def _execute_command(command: str, arguments: Sequence[str]) -> int:
    from .commands import execute

    return execute(command, arguments)


def _new(arguments: Sequence[str]) -> int:
    return _execute_command("new", arguments)


def _task(arguments: Sequence[str]) -> int:
    return _execute_command("task", arguments)


def _in_progress(arguments: Sequence[str]) -> int:
    return _execute_command("in-progress", arguments)


def _touched(arguments: Sequence[str]) -> int:
    return _execute_command("touched", arguments)


def _park(arguments: Sequence[str]) -> int:
    return _execute_command("park", arguments)


def _unpark(arguments: Sequence[str]) -> int:
    return _execute_command("unpark", arguments)


def _validate(arguments: Sequence[str]) -> int:
    return _execute_command("validate", arguments)


def _analyze(arguments: Sequence[str]) -> int:
    return _execute_command("analyze", arguments)


def _drift(arguments: Sequence[str]) -> int:
    return _execute_command("drift", arguments)


def _search(arguments: Sequence[str]) -> int:
    return _execute_command("search", arguments)


def _sync(arguments: Sequence[str]) -> int:
    return _execute_command("sync", arguments)


def _archive(arguments: Sequence[str]) -> int:
    return _execute_command("archive", arguments)


COMMANDS: dict[str, Handler] = {
    "list": _list,
    "status": _status,
    "instructions": _instructions,
    "new": _new,
    "task": _task,
    "in-progress": _in_progress,
    "touched": _touched,
    "park": _park,
    "unpark": _unpark,
    "validate": _validate,
    "analyze": _analyze,
    "drift": _drift,
    "archive": _archive,
    "sync": _sync,
    "search": _search,
}


def emit_help(*, json_mode: bool) -> None:
    commands = sorted(COMMANDS)
    if json_mode:
        emit_json({"commands": commands})
        return
    print("Cash commands:")
    for command in commands:
        print(f"  {command}")


def dispatch(
    arguments: Sequence[str],
    *,
    execute: bool = True,
) -> Handler | int:
    if not arguments:
        raise CashError(
            "missing_command",
            "A command is required. Run --help for available commands.",
        )

    command = arguments[0]
    handler = COMMANDS.get(command)
    if handler is None:
        raise CashError(
            "unknown_command",
            f"Unknown command: {command}. Run --help for available commands.",
        )
    if not execute:
        return handler
    return handler(arguments[1:])


def main(arguments: Sequence[str] | None = None) -> int:
    actual_arguments = list(sys.argv[1:] if arguments is None else arguments)
    json_mode = "--json" in actual_arguments
    try:
        if actual_arguments and actual_arguments[0] in {"--help", "-h"}:
            emit_help(json_mode=json_mode)
            return 0
        return int(dispatch(actual_arguments))
    except CashError as error:
        if json_mode:
            print(error.as_json())
        else:
            print(f"error[{error.code}]: {error.message}", file=sys.stderr)
        return error.exit_code
    except (OSError, UnicodeError) as error:
        execution_error = CashError(
            "execution_error",
            str(error),
            exit_code=1,
        )
        if json_mode:
            print(execution_error.as_json())
        else:
            print(
                f"error[{execution_error.code}]: {execution_error.message}",
                file=sys.stderr,
            )
        return execution_error.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
