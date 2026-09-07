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
| `Tests/FluentCoreTests/` | Grading rules, decode fixtures, the `update-db.py` wire format, profile slugs, the teacher's brief. |
| `Tests/FluentAppTests/` | The migration and the teacher-context assembly. |
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
| Fluent root | `Locations.fluentRoot()` | `$FLUENT_KIT_ROOT`, else `Fluent.app/Contents/Resources/fluent` |
| Profile directory | `ProfileStore.active` | `${XDG_DATA_HOME:-~/.local/share}/perapera/profiles/<id>/` |
| Prompts and schemas | `ResourceLoader` | `$FLUENT_APP_RESOURCES`, else `Bundle.module` |
| OpenRouter key | `Secrets.openRouter()` | `$OPENROUTER_FLUENT`, else `<state root>/credentials.env`, mode 0600 |

They used to be one setting, `pluginRoot`, which only resolved from a git checkout.

`Locations.fluentRoot()` returns nil under `swift run`, since there is no bundle to look
in. For development export `FLUENT_KIT_ROOT=$PWD/fluent`, or work through `make run`, which
builds the bundle. `.claude/settings.local.json` sets it for terminal sessions.

State lives under `$XDG_DATA_HOME` rather than `~/Library/Application Support` because the
same directory is read by Python hooks and five Fluent skills driven from a shell, and that
path contains a space every one of them has to quote. Time Machine and Migration Assistant
take the whole home directory either way.

**No learner state belongs in this repository.** A JSON database appearing under the
checkout is a bug, and `/fluent/data/*.json` is gitignored to keep a stray CLI run from
committing one.

## Testing

```bash
swift test                                        # 149, no network
cd fluent && python3 -m unittest discover -s tests # 29, stdlib only
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

It runs with `--safe-mode` and an assembled `--system-prompt`, so the teacher's context is
exactly what `Resources/teacher-context.json` names and nothing else. Before that, every
lesson silently carried whichever `CLAUDE.md` the working directory sat under — the
machine's global one, and this file — and never Fluent's methodology, because the call has
no tools to read it.

The manifest deliberately excludes `fluent/CLAUDE.md` and `fluent/LEARNING_SYSTEM.md`: they
instruct an interactive session to read files and update databases, which is the wrong
surface for a JSON generator.

Use `--tools ""` to remove the tools. `--allowedTools ""` only empties the permission
allowlist and leaves the tools defined.

## Build

```bash
make app      # build, bundle the fluent snapshot, ad-hoc sign
make run      # and launch
make install  # copy to /Applications
make icon     # regenerate the icon from tools/make-icon.swift
```

`make app` refuses to build while `fluent/` has uncommitted changes: it snapshots the
subtree with `git archive`, which ships the commit rather than the working tree.

App Sandbox is off because the app spawns `claude` and `python3`.
