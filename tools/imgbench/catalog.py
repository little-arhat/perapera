"""OpenRouter image-model catalog — pure pricing primitives.

No I/O, no network. API-shaped payloads in, values out; the fetching lives in
``cli.py`` and the history in ``store.py``.

Adapted from the ``llm`` price watch in the options repo, which keeps two facts
apart because they come from different endpoints and answer different questions:

* the **effective price** (``GET /models``) — what it costs today, already net
  of any promotion;
* the **discount** (``GET /models/{id}/endpoints``) — how much of that price is
  promotional, i.e. how far it can snap back.

Image models need a third fact that text models do not, and it dominates the
other two:

* **fidelity** — whether the model renders the requested characters correctly.

That is not a refinement. ``gemini-2.5-flash-image`` costs 43% less than
``gemini-3.1-flash-image`` and, asked for みなみぐち, drew みなみりぢち. For a
reading drill a wrong glyph teaches a wrong letterform, so the cheaper model is
not a saving — it is a defect generator. Ranking image models on price alone
selects for exactly the wrong thing.

Fidelity cannot be read from any endpoint. It has to be measured, which is why
this tool generates rather than only fetching. See ``fidelity.py``.
"""

from __future__ import annotations

import math
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class ImageModel:
    """One image-capable model's price and promotion state. A value.

    ``quoted_image`` is dollars per generated image as OpenRouter reports it.
    ``None`` means "not quoted" and is common — the catalog frequently leaves it
    empty for image models, which is the reason `measured_image` exists at all.
    A genuinely free model would quote ``0.0``.
    """

    id: str
    quoted_image: float | None = None
    quoted_prompt: float | None = None
    discount: float = 0.0
    context: int | None = None
    delisted: bool = False

    @property
    def quoted_or_none(self) -> float | None:
        """The catalog's per-image price, if it gave one."""
        return self.quoted_image


@dataclass(frozen=True)
class Observation:
    """What one benchmark run learned about one model.

    ``measured_image`` is the metered cost of a real generation — the only
    trustworthy per-image figure, since the catalog often quotes nothing.
    ``fidelity`` is 0.0-1.0 over the probe set; ``None`` when nothing was run.
    """

    id: str
    measured_image: float | None = None
    fidelity: float | None = None
    samples: int = 0
    discount: float = 0.0
    quoted_image: float | None = None

    @property
    def usable(self) -> bool:
        """Whether this model can be trusted to render text.

        The threshold is deliberately high. A model that gets nine characters in
        ten right still produces a wrong glyph in most sentences, and the
        learner cannot tell which one is wrong.
        """
        return self.fidelity is not None and self.fidelity >= 0.95

    @property
    def cost_per_correct_image(self) -> float | None:
        """Price adjusted for how often a generation has to be thrown away.

        The honest comparator. A model at $0.039 that fails a third of the time
        costs $0.058 per usable image, before counting the wasted verification
        calls and the learner's patience.
        """
        if self.measured_image is None or not self.fidelity:
            return None
        return self.measured_image / self.fidelity


def is_image_model(payload: Mapping[str, Any]) -> bool:
    """Whether a ``/models`` entry can emit images."""
    architecture = payload.get("architecture") or {}
    return "image" in (architecture.get("output_modalities") or [])


def parse_model(payload: Mapping[str, Any]) -> ImageModel:
    """Build an ImageModel from one ``/models`` entry."""
    pricing = payload.get("pricing") or {}
    return ImageModel(
        id=str(payload.get("id", "")),
        quoted_image=_float_or_none(pricing.get("image")),
        quoted_prompt=_float_or_none(pricing.get("prompt")),
        context=_int_or_none(payload.get("context_length")),
    )


def parse_models(payload: Mapping[str, Any]) -> list[ImageModel]:
    """Every image-capable model in a ``/models`` payload, id-sorted.

    Routing aliases (``openrouter/auto``) are excluded: they are a dispatcher,
    not a model, so benchmarking one measures whatever it happened to pick.
    """
    data = payload.get("data") or []
    models = [
        parse_model(entry)
        for entry in data
        if is_image_model(entry) and not str(entry.get("id", "")).startswith("openrouter/")
    ]
    return sorted(models, key=lambda m: m.id)


def discount_from_endpoints(
    payload: Mapping[str, Any], quoted_price: float | None
) -> float:
    """Promotional share of the price, from a ``/models/{id}/endpoints`` payload.

    Read off the endpoint OpenRouter actually quotes, not the best-discounted
    one. Providers are promoted individually and the two are often different;
    reporting the deepest discount would call a stable price promotional, which
    inverts the meaning of the column. The number is snap-back risk, not thrift.

    Falls back to the cheapest endpoint when nothing matches the quote, and to
    0.0 when nothing is served.
    """
    endpoints = (payload.get("data") or {}).get("endpoints") or []
    if not endpoints:
        return 0.0

    def price_of(endpoint: Mapping[str, Any]) -> float | None:
        pricing = endpoint.get("pricing") or {}
        # Image endpoints quote per-image; text-shaped ones quote per-token.
        return _float_or_none(pricing.get("image")) or _float_or_none(
            pricing.get("prompt")
        )

    def discount_of(endpoint: Mapping[str, Any]) -> float:
        return _float_or_none((endpoint.get("pricing") or {}).get("discount")) or 0.0

    if quoted_price is not None:
        for endpoint in endpoints:
            price = price_of(endpoint)
            if price is not None and math.isclose(price, quoted_price, rel_tol=1e-9):
                return discount_of(endpoint)
    return discount_of(min(endpoints, key=lambda e: price_of(e) or float("inf")))


def rank(observations: Sequence[Observation]) -> list[Observation]:
    """Order models by what actually matters: fidelity first, then price.

    Not a blend. A weighted score would let a large price advantage outvote a
    fidelity gap, and there is no discount that makes a wrong glyph acceptable.
    Unusable models sort last regardless of price, and are kept in the list
    rather than dropped so a run records *why* they were rejected.
    """
    return sorted(
        observations,
        key=lambda o: (
            not o.usable,
            o.cost_per_correct_image
            if o.cost_per_correct_image is not None
            else float("inf"),
            o.id,
        ),
    )


def dominates(challenger: Observation, incumbent: Observation) -> bool:
    """Whether `challenger` is strictly cheaper and no less faithful.

    Deliberately narrow, and narrower than the text-model version it is adapted
    from. It fires only when BOTH models have been measured, so an unmeasured
    model never displaces a measured one on a catalog price — which here would
    be worse than useless, since the catalog price bears no relation to the bill.

    Fidelity must be no lower, never merely "close". A cheaper model that is
    fractionally less accurate is not a saving: the wrong glyph it draws teaches
    a wrong letterform, and no discount offsets that.
    """
    if challenger.id == incumbent.id:
        return False
    if challenger.measured_image is None or incumbent.measured_image is None:
        return False
    if challenger.fidelity is None or incumbent.fidelity is None:
        return False
    if not challenger.usable:
        return False
    if challenger.fidelity < incumbent.fidelity:
        return False
    return challenger.measured_image < incumbent.measured_image


def worth_measuring(
    catalog: Sequence[ImageModel],
    observed: Mapping[str, Observation],
    incumbent: Observation | None,
) -> list[ImageModel]:
    """Models that might beat the incumbent but have never been benchmarked.

    Not a suggestion — a shortlist of things worth spending a probe on. The
    catalog cannot say whether they are cheaper (its prices are unrelated to the
    bill) or whether they can draw kana at all, so the only honest output is
    "unknown, and cheap to find out".
    """
    return [
        model
        for model in catalog
        if model.id not in observed
        and (incumbent is None or model.id != incumbent.id)
    ]


def price_moves(
    history: Sequence[Mapping[str, Any]],
    threshold: float = 0.02,
    field: str = "measured_image",
) -> list[tuple[str, float, float, str]]:
    """Models whose price moved between their last two observations of `field`.

    Returns (id, was, now, date_of_earlier).

    Defaults to the measured price, which is the one that matched a bill. Passing
    ``quoted_image`` watches the catalog instead: cheaper by far, since it needs
    no generation, and the only way to notice a rise *before* paying it.
    """
    by_model: dict[str, list[Mapping[str, Any]]] = {}
    for record in history:
        model_id = record.get("id")
        if model_id:
            by_model.setdefault(str(model_id), []).append(record)

    moves: list[tuple[str, float, float, str]] = []
    for model_id, records in by_model.items():
        ordered = sorted(records, key=lambda r: str(r.get("date", "")))
        if len(ordered) < 2:
            continue
        was = ordered[-2].get(field)
        now = ordered[-1].get(field)
        if not was or not now:
            continue
        if abs(now - was) / was > threshold:
            moves.append((model_id, float(was), float(now), str(ordered[-2].get("date", ""))))
    return sorted(moves, key=lambda m: (m[2] - m[1]) / m[1])


def _float_or_none(value: Any) -> float | None:
    """Parse a price. Absent and unparseable both mean unknown, never zero."""
    if value is None or value == "":
        return None
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return None
    # OpenRouter uses -1 for "variable" on routing aliases.
    return None if parsed < 0 else parsed


def _int_or_none(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None
