# Perapera

A macOS app for learning Japanese, built on [Fluent](https://github.com/m98/fluent).
Claude writes the lessons, the app renders and grades them offline, and finished
lessons are written back through Fluent's database scripts.

- [INSTALL.md](INSTALL.md) — build it, run it, point it at your data
- [USAGE.md](USAGE.md) — the daily loop
- [CLAUDE.md](CLAUDE.md) — how the code is organised

## Why it exists

The terminal is a poor exercise surface. It has no audio, no lesson archive and no
offline practice, and the system IME silently converts kana to kanji, so typing
Japanese tests recognition instead of recall. The app fixes the surface. Fluent's
databases, SM-2 scheduling and skills stay the system of record.

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

Two rules hold this together.

**The app owns writes.** Claude is a pure function: a prompt and a schema go in, a
validated value comes out. It never touches a database, so a bad generation costs a
retry rather than a corruption.

**Fluent owns the learning state.** SM-2, streaks, atomic writes and backups live in
`update-db.py`, which is tested and already authoritative. A Swift reimplementation
would be a second source of truth that drifts away from the first.

Grading splits the same way. The app supplies what it can measure: which answers were
right, how long the lesson took, which items were reviewed. The teacher supplies
judgement: which mistakes are worth tracking, what to work on next. Neither is asked
for the other's half.

## Layout

| Path | What |
|---|---|
| `Sources/FluentCore/` | Pure values: `Lesson`, `Exercise`, `Grader`, `SessionReport`. No SwiftUI, no subprocesses. |
| `Sources/FluentApp/` | The shell: views, plus the effectful edges `ClaudeClient`, `FluentStore` and `ImagePipeline`. |
| `Sources/FluentApp/Resources/Prompts/` | Prompt text. Content, not code. |
| `Sources/FluentApp/Resources/Schemas/` | The JSON contracts passed to `claude --json-schema`. |
| `Tests/` | Grading rules, the `update-db.py` wire format, profile slugs, the migration. 149 tests, no network. |
| `tools/imgbench/` | Image-model benchmark. Its own `uv` project, 28 tests. |
| `fluent/` | Fluent: skills, hooks, six databases, methodology, 29 Python tests. |

`Exercise` decodes flat JSON into a Swift sum type. The schema is flat because models
generate flat objects far more reliably than discriminated unions. The boundary
validates; the interior gets a real sum type with no optionals to thread through the UI.

## Credits

This app is a front end. Everything that makes it teach anything comes from
**[Fluent](https://github.com/m98/fluent)** by Mohammad Kermani: 396 stars, MIT licensed,
and the reason this project exists at all.

Fluent supplies the parts that are hard to get right:

- the SM-2 spaced-repetition implementation, and `update-db.py`, which has stayed the
  single writer of every database through this whole project
- the six-database schema: profile, progress, mistakes, mastery, review queue, session log
- the teaching methodology (active recall, desirable difficulty at 60-70%, interleaving,
  comprehensible input) and the error taxonomy the feedback is graded against
- twelve skills, including the `/fluent-setup` interview that still creates every profile
  this app reads

I did not improve on any of that. I put a window in front of it, because the terminal
cannot play audio, cannot hold a lesson archive, and lets the system IME turn your kana
into kanji before you have learned them. Fluent remains the system of record; if you want
the tutor without the window, install it directly and skip this repo:

```bash
claude plugin marketplace add m98/fluent && claude plugin install fluent@m98
```

## Relationship to Fluent

`fluent/` is our copy of Fluent, and `upstream` points at the original. It carries about
244 lines of changes, of which one matters: upstream keys the streak off `last_updated`,
which `/fluent-setup` stamps at profile creation, so a streak could never start. We added
`last_session_date` and a backfill. That fix belongs upstream and has not been sent yet.

```bash
tools/upstream-diff.sh                # what we changed
git merge upstream/main               # take their improvements
```

## Licence

MIT, inherited from Fluent. See [LICENSE](LICENSE).

## Status

The core loop works end to end: generate a lesson, do it offline, finish it, and the
results land in Fluent's six databases. Japanese TTS, kana input with the IME bypassed,
Core Text furigana, generated photographs with the writing verified before you see it,
word drills, a picture library, saved words and per-call spending are all live.

Learner state lives under `$XDG_DATA_HOME` in named profiles, and `make install` produces a
bundle that carries its own snapshot of Fluent, so the installed app needs no checkout.

Outstanding work is tracked in `TODO.md`; the reshape that got here is recorded in
[TransitionPlan.md](TransitionPlan.md).
