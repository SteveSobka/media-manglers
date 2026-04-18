"""Machine-readable CLI request/result contracts for Media Manglers helpers."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
import json
from pathlib import Path
from typing import Any


JsonObject = dict[str, Any]


@dataclass(slots=True)
class CommandEnvelope:
    payload: JsonObject = field(default_factory=dict)

    def to_dict(self) -> JsonObject:
        return asdict(self)


@dataclass(slots=True)
class CommandResult:
    ok: bool
    data: JsonObject = field(default_factory=dict)
    error: str = ""

    def to_dict(self) -> JsonObject:
        return asdict(self)


def read_json_file(path: str | Path) -> JsonObject:
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def write_json_file(path: str | Path, payload: JsonObject) -> None:
    Path(path).write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
