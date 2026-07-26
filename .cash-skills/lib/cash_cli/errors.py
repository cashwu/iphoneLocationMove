from __future__ import annotations

import json
from dataclasses import dataclass


@dataclass(slots=True)
class CashError(Exception):
    code: str
    message: str
    exit_code: int = 2
    path: str | None = None

    def __post_init__(self) -> None:
        Exception.__init__(self, self.message)

    def payload(self) -> dict[str, object]:
        detail: dict[str, object] = {
            "code": self.code,
            "message": self.message,
        }
        if self.path is not None:
            detail["path"] = self.path
        return {"error": detail}

    def as_json(self) -> str:
        return json.dumps(
            self.payload(),
            ensure_ascii=False,
            separators=(",", ":"),
        )
