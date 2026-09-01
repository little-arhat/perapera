#!/usr/bin/env python3
"""imgbench — which image model can actually draw Japanese, and what it costs.

    imgbench list              # image-capable models, catalog price, discount
    imgbench run               # benchmark the shortlist (costs money)
    imgbench run --models a,b  # benchmark specific models
    imgbench report            # last measurements, ranked, with movement
    imgbench suggest           # cheaper swaps, price moves, what to measure

The effectful shell. Fetching, generating, verifying and rendering live here;
the pricing values are in ``catalog.py``, the probe set and scoring in
``fidelity.py``, the history in ``store.py``.

Why this exists as its own tool rather than a flag on the app: choosing an image
model is an occasional, deliberate, paid decision. Folding it into the app would
either run benchmarks nobody asked for or bury the numbers where nobody looks.

Requires OPENROUTER_FLUENT (environment or .env at the repo root)
for `run`; `list` and `report` need no key.
"""

from __future__ import annotations

import argparse
import base64
import contextlib
import datetime as dt
import json
import os
import pathlib
import re
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import store
from catalog import (
    ImageModel,
    Observation,
    discount_from_endpoints,
    dominates,
    parse_models,
    price_moves,
    rank,
    worth_measuring,
)
from fidelity import PROBES, ModelResult, ProbeResult, missing, score_transcription

ROOT = pathlib.Path(__file__).resolve().parent
BASE = "https://openrouter.ai/api/v1"

# The model that reads generated images back. Chosen because it transcribed
# vertical brush calligraphy and dakuten that macOS Vision dropped, at $0.0006
# per image — see docs/research/script-recognition.md.
VERIFIER = "google/gemini-2.5-flash"

# The key's name. Fluent-specific rather than shared with other projects, so
# revoking one does not break the others.
ENV_KEY = "OPENROUTER_FLUENT"

# Benchmarking every image model would cost ~$3 a run to learn nothing about
# most of them. These are the ones plausibly worth using.
SHORTLIST = (
    "google/gemini-3.1-flash-image",
    "google/gemini-3-pro-image",
    "google/gemini-2.5-flash-image",
)

# What the app generates with today. `suggest` compares against this.
IN_USE = "google/gemini-3.1-flash-image"


# ─── Credentials ─────────────────────────────────────────────


def api_key() -> str:
    """The OpenRouter key: `OPENROUTER_FLUENT`.

    Looked up in the environment first, then in a `.env` file at the repo root.
    The file is the normal case — cron and GUI contexts never source a login
    shell, so relying on the environment alone is the difference between working
    and a confusing auth error.

    `.env` is gitignored. Never print or log the value.
    """
    key = os.environ.get(ENV_KEY)
    if key:
        return key
    for candidate in (ROOT.parent.parent / ".env", pathlib.Path.cwd() / ".env"):
        if not candidate.exists():
            continue
        for line in candidate.read_text(encoding="utf-8").splitlines():
            match = re.match(rf"\s*(?:export\s+)?{ENV_KEY}\s*=\s*(.+)", line)
            if match:
                return match.group(1).strip().strip('"').strip("'")
    sys.exit(
        f"{ENV_KEY} is not set.\n"
        f"Add it to {ROOT.parent.parent / '.env'} as {ENV_KEY}=sk-or-...\n"
        "or export it in the environment."
    )


# ─── Network ─────────────────────────────────────────────────


def get_json(url: str, key: str | None = None) -> dict:
    headers = {"Authorization": f"Bearer {key}"} if key else {}
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def post_chat(payload: dict, key: str, timeout: int = 300) -> dict:
    request = urllib.request.Request(
        f"{BASE}/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def generate(model: str, prompt: str, key: str) -> tuple[bytes | None, float | None, str]:
    """One image. Returns (png bytes, metered cost, note)."""
    try:
        body = post_chat(
            {
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "modalities": ["image", "text"],
                "usage": {"include": True},
            },
            key,
        )
    except urllib.error.HTTPError as error:
        return None, None, f"HTTP {error.code}: {error.read().decode()[:160]}"

    message = body["choices"][0]["message"]
    cost = (body.get("usage") or {}).get("cost")
    cost = float(cost) if cost is not None else None
    images = message.get("images") or []
    if not images:
        return None, cost, "no image returned"
    data = images[0]["image_url"]["url"].split(",", 1)[1]
    return base64.b64decode(data), cost, ""


def transcribe(png: bytes, key: str) -> tuple[str, float | None]:
    """Read the image back. The only trustworthy check on what was drawn."""
    encoded = base64.b64encode(png).decode()
    try:
        body = post_chat(
            {
                "model": VERIFIER,
                "usage": {"include": True},
                "messages": [
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text",
                                "text": (
                                    "Transcribe every piece of Japanese text on the "
                                    "main sign, poster or menu in this image, exactly "
                                    "as written, one line per line of text. Include "
                                    "vertical text. Output only the transcriptions."
                                ),
                            },
                            {
                                "type": "image_url",
                                "image_url": {"url": f"data:image/png;base64,{encoded}"},
                            },
                        ],
                    }
                ],
            },
            key,
        )
    except urllib.error.HTTPError as error:
        return f"<verifier failed: HTTP {error.code}>", None
    cost = (body.get("usage") or {}).get("cost")
    return body["choices"][0]["message"]["content"].strip(), (
        float(cost) if cost is not None else None
    )


# ─── Commands ────────────────────────────────────────────────


def cmd_list(args: argparse.Namespace) -> int:
    """Image-capable models with catalog price and promotion state."""
    models = parse_models(get_json(f"{BASE}/models"))
    if not models:
        print("no image-capable models found")
        return 1

    key = None
    if args.discounts:
        key = api_key()
        with ThreadPoolExecutor(max_workers=8) as pool:
            payloads = list(
                pool.map(
                    lambda m: _endpoints_safe(m.id, key),
                    models,
                )
            )
        models = [
            ImageModel(
                id=m.id,
                quoted_image=m.quoted_image,
                quoted_prompt=m.quoted_prompt,
                discount=discount_from_endpoints(p, m.quoted_image or m.quoted_prompt),
                context=m.context,
            )
            # strict: a payload per model, or the discounts would silently
            # attach to the wrong rows.
            for m, p in zip(models, payloads, strict=True)
        ]

    history = store.latest_by_model(store.read(store.history_path(ROOT)))

    print(f"{'model':<44} {'quoted':>12} {'disc':>6} {'measured':>10} {'fidelity':>9}")
    print("-" * 86)
    for model in models:
        seen = history.get(model.id, {})
        # Rendered at full precision on purpose. The catalog quotes
        # $0.0000003 for a model that bills $0.0387 — a 130,000x gap. Rounding
        # that to $0.0000 would hide the discrepancy that justifies this tool.
        quoted = f"${model.quoted_image:.7f}" if model.quoted_image else "—"
        discount = f"{model.discount:.0%}" if model.discount else "—"
        measured = seen.get("measured_image")
        fidelity = seen.get("fidelity")
        print(
            f"{model.id:<44} {quoted:>12} {discount:>6} "
            f"{f'${measured:.4f}' if measured else '—':>10} "
            f"{f'{fidelity:.0%}' if fidelity is not None else '—':>9}"
        )
    print(
        "\nquoted is unreliable for image models: often blank, and when present it\n"
        "is a per-token figure that bears no relation to the per-image bill.\n"
        "measured/fidelity come from `imgbench run` and are the only real numbers."
    )
    return 0


def _endpoints_safe(model_id: str, key: str) -> dict:
    # A model can be listed but not served, which is a 404 rather than an error
    # worth stopping for: no endpoints simply means no discount to report.
    with contextlib.suppress(urllib.error.HTTPError):
        return get_json(f"{BASE}/models/{model_id}/endpoints", key)
    return {}


def cmd_run(args: argparse.Namespace) -> int:
    """Generate the probe set against each model and score what comes back."""
    key = api_key()
    models = args.models.split(",") if args.models else list(SHORTLIST)
    probes = [p for p in PROBES if not args.probe or p.name == args.probe]
    if not probes:
        print(f"no probe named {args.probe!r}")
        return 1

    estimate = len(models) * len(probes) * 0.069
    print(f"{len(models)} model(s) x {len(probes)} probe(s) — roughly ${estimate:.2f}")
    if not args.yes and input("proceed? [y/N] ").strip().lower() not in ("y", "yes"):
        print("nothing spent")
        return 0

    out_dir = ROOT / "samples"
    out_dir.mkdir(parents=True, exist_ok=True)
    day = dt.date.today().isoformat()
    results: list[ModelResult] = []

    for model in models:
        print(f"\n{model}")
        model_result = ModelResult(model=model)
        for probe in probes:
            png, gen_cost, note = generate(model, probe.prompt, key)
            if png is None:
                print(f"  {probe.name:<26} FAILED — {note}")
                model_result.results.append(
                    ProbeResult(probe.name, probe.targets, (), 0.0, gen_cost, note)
                )
                continue

            slug = model.split("/")[-1]
            (out_dir / f"{day}_{slug}_{probe.name}.png").write_bytes(png)

            text, verify_cost = transcribe(png, key)
            score = score_transcription(probe.targets, text)
            gone = missing(probe.targets, text)
            total = (gen_cost or 0) + (verify_cost or 0)
            model_result.results.append(
                ProbeResult(
                    probe.name,
                    probe.targets,
                    tuple(text.splitlines()),
                    score,
                    total,
                    "missing: " + " ".join(gone) if gone else "",
                )
            )
            mark = "ok " if score == 1.0 else "MISS"
            detail = f"  missing {' '.join(gone)}" if gone else ""
            print(f"  {probe.name:<26} {mark} {score:.0%}  ${total:.4f}{detail}")
        results.append(model_result)

    observations = [
        Observation(
            id=r.model,
            measured_image=(r.cost / len(r.results)) if r.results else None,
            fidelity=r.fidelity,
            samples=len(r.results),
        )
        for r in results
    ]
    store.append(
        store.history_path(ROOT), [store.record(o, day) for o in observations]
    )
    print(f"\nimages in {out_dir}")
    _render(observations)
    return 0


def cmd_report(args: argparse.Namespace) -> int:
    """The last measurement for each model, ranked, with movement."""
    records = store.read(store.history_path(ROOT))
    if not records:
        print("nothing measured yet — run `imgbench run`")
        return 1

    latest = store.latest_by_model(records)
    observations = [
        Observation(
            id=model_id,
            measured_image=entry.get("measured_image"),
            fidelity=entry.get("fidelity"),
            samples=entry.get("samples", 0),
            discount=entry.get("discount", 0.0) or 0.0,
            quoted_image=entry.get("quoted_image"),
        )
        for model_id, entry in latest.items()
    ]
    _render(observations)

    moved = []
    for observation in observations:
        before, now = store.movement(records, observation.id)
        if before and now:
            was, is_now = before.get("measured_image"), now.get("measured_image")
            if was and is_now and abs(is_now - was) / was > 0.02:
                moved.append(
                    f"  {observation.id}: ${was:.4f} → ${is_now:.4f} "
                    f"({(is_now - was) / was:+.0%}) since {before['date']}"
                )
    if moved:
        print("\nprice moved:")
        print("\n".join(moved))
    return 0


def cmd_suggest(args: argparse.Namespace) -> int:
    """Cheaper swaps that are no less faithful, plus what is worth measuring."""
    records = store.read(store.history_path(ROOT))
    observed = {
        model_id: Observation(
            id=model_id,
            measured_image=entry.get("measured_image"),
            fidelity=entry.get("fidelity"),
            samples=entry.get("samples", 0),
        )
        for model_id, entry in store.latest_by_model(records).items()
    }
    if not observed:
        print("nothing measured yet — run `imgbench run`")
        return 1

    current = args.current or IN_USE
    incumbent = observed.get(current)
    if incumbent is None:
        print(f"{current} has never been measured — run `imgbench run --models {current}`")
        return 1

    print(
        f"in use: {incumbent.id}  "
        f"${incumbent.measured_image:.4f}  {(incumbent.fidelity or 0):.0%} fidelity\n"
    )

    better = [o for o in observed.values() if dominates(o, incumbent)]
    if better:
        print("cheaper and no less faithful:")
        for option in sorted(better, key=lambda o: o.measured_image or 0):
            saving = 1 - (option.measured_image or 0) / (incumbent.measured_image or 1)
            print(
                f"  {option.id:<40} ${option.measured_image:.4f}  "
                f"{(option.fidelity or 0):.0%}  saves {saving:.0%}"
            )
    else:
        print("no cheaper model matches it on fidelity — staying put is correct.")

    # Rejected models are named rather than omitted, so the same cheap option is
    # not reconsidered every time someone reads the table.
    rejected = [
        o for o in observed.values()
        if o.id != incumbent.id and o.measured_image is not None
        and (o.measured_image < (incumbent.measured_image or 0)) and not o.usable
    ]
    if rejected:
        print("\ncheaper but rejected on fidelity:")
        for option in rejected:
            print(
                f"  {option.id:<40} ${option.measured_image:.4f}  "
                f"{(option.fidelity or 0):.0%} — draws wrong characters"
            )

    moves = price_moves(records)
    if moves:
        print("\nprice moved since the previous run:")
        for model_id, was, now, when in moves:
            print(f"  {model_id:<40} ${was:.4f} → ${now:.4f} ({(now-was)/was:+.0%}) since {when}")

    try:
        catalog = parse_models(get_json(f"{BASE}/models"))
    except urllib.error.URLError:
        catalog = []
    unknown = worth_measuring(catalog, observed, incumbent)
    if unknown:
        cost = len(unknown) * 0.07
        print(f"\nnever measured ({len(unknown)}), ~${cost:.2f} to benchmark all:")
        for model in unknown:
            print(f"  {model.id}")
        print(
            "  The catalog cannot say whether these are cheaper — its prices do\n"
            "  not match the bill — nor whether they can draw kana at all."
        )
    return 0


def _render(observations: list[Observation]) -> None:
    print()
    print(f"{'model':<40} {'$/image':>9} {'fidelity':>9} {'$/usable':>9}  verdict")
    print("-" * 84)
    for observation in rank(observations):
        measured = f"${observation.measured_image:.4f}" if observation.measured_image else "—"
        fidelity = (
            f"{observation.fidelity:.0%}" if observation.fidelity is not None else "—"
        )
        effective = (
            f"${observation.cost_per_correct_image:.4f}"
            if observation.cost_per_correct_image
            else "—"
        )
        verdict = "use" if observation.usable else "REJECT — renders wrong characters"
        print(
            f"{observation.id:<40} {measured:>9} {fidelity:>9} {effective:>9}  {verdict}"
        )
    print(
        "\n$/usable is price divided by fidelity: what a correct image really costs.\n"
        "Fidelity below 95% is a reject at any price — a wrong glyph teaches a\n"
        "wrong letterform, which is worse than not practising."
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="imgbench",
        description="Which image model can draw Japanese, and what it costs.",
    )
    sub = parser.add_subparsers(dest="command")

    p_list = sub.add_parser("list", help="image-capable models and catalog prices")
    p_list.add_argument(
        "--discounts",
        action="store_true",
        help="also fetch per-model endpoints for promotion state (slower, needs key)",
    )
    p_list.set_defaults(func=cmd_list)

    p_run = sub.add_parser("run", help="benchmark models (costs money)")
    p_run.add_argument("--models", help="comma-separated ids (default: shortlist)")
    p_run.add_argument("--probe", help="run only this probe")
    p_run.add_argument("-y", "--yes", action="store_true", help="skip the cost prompt")
    p_run.set_defaults(func=cmd_run)

    p_report = sub.add_parser("report", help="last measurements, ranked")
    p_report.set_defaults(func=cmd_report)

    p_suggest = sub.add_parser(
        "suggest", help="cheaper swaps that are no less faithful")
    p_suggest.add_argument(
        "--current", help=f"model in use (default: {IN_USE})")
    p_suggest.set_defaults(func=cmd_suggest)

    args = parser.parse_args()
    if not getattr(args, "func", None):
        parser.print_help()
        return 0
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
