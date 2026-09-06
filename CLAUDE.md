# Perapera — development

A SwiftUI app for learning Japanese. This repository holds all of our code: the app at the
root, and our copy of Fluent at `fluent/`. Fluent originates in
[m98/fluent](https://github.com/m98/fluent), which is the `upstream` remote.

For what the app does and how to run it, see [README.md](README.md), [INSTALL.md](INSTALL.md)
and [USAGE.md](USAGE.md).

## Layout

| Path | What |
|---|---|
| `Sources/FluentCore/` | Pure values: `Lesson`, `Exercise`, `Grader`, `SessionReport`, `LessonPlan`. No SwiftUI, no subprocesses, no filesystem. |
| `Sources/FluentApp/` | The shell: SwiftUI views plus the effectful edges `ClaudeClient`, `FluentStore`, `LessonStore` and `ImagePipeline`. |
| `Sources/FluentApp/Resources/Prompts/` | Prompt text. Content, not code. |
| `Sources/FluentApp/Resources/Schemas/` | The JSON contracts passed to `claude --json-schema`. |
| `Tests/FluentCoreTests/` | 127 tests: grading rules, decode fixtures, the `update-db.py` wire format. |
| `tools/imgbench/` | Image-model benchmark. Its own `uv` project, 28 tests. |
| `fluent/` | Fluent: skills, hooks, six databases, methodology, 22 Python tests. |

## Rules that hold the design together

- **The app owns writes.** `claude` is a pure function: a prompt and a schema in, a
  validated value out. It never touches a database, so a bad generation costs a retry
  rather than a corruption.
- **Fluent owns the learning state.** SM-2, streaks, atomic writes and backups stay in
  `fluent/.claude/hooks/update-db.py`, the single writer. Nothing here reimplements them.
- **Fluent owns the pedagogy.** `fluent/docs/METHODOLOGY.md` states how Fluent teaches,
  independent of surface. Do not paraphrase teaching rules into Swift.
- **Grading splits by what each side can know.** The app supplies what it measures; the
  teacher supplies judgement. Neither is asked for the other's half.
- **Target language is Japanese.** Kana input, furigana, ruby and voice selection assume it.

## Working with upstream

```bash
git diff upstream/main -- fluent/     # what we changed
git merge upstream/main               # take their improvements
```

Keep `fluent/` mergeable. No macOS paths, no Japanese specifics, no app knowledge under
that directory; anything app-shaped belongs above it.

Our divergence is about 244 lines. The load-bearing part is the streak fix: upstream keys
the streak off `last_updated`, which `/fluent-setup` stamps at profile creation, so a
streak could never start. We added `last_session_date` and a backfill migration.

## Where things resolve

| Concept | Resolved by | Where |
|---|---|---|
| Fluent root | `Paths.defaultPluginRoot()` | `$CLAUDE_PLUGIN_ROOT`, else the stored `pluginRoot` setting |
| Learner data | `Paths.dataDirectory(pluginRoot:)` | `$FLUENT_DATA_DIR`, else repo-local `data/`, else `~/.claude/fluent-data` |
| Prompts and schemas | `ResourceLoader` | the repo copy when present, else `Bundle.module` |
| OpenRouter key | `Secrets.openRouter(repoRoot:)` | `$OPENROUTER_FLUENT`, else `.env` at the repo root |

These four are currently braided into one setting, `pluginRoot`, which only resolves
correctly from a git checkout. Pulling them apart is Phase 3 of
[TransitionPlan.md](TransitionPlan.md), which also moves learner state to
`${XDG_DATA_HOME:-~/.local/share}/perapera/profiles/<profile>/` and adds named profiles.

**No learner state belongs in this repository.** A JSON database appearing under the
checkout is a bug, and `/fluent/data/*.json` is gitignored to keep a stray CLI run from
committing one.

## Testing

```bash
swift test                                        # 127, no network
cd fluent && python3 -m unittest discover -s tests # 22, stdlib only
cd tools/imgbench && uv run pytest                # 28
```

Fluent's Python must import nothing outside the standard library. Claude Code invokes the
hooks against whatever interpreter the learner has, with no venv and no install step, and
`test_stdlib_only.py` asserts this so it cannot be lost by accident.

`test_update_db.py` runs `update-db.py` as a subprocess with an explicit `env`. Do not
remove that: without it the subprocess inherits `$FLUENT_DATA_DIR`, which outranks the
working directory in `fluent_paths.data_dir()`, and the suite writes its fixture sessions
into a real learner's databases. It did exactly that once.

## Calling `claude -p`

`ClaudeClient` streams `--output-format stream-json` so the wait can be shown rather than
spun through, validates against a schema, and retries once on malformed output only.

Measured 2026-09-02: a `claude -p` call from this directory loads both
`~/.claude/CLAUDE.md` and this file into every lesson. Neither belongs in a lesson. Phase 4
of the plan moves the call to `--safe-mode` with an assembled `--system-prompt`, so the
teacher's context is exactly what the app puts there. Until then, remember that this file
reaches the model.

Use `--tools ""` to remove the tools. `--allowedTools ""` only empties the permission
allowlist and leaves the tools defined.

## Build

```bash
make app     # build, assemble Fluent.app, ad-hoc sign
make run     # and launch
make icon    # regenerate the icon from tools/make-icon.swift
```

App Sandbox is off because the app spawns `claude` and `python3`.
