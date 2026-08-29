# imgbench

Which image model can actually draw Japanese, and what it costs.

```bash
python3 tools/imgbench/cli.py list          # models, catalog price, discount
python3 tools/imgbench/cli.py run           # benchmark the shortlist (costs money)
python3 tools/imgbench/cli.py report        # last measurements, ranked
```

Adapted from the `llm` price watch in the options repo, which keeps two facts
apart because they come from different endpoints: the **effective price**
(`/models`, already net of promotion) and the **discount**
(`/models/{id}/endpoints`, i.e. how far the price can snap back). A cheap model
at 0% off is a stable choice; the same price at 75% off is a lease.

Image models need a third fact, and it dominates the other two.

## Why price alone selects the wrong model

`gemini-2.5-flash-image` costs 43% less than `gemini-3.1-flash-image`. Asked for
みなみぐち it drew **みなみりぢち** — confidently, in a beautiful sign.

For a reading drill a wrong glyph teaches a wrong letterform, which is worse
than not practising at all. So the cheaper model is not a saving; it is a defect
generator, and any ranking that reads only the price column will choose it.

Fidelity cannot be read from an endpoint. It has to be measured — which is why
this tool generates images rather than only fetching prices.

## The catalog is not just incomplete, it is wrong

```
model                                              quoted   measured
google/gemini-2.5-flash-image                  $0.0000003   $0.0387
google/gemini-3.1-flash-image                           —   $0.0677
```

The quoted figure is per-token and bears no relation to the per-image bill — a
130,000x gap. Blank is common. `measured` is the only real number, and it comes
from metering an actual generation.

## What a run does

For each model, for each probe: generate → read the image back with a vision
model → score the transcription against the exact text that was requested.

The probes target what breaks, not what is easy:

| Probe | Catches |
|---|---|
| `dakuten` | ぐ drawn as く or り — the failure that exposed 2.5-flash |
| `katakana_confusables` | dropped long-vowel marks, ギ losing its dakuten |
| `handwritten_small_kana` | small ゃゅょっ drawn full size |
| `vertical_brush` | the hardest render, and れ/ね/わ |

Scoring is per target, all-or-nothing. みなみりぢち shares four characters with
みなみぐち and earns zero, because a nearly-right glyph is exactly what this
exists to catch.

A run costs roughly `models x probes x $0.069` and prompts before spending.

## Reading the report

```
model                                     $/image  fidelity  $/usable  verdict
google/gemini-3.1-flash-image             $0.0677      100%   $0.0677  use
google/gemini-2.5-flash-image             $0.0387       75%   $0.0516  REJECT
```

`$/usable` is price divided by fidelity: what a *correct* image really costs,
counting the ones you throw away. Below 95% fidelity a model is rejected at any
price.

Rejected models stay in the table rather than being dropped, so a run records
why they were rejected.

## The log

`history.jsonl`, append-only, one line per measurement. Only observed values are
persisted — never rankings or verdicts — so if the usable threshold changes,
old runs re-rank correctly instead of carrying a stale judgement.

## Layout

| File | |
|---|---|
| `catalog.py` | pure: parse `/models`, discount logic, ranking |
| `fidelity.py` | pure: the probe set and scoring |
| `store.py` | the append-only log |
| `cli.py` | the shell: fetching, generating, verifying, rendering |
| `test_imgbench.py` | 21 tests, no network |

## Credentials

`run` needs `OPENROUTER_FLUENT`, read from the environment or from a `.env` at
the repo root:

```
OPENROUTER_FLUENT=sk-or-...
```

`.env` is gitignored. The key is Fluent-specific rather than shared with other
projects, so revoking it cannot break them. `list` and `report` need no key.
