# Fluent — macOS app

A SwiftUI front end for Fluent. Claude generates lessons, the app renders and
grades them (offline), and finished lessons are written back through Fluent's
existing database scripts.

## Why it exists

The terminal is a poor exercise surface. It has no audio, no lesson archive, no
offline practice, and — the reason that actually forced this — the system IME
silently converts kana to kanji, so typing Japanese tests *recognition* rather
than *recall*. The app fixes the surface. Fluent's databases, SM-2 scheduling,
and skills remain the system of record.

## Design

```
Generate ──► claude -p --json-schema ──► lesson JSON (validated)
                                              │
                                    lessons/*.json  (authoritative)
                                              │
                                     SwiftUI renders one at a time
                                              │
                                    Grader (pure, local, offline)
                                       ├─ auto-gradable → instant verdict
                                       └─ open-ended    → held for the teacher
                                              │
                                     "Finish lesson" (needs network)
                                              │
                                claude -p ──► feedback JSON (validated)
                                              │
                                     update-db.py  ← the single writer
```

Two rules hold the design together:

**The app owns writes.** Claude is a pure function — a prompt and a schema go
in, a validated value comes out. It never touches a database. A bad generation
is a retry, not a corruption.

**Fluent owns the learning state.** SM-2, streaks, atomic writes, and backups
stay in `update-db.py`, which is tested and already authoritative. Nothing here
reimplements them; duplicating that logic in Swift would create a second source
of truth that drifts.

The split extends to grading: the app supplies every fact it can *measure*
(which answers were right, how long the lesson took, which items were reviewed),
and the teacher supplies only *judgement* (which mistakes are worth tracking,
what to focus on next). Neither is asked for the other's half.

## Layout

| Path | What |
|---|---|
| `Sources/FluentCore/` | Pure values: `Lesson`, `Exercise`, `Grader`, `SessionReport`. No SwiftUI, no subprocesses. |
| `Sources/FluentApp/` | The shell: views, plus the two effectful edges (`ClaudeClient`, `FluentStore`). |
| `Sources/FluentApp/Resources/Prompts/` | Prompt text. Content, not code — edit without rebuilding. |
| `Sources/FluentApp/Resources/Schemas/` | The JSON contracts passed to `claude --json-schema`. |
| `Tests/FluentCoreTests/` | Grading rules and the `update-db.py` wire format. |

`Exercise` decodes flat JSON into a Swift sum type. The schema is flat because
models generate flat objects far more reliably than discriminated unions; the
boundary validates, and the interior gets a real sum type with no optionals to
thread through the UI.

## Build

```bash
make app     # build + assemble Fluent.app + ad-hoc sign
make run     # and launch it
make test    # swift test
```

Requires Xcode (for the SDK and the test frameworks) and Swift 6. There is no
`.xcodeproj` on purpose — this is a plain Swift package, and the bundle is four
files of metadata rather than a reason to adopt a project format.

The app spawns `claude` and `python3`, so **App Sandbox is off**. A sandboxed
build cannot work.

## Settings

`claude` is located on PATH at first launch, including the usual Homebrew
locations, since a GUI app inherits a minimal PATH. Repo path, `claude` path,
and model are editable in Settings (⌘,).

Opus generates and grades by default. Generation is the high-volume call, so
switching *it* to Sonnet is the main cost lever; every call carries a
`--max-budget-usd` ceiling.

## Offline

Generation and feedback need the network. Everything between them does not.
Generate several lessons, do them on a plane, and press **Finish lesson** when
you land — a completed lesson waits in `completed` state until it can be sent.
One lesson becomes one Fluent session.

## Status

Phase 1 (core loop) is built. Not yet done:

- **Phase 2** — Japanese TTS, and kana input with the IME bypassed.
- **Phase 3** — progress dashboard, furigana, kanji reading drills.
