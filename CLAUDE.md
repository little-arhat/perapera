# Perapera — Fluent for macOS

A SwiftUI front end for Fluent. This repository holds **all of our code**: the app at the
root, and our Fluent at `fluent/`. Fluent originates in
[m98/fluent](https://github.com/m98/fluent), which is the `upstream` remote — not a
submodule, and not a second copy on disk.

## Layout

| Path | What |
|---|---|
| `Sources/FluentCore/` | Pure values: `Lesson`, `Exercise`, `Grader`, `SessionReport`, `ProfileSlug`. No SwiftUI, no subprocesses, no filesystem outside injected URLs. |
| `Sources/FluentApp/` | The shell: SwiftUI views plus the effectful edges — `ClaudeClient`, `FluentStore`, `ImagePipeline`, `ProfileStore`. |
| `Sources/FluentApp/Resources/Prompts/` | Prompt text. Content, not code. |
| `Sources/FluentApp/Resources/Schemas/` | The JSON contracts passed to `claude --json-schema`. |
| `Tests/FluentCoreTests/`, `Tests/FluentAppTests/` | Grading rules, the `update-db.py` wire format, path and slug math. |
| `tools/imgbench/` | Image-model benchmark (its own `uv` project). |
| `fluent/` | Fluent: skills, hooks, six databases, methodology, its own tests. |

## Working with upstream

```bash
git diff upstream/main -- fluent/     # what we changed
git merge upstream/main               # take their improvements
```

Keep `fluent/` mergeable: no macOS paths, no Japanese specifics, no app knowledge in there.
Anything app-shaped belongs above `fluent/`.

## The four locations, kept apart

They used to be one setting called `pluginRoot`. They are not one thing.

| Concept | Resolved by | Where |
|---|---|---|
| Fluent root | `Locations.kitRoot()` | `$FLUENT_KIT_ROOT`, else `Fluent.app/Contents/Resources/fluent` |
| Profile directory | `ProfileStore.active()` | `~/Library/Application Support/Fluent/profiles/<id>/` |
| App resources | `ResourceLoader` | `$FLUENT_APP_RESOURCES`, else `Bundle.module` |
| Credentials | `Secrets` | `$OPENROUTER_FLUENT`, else `~/Library/Application Support/Fluent/credentials.env` |

`Locations.kitRoot()` returns nil under `swift run` — there is no bundle to look in — so
for development export `FLUENT_KIT_ROOT=$PWD/fluent`, or work through `make run`, which
builds the bundle. `.claude/settings.local.json` sets it for terminal sessions.

**No learner state lives in this repository.** If you find yourself writing a JSON database
under the checkout, that is the bug.

## Rules that hold the design together

- **The app owns writes.** `claude` is a pure function: a prompt and a schema in, a
  validated value out. It never touches a database. A bad generation is a retry, not a
  corruption.
- **Fluent owns the learning state.** SM-2, streaks, atomic writes and backups stay in
  `fluent/.claude/hooks/update-db.py`, the single writer. Nothing here reimplements them.
- **Fluent owns the pedagogy.** `fluent/docs/METHODOLOGY.md` is the teacher's brief; the
  app assembles it into the system prompt via `Resources/teacher-context.json`. Do not
  paraphrase teaching rules into Swift.
- **`claude -p` runs with `--safe-mode`.** No ambient `CLAUDE.md`, no hooks, no skills —
  the context is exactly what the app puts in `--system-prompt`. This file is development
  instruction and must never reach a lesson.
- **Target language is Japanese.** Kana input, furigana, ruby and voice selection assume
  it. Profiles make other languages storable, not supported.
- **Use one surface at a time.** The app and a terminal tutor session write the same six
  databases through the same script, and nothing serialises them (FL-31).

## Build and test

```bash
swift test          # no network
make app            # build + bundle the fluent snapshot + ad-hoc sign
make run            # and launch
make install        # copy to /Applications
```

## Running tutor sessions in the terminal

The skills live in `fluent/`. Run them from there — it needs its own
`.claude/settings.local.json`, because a session rooted at `fluent/` does not read this
directory's settings. Both copies carry the same `FLUENT_DATA_DIR`, and both are
gitignored. If it is unset, Fluent silently creates an empty database set at
`~/.claude/fluent-data` rather than failing.
