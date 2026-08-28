"""Append-only log of what image models cost and how well they render.

An event log, not a snapshot. A model earns a line when it is actually measured;
runs are occasional and each costs real money, so every line is a fact worth
keeping and nothing is repetition.

Only observed values are persisted — id, measured cost, fidelity, discount,
quoted price. Rankings and verdicts are derived at read time, so the log stays a
record of measurements rather than of opinions about them. If the usable
threshold changes later, old runs re-rank correctly instead of carrying a stale
judgement.

One JSON object per line in ``tools/imgbench/history.jsonl``.
"""

from __future__ import annotations

import json
from collections.abc import Iterable
from pathlib import Path
from typing import Any, Protocol


class Observed(Protocol):
    """What the store needs of an observation.

    Structural rather than an import: these are flat scripts, and importing
    ``catalog`` here would only resolve once ``cli`` has fixed ``sys.path``.
    """

    id: str

PERSISTED: tuple[str, ...] = (
    "measured_image",
    "fidelity",
    "samples",
    "discount",
    "quoted_image",
)


def history_path(root: Path) -> Path:
    return root / "history.jsonl"


def record(observation: Observed, day: str) -> dict:
    """Project an Observation to a persisted record."""
    out: dict[str, Any] = {"date": day, "id": observation.id}
    for field_name in PERSISTED:
        out[field_name] = getattr(observation, field_name)
    return out


def append(path: Path, records: Iterable[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        for entry in records:
            handle.write(json.dumps(entry, ensure_ascii=False) + "\n")


def read(path: Path) -> list[dict]:
    """Every record. Malformed lines are skipped, not fatal — a half-written
    line from an interrupted run must not blind the whole log."""
    if not path.exists():
        return []
    out: list[dict] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


def latest_by_model(records: list[dict]) -> dict[str, dict]:
    """The most recent record for each model, by date then file order."""
    latest: dict[str, dict] = {}
    for entry in records:
        model = entry.get("id")
        if not model:
            continue
        previous = latest.get(model)
        if previous is None or entry.get("date", "") >= previous.get("date", ""):
            latest[model] = entry
    return latest


def movement(records: list[dict], model: str) -> tuple[dict | None, dict | None]:
    """The two most recent observations of one model, oldest first.

    ``(None, None)`` when never measured, ``(None, latest)`` when measured once.
    Prices move and models are re-tuned; a benchmark is only useful if you can
    see the change.
    """
    history = [r for r in records if r.get("id") == model]
    history.sort(key=lambda r: r.get("date", ""))
    if not history:
        return None, None
    if len(history) == 1:
        return None, history[0]
    return history[-2], history[-1]
