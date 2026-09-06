# Perapera: Repository Reshape Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development`
> (recommended) or `superpowers:executing-plans` to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking. **Every task ends with a
> verification block. If a verification fails, STOP — do not proceed to the next task.**

**Goal:** Turn this repository into `perapera` — one repo holding all of our code, with the
Swift app at the root and our fluent at `fluent/` — move all learner state out of the repo
into `~/Library/Application Support/Fluent` under named profiles, make the app installable
with a bundled fluent snapshot, and give `claude -p` an explicit, fluent-sourced teaching
context. No progress, no lesson archive and no git history is lost.

**Architecture:** One repository, reshaped by `git mv` — no second repo, no submodule, no
history rewriting. The app moves from `app/` to the root; fluent's own files (hooks,
skills, references, templates, docs, tests) move from the root into `fluent/`. `origin`
becomes `little-arhat/perapera`; `m98/fluent` becomes the `upstream` remote, so their
improvements arrive by `git merge upstream/main` and our divergence is one
`git diff upstream/main -- fluent/` away.

Four concepts currently braided into one setting (`pluginRoot`) are pulled apart: **fluent
root** (scripts + methodology — `<repo>/fluent` in development, a bundled snapshot when
installed), **profile directory** (all mutable learner state), **app resources** (prompts
and schemas, from `Bundle.module`), and **credentials** (Application Support, mode 0600).
Learner state moves from `~/.claude/fluent-data` to
`~/Library/Application Support/Fluent/profiles/<id>/`, copied and byte-verified before the
old location is retired.

**Tech Stack:** Swift 6 / SwiftUI / SPM (macOS 14+), Python 3 stdlib-only (fluent's hooks),
`claude` CLI 2.1.258, `make`.

**Spec:** This document is both spec and plan. The requirements it implements are the
seven points in the transition request, restated in [Requirements](#requirements) below.

---
## Global Constraints

- **No state loss.** Every phase is preceded by a restorable backup and followed by a
  verification that compares against a recorded baseline. Copy-then-verify-then-retire,
  never move-and-hope.
- **No history loss.** All 63 pre-transition commits stay reachable. Every relocation is a
  `git mv` in one repository — no rebase, no `filter-branch`, no `filter-repo`, no
  force-push over existing history.
- **One repository.** All of our code lives in `perapera`. `m98/fluent` is a remote we
  merge from, never a second copy on disk.
- **`fluent/.claude/hooks/update-db.py` remains the single writer** of the six learning
  databases. Nothing in Swift reimplements SM-2, streaks, or backups.
- **Fluent stays stdlib-only Python** — `fluent/tests/test_stdlib_only.py` enforces it and
  must stay green.
- **Fluent stays language-agnostic and surface-agnostic.** No macOS paths, no Japanese
  specifics, no app knowledge under `fluent/`. It must remain mergeable with upstream.
- **Japanese stays the only supported target language in the app** (kana input, furigana,
  ruby, TTS voice selection). Profiles make other languages *possible*, not *supported*.
- **Swift 6, macOS 14 minimum**, `swift-tools-version: 6.0`. App Sandbox stays **off**
  (the app spawns `claude` and `python3`).
- **Python interpreter is `/usr/bin/python3`** (system Python; no venv, no install step).
- **Filesystem is case-insensitive APFS and `core.ignorecase=true`.** `Tests/` and
  `tests/`, `Tools/` and `tools/`, are the same path. Ordering in Phase 2 depends on this.
- Commit after every task. Conventional-commit style, matching the existing log.

---
## Requirements

| # | Requirement | Phase |
|---|---|---|
| R1 | Fluent separated from the app, upstream trackable | 2 (`fluent/` + `upstream` remote) |
| R2 | App code at the repo root, app git history preserved | 2 |
| R3 | A `CLAUDE.md` specific to the app | 2 |
| R4 | `claude -p` gets the right fluent coordinates, and fluent's teaching instructions actually reach the model | 1, 4 |
| R5 | The app is installable, with a fluent snapshot bundled | 6 |
| R6 | State (databases, images, dictionaries, spending, results) lives in `~/Library/Application Support`, not the repo | 3 |
| R7 | Create and switch learner profiles | 3, 5 |
| R8 | Keep the Japanese focus | (constraint) |

**On R1.** The original request said "move fluent into a submodule". It becomes a
directory plus an `upstream` remote instead, because our fluent is not pristine: it carries
244 lines of our changes, including the `last_session_date` streak fix in `read-db.py` and
`update-db.py` that the app depends on. A submodule of pristine `m98/fluent` would put a
second, divergent `update-db.py` on disk — the one with the bug — which is the duplication
the submodule was meant to avoid. A remote gives the same diffing and, unlike a submodule,
can actually merge upstream's work in. Decided 2026-09-03.

---
## Measured Starting State

Recorded 2026-09-02. The executor re-measures these in Task 0.1 and compares.

| Fact | Value |
|---|---|
| HEAD | `edb680379a4437adfa546df03f54ea846d8d637b` (`edb6803`) |
| Commits on `main` | 63 |
| Commits ahead of `origin/main` (m98/fluent) | 38 |
| Merge base with upstream | `86fb80f` |
| Swift tests | 127, all passing |
| Kit Python tests | 19, all passing (`python3 -m unittest discover -s tests`) |
| imgbench tests | 28, all passing (`uv run pytest` in `tools/imgbench`) |
| Live data directory | `~/.claude/fluent-data` (1.7 MB) |
| Lesson records | 7 JSON + 2 asset folders |
| Learner | Roma · Japanese · A1 → B2 · streak 1 · 7 sessions |
| Recorded spend | $0.74 |
| `gh` CLI | **not installed** (repos created in a browser; `git` over ssh works) |
| Kit repo | `git@github.com:little-arhat/perapera.git` — created empty, ssh verified 2026-09-03 |
| Git remote `origin` | `https://github.com/m98/fluent` |
| Extra git ref | `refs/claude/checkpoint-8e19f5f3` |

### Files that are untracked or gitignored and must survive

These are invisible to `git` and are the easiest thing to lose. All of them are real state:

| Path | Why it matters |
|---|---|
| `TODO.md` | The working ticket list (FL-1…FL-28). Gitignored on purpose. |
| `.env` | `OPENROUTER_FLUENT` key. No other copy exists. |
| `results/fluent-learn-session-001.md`, `results/fluent-review-session-002.md` | Written session transcripts from CLI tutor sessions. |
| `.claude/settings.local.json` | Local permission allowlist. |
| `.claude/RESUME.md` | Points at `refs/claude/checkpoint-8e19f5f3`. |
| `tools/imgbench/samples/` | Benchmark images (large, disposable, but measured). |
| `~/.claude/fluent-data/**` | **All** learner state, including `.backups/`. |
| `~/Library/Preferences/dev.fluent.app.plist` | App `UserDefaults` (paths, text size, speech rate, voice). |
| `.git/info/exclude` | Local ignore rules — `.claude/RESUME.md` resolves to `.git/info/exclude:7`, not `.gitignore`. `git bundle` does not carry it. |

---

## Target State

### The repository (`/Users/r/prj/p/lang/fluent`, origin `little-arhat/perapera`)

```
.
├── CLAUDE.md                    NEW — app-development instructions
├── README.md                    was app/README.md
├── LICENSE                      kept (MIT, shared lineage with m98/fluent)
├── TransitionPlan.md            this file
├── TODO.md                      untracked, unchanged
├── Makefile                     was app/Makefile
├── Package.swift                was app/Package.swift
├── Sources/
│   ├── FluentCore/              was app/Sources/FluentCore/
│   └── FluentApp/               was app/Sources/FluentApp/
├── Tests/
│   ├── FluentCoreTests/         was app/Tests/FluentCoreTests/
│   └── FluentAppTests/          NEW (Task 4.1)
├── Resources/                   was app/Resources/ (Info.plist, Fluent.icns, iconset)
├── tools/
│   ├── make-icon.swift          was app/Tools/make-icon.swift  (lowercase: see Task 2.2)
│   └── imgbench/                unchanged
├── docs/research/               unchanged
├── .claude/                     app-development settings only
└── fluent/                      ← everything below was at the repo root
    ├── CLAUDE.md                the tutor persona
    ├── LEARNING_SYSTEM.md       CLI session choreography, linking to METHODOLOGY.md
    ├── docs/METHODOLOGY.md      NEW — surface-independent pedagogy (Task 1.1)
    ├── docs/DB_SCRIPTS.md
    ├── PRACTICE.md  README.md  AGENTS.md  CONTRIBUTING.md  CHANGELOG.md
    ├── .claude/{hooks,skills,references}/  settings.json
    ├── .claude-plugin/
    ├── data-examples/           the six DB templates — the schema authority
    ├── tests/                   21 stdlib-only Python tests
    └── data/                    .gitkeep + README only
```

`fluent/results/` is **removed** in Task 1.2: transcripts move beside the databases, and
leaving the directory would be a second documented answer to "where do transcripts go".

### Remotes

| Remote | URL | Role |
|---|---|---|
| `origin` | `git@github.com:little-arhat/perapera.git` | ours; everything is pushed here |
| `upstream` | `https://github.com/m98/fluent` | the project this forked from; merge-base `86fb80f` |

`git diff upstream/main -- fluent/` shows our divergence; `git merge upstream/main` brings
their work in. That is the whole upstream story — no submodule, no vendored second copy.

### Learner state (`~/Library/Application Support/Fluent`)

```
~/Library/Application Support/Fluent/
├── credentials.env                     mode 0600 — OPENROUTER_FLUENT=…
├── migration.log                       what was moved, when, and from where
└── profiles/
    └── roma-japanese/
        ├── learner-profile.json        ┐
        ├── progress-db.json            │
        ├── mistakes-db.json            ├─ written only by update-db.py
        ├── mastery-db.json             │
        ├── spaced-repetition.json      │
        ├── session-log.json            ┘
        ├── saved-items.json            ┐
        ├── pictures.json               ├─ written only by the app
        ├── spending.json               ┘
        ├── lessons/*.json
        ├── lessons/assets/<lesson-id>/*.jpg
        ├── lessons/assets/on-demand/*.jpg
        ├── results/*.md                CLI session transcripts (Task 1.2)
        └── .backups/
```

---

## Design Decisions, With Their Tradeoffs

### D1 — One repository, reshaped by `git mv`

Everything of ours lives in `perapera`. The app moves to the root, fluent moves to
`fluent/`, both with `git mv`, so the index records renames and `git log --follow` walks
through the move. No SHA is rewritten; `refs/claude/checkpoint-8e19f5f3` and every commit
reference in `TODO.md` stay valid.

**Tradeoff:** `git log -- Sources/` shows only post-move commits, because git stores
snapshots rather than renames. `git log --follow <file>` and `git log -- app/<old path>`
both still work, and that is the whole cost.

### D2 — Upstream is a remote, not a submodule or a second repo

Our fluent carries 244 lines of changes on top of `m98/fluent`, including the streak fix
the app depends on. A submodule of pristine upstream would mean two divergent copies of
`update-db.py` on disk, and the app would build against the wrong one.

A remote does more with less: `git diff upstream/main -- fluent/` for divergence,
`git merge upstream/main` to actually take their improvements — which a submodule cannot
do — and the merge-base records what we forked from. It also sidesteps CVE-2022-39253,
which refuses the `file://` transport for submodules and would have put
`-c protocol.file.allow=always` on every clone and update.

**Tradeoff:** upstream's history is not checked out beside ours, so reading their current
version of a file means `git show upstream/main:.claude/hooks/update-db.py` rather than
opening it. A fetch away, and worth it to keep one copy of every file.

### D3 — `claude -p` gets an explicit system prompt, not ambient `CLAUDE.md`

**Measured today** (probe run 2026-09-02): a `claude -p` call from this repo loads
`/Users/r/.claude/CLAUDE.md` *and* `/Users/r/prj/p/lang/fluent/CLAUDE.md` into every lesson
generation and grading call. The first is the learner's global software-engineering
compass — pure noise, paid for on every lesson. The second is the tutor persona, written
for an interactive CLI session that reads files and writes databases: instructions the app
must *not* follow. `LEARNING_SYSTEM.md` — the actual methodology — never arrives at all,
because the call runs with no tools.

Also measured: `--safe-mode` drops all `CLAUDE.md` discovery, skills, plugins and hooks
while leaving OAuth, `--json-schema`, `--output-format stream-json`,
`--include-partial-messages` and `total_cost_usd` fully working.

So: `--safe-mode` plus a `--system-prompt` the app assembles from a manifest of kit
documents. Context becomes a value the app composes, not a side effect of a working
directory.

**Tradeoff:** the app must now say explicitly what the teacher knows. That is the point,
but it means a kit document that changes has to be in the manifest to take effect — the
manifest is data (`Resources/teacher-context.json`), so this is a one-line edit, not a
rebuild-shaped problem.

### D4 — The kit grows `docs/METHODOLOGY.md`

`LEARNING_SYSTEM.md` braids two things: *what good language teaching is* (principles,
exercise types, adaptive difficulty, error categories, feedback content, quality checks)
and *how a CLI chat session is choreographed* (read these files, greet, present one
question at a time, update these databases, print this summary — with slash commands
still named `/dutch`). Only the first half is true for the app.

Task 2.1 splits them: `docs/METHODOLOGY.md` holds the surface-independent half,
`LEARNING_SYSTEM.md` keeps the choreography and links to it. Both surfaces then read the
same pedagogy from one place.

**Tradeoff:** a prose refactor in a file the upstream may also edit, making future merges
from `m98/fluent` slightly noisier. Worth it: without the split, "use all of fluent's
instructions" means feeding a JSON generator a script telling it to write files.

### D5 — A profile is one learner *and* one target language

`learner-profile.json` holds exactly one `target_language`, so "Roma learning Japanese" and
"Roma learning Spanish" are two profiles. Profile id is a slug derived from name and
language (`roma-japanese`), uniquified with a numeric suffix on collision.

The profile *list* is derived by scanning `profiles/*/learner-profile.json` — no index
file to drift out of sync. Only the **active** profile id is stored, in `UserDefaults`,
because "which profile is open on this Mac" is a per-machine preference, not learner state.

**Tradeoff:** listing costs a directory scan and N small JSON reads at launch. With a
handful of profiles this is microseconds, and it removes a whole class of "the index says
something the directory doesn't" bugs.

### D6 — Migration copies, verifies, then retires

`~/.claude/fluent-data` is **copied** into `profiles/<slug>/`, every file's SHA-256 is
compared, and only then is the old directory renamed to
`~/.claude/fluent-data.migrated-YYYYMMDD` with a `README.txt` pointing at the new home.

The rename is not tidiness. Both the app and the CLI resolve `~/.claude/fluent-data` as a
default; leaving a readable copy there is an invitation to a silent split-brain where the
CLI updates one set of databases and the app another.

**Tradeoff:** any shell alias or script pointing at the old path breaks loudly. Loudly is
correct — the alternative is two divergent copies of the learner's progress.

### D7 — The CLI follows the app, via `FLUENT_DATA_DIR`

`~/.claude/fluent-data` is not a Claude Code convention and Claude Code has never heard of
it. It is defined at exactly one line — `fluent_paths.py:58` — as fluent's own last-resort
fallback, chosen because `~/.claude/` is where plugins park things. `data_dir()` checks
`$FLUENT_DATA_DIR` first, `expanduser`s and `resolve`s it, and asks no questions. Any path
works.

**Verified 2026-09-02** (read-only probes, no data moved):

- `FLUENT_DATA_DIR="/tmp/space probe/data" python3 .claude/hooks/read-db.py` and
  `session-start.py` both work — the space in `Application Support` is not a problem for
  fluent, which never shells out and receives the path through `argv`/`os.environ`.
- A project `.claude/settings.json` `"env"` block **is** exported into hook and command
  environments: a `printenv FLUENT_DATA_DIR` SessionStart hook in a scratch directory read
  back `/Users/r/Library/Application Support/Fluent/profiles/roma-japanese`, space intact.
  This is the mechanism Task 3.5 relies on.
- `precompact-backup.sh` quotes `"$DATA_DIR"` throughout, so it survives the space too.

The app sets both coordinates explicitly on every subprocess; the developer machine sets
`FLUENT_DATA_DIR` in `.claude/settings.local.json` (untracked after Task 2.3, so an
absolute path is appropriate there). The kit learns nothing about macOS.

The app's `claude -p` calls are a separate question and a simpler one: after Task 4.2 they
run `--safe-mode --tools ""`, so `claude` loads no plugin, runs no hook and reads no
database. It receives a prompt and returns JSON. Where the data lives is invisible to it.

### D7a — One profile, one writer at a time — by convention, not by lock

`update-db.py` writes each of the six databases atomically, but nothing coordinates *two*
writers. Two real races exist once the app and the CLI share a profile directory:

- A terminal `/fluent-review` session and the app's **Finish lesson** overlapping: both
  call `update-db.py`, each having read the pre-update state, so the second silently
  discards the first's SM-2 updates. Same-session-id calls replace by design, but these
  carry different ids.
- A terminal tutor session running while the app performs its **first-launch migration**:
  `Migrator` renames the directory out from under it, and the CLI's next
  `ensure_data_dir()` recreates an empty one and starts a divergent profile.

This plan does **not** add a lockfile. A lock is a real design decision — what it covers,
what happens when it is stale, whether the CLI can honour it at all when the writer is a
skill the model invokes — and inventing one mid-transition would be exactly the kind of
half-measure that later has to be undone. Instead:

- Task 3.4 Step 5 says to quit terminal tutor sessions before the first launch after this
  change, and `runIfNeeded` logs to `migration.log` so an overlap is at least diagnosable
  afterwards.
- `README.md` and the app's Settings screen state the constraint plainly: use one surface
  at a time.
- It is recorded as **FL-31** rather than silently accepted.

**Tradeoff:** a documented constraint is weaker than an enforced one, and a learner who
ignores it loses one session's scheduling. Naming it beats an unexamined lock that fails
open.

### D8 — Prompts and schemas come from `Bundle.module`

`ResourceLoader` currently prefers `<repo>/app/Sources/FluentApp/Resources/…` so a prompt
can be edited without a rebuild. An installed app has no repo. New precedence:
`$FLUENT_APP_RESOURCES` (explicit dev override) → `Bundle.module`.

**Tradeoff:** editing a prompt in the repo no longer changes the running installed app
unless the env var is set. Explicit beats a path that silently resolves differently on two
machines.

### D9 — Credentials move to Application Support, not Keychain

`Secrets` reads `$OPENROUTER_FLUENT`, then `<AppSupport>/Fluent/credentials.env` (0600).

**Tradeoff:** the Keychain is the better macOS answer — encrypted at rest, ACL'd per app.
It is also a larger change (Security framework, a first-run authorisation prompt, an
export path for `imgbench` which reads the same key from a file). A 0600 file in
Application Support is the same protection the repo `.env` had, at a path that survives
installation. Keychain is recorded as future work, not smuggled in here.

### D10 — The bundled fluent snapshot is produced by `git archive`

`make app` runs `git archive HEAD:fluent | tar -x -C Fluent.app/Contents/Resources/fluent`
and writes the repository SHA to `Contents/Resources/fluent-version.txt`.

`git archive HEAD:fluent` ships exactly the tracked files of that subtree at that commit:
no `.git`, no `__pycache__`, no `.venv`, and crucially no `data/*.json` a CLI run left
lying around. A `cp -R` would ship whatever happened to be on disk, including a learner's
databases.

**Tradeoff:** uncommitted edits under `fluent/` are silently not shipped. `make app`
therefore refuses to build while `fluent/` has uncommitted changes, rather than producing
a bundle that disagrees with the repository.

## Phase 0 — Safety Net

*Nothing in this phase changes the repository. Its only job is to make every later phase
reversible.*

### Task 0.1: Record the baseline and take a complete backup

**Files:**
- Create: `~/fluent-transition-backup/` (outside both repos, outside any git tree)

- [ ] **Step 1: Create the backup directory and record the date**

```bash
export FB="$HOME/fluent-transition-backup/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$FB"
echo "$FB" > "$HOME/fluent-transition-backup/LATEST"
cd /Users/r/prj/p/lang/fluent
```

- [ ] **Step 2: Bundle the entire git repository, all refs included**

```bash
git bundle create "$FB/repo-all-refs.bundle" --all
git for-each-ref --format='%(refname) %(objectname)' > "$FB/refs-before.txt"
git log --oneline --all > "$FB/log-before.txt"
git rev-parse HEAD > "$FB/head-before.txt"
```

`--all` is required: a plain `git bundle create ... main` would drop
`refs/claude/checkpoint-8e19f5f3`.

- [ ] **Step 3: Verify the bundle is complete and restorable**

```bash
git bundle verify "$FB/repo-all-refs.bundle"
rm -rf /tmp/bundle-check && git clone "$FB/repo-all-refs.bundle" /tmp/bundle-check
git -C /tmp/bundle-check log --oneline | wc -l   # expect 63
```

Expected: `The bundle records a complete history.` and `63`.

- [ ] **Step 4: Archive everything git does not track**

```bash
tar -czf "$FB/untracked-and-ignored.tgz" \
  TODO.md .env .claude/settings.local.json .claude/RESUME.md .git/info/exclude \
  results/fluent-learn-session-001.md results/fluent-review-session-002.md \
  tools/imgbench/samples 2>/dev/null || true
tar -tzf "$FB/untracked-and-ignored.tgz" | tee "$FB/untracked-listing.txt"
```

Expected: the listing names `TODO.md`, `.env`, `settings.local.json`, `RESUME.md`,
`.git/info/exclude` and both `results/*.md` files. `tools/imgbench/samples` may be absent — that is fine, it is
disposable; nothing else on the list is.

- [ ] **Step 5: Archive the live learner state and checksum every file**

```bash
tar -czf "$FB/fluent-data.tgz" -C "$HOME/.claude" fluent-data
find "$HOME/.claude/fluent-data" -type f -print0 | sort -z | xargs -0 shasum -a 256 \
  > "$FB/fluent-data.sha256"
wc -l < "$FB/fluent-data.sha256"
du -sh "$HOME/.claude/fluent-data"
```

Record both numbers in `$FB/baseline.txt`. Expected roughly: 1.7 MB.

- [ ] **Step 6: Snapshot the app's UserDefaults**

```bash
defaults export dev.fluent.app "$FB/userdefaults-dev.fluent.app.plist" 2>/dev/null \
  || echo "no defaults yet"
```

- [ ] **Step 7: Snapshot the databases as fluent itself reads them**

```bash
python3 .claude/hooks/read-db.py > "$FB/read-db-before.json"
python3 - <<'PY'
import json, os
p = os.path.join(os.environ["FB"], "read-db-before.json")
d = json.load(open(p))
prof = d["databases"]["learner_profile"]
print("streak", prof["current_streak_days"])
print("sessions", prof["total_sessions"])
print("sr_items", len(d["databases"]["spaced_repetition"]["items"]))
print("log_sessions", len(d["databases"]["session_log"]["sessions"]))
print("due", d["computed"]["due_reviews_count"])
print("next_session_id", d["computed"]["next_session_id"])
PY
```

Write that output to `$FB/baseline.txt`. **These six numbers are the contract**: they must
be identical after every later phase.

- [ ] **Step 8: Record the test baselines**

```bash
( cd app && swift test 2>&1 | tail -1 ) | tee -a "$FB/baseline.txt"
python3 -m unittest discover -s tests -q 2>&1 | tail -3 | tee -a "$FB/baseline.txt"
( cd tools/imgbench && uv run pytest -q 2>&1 | tail -1 ) | tee -a "$FB/baseline.txt"
```

Expected: `127 tests`, `Ran 19 tests … OK`, `28 passed`.

- [ ] **Step 9: Verify the backup by restoring it somewhere disposable**

```bash
rm -rf /tmp/restore-check && mkdir -p /tmp/restore-check
tar -xzf "$FB/fluent-data.tgz" -C /tmp/restore-check
( cd /tmp/restore-check && find fluent-data -type f -print0 | sort -z \
  | xargs -0 shasum -a 256 | sed "s#fluent-data#$HOME/.claude/fluent-data#" ) \
  | diff - "$FB/fluent-data.sha256" && echo "RESTORE VERIFIED"
```

Expected: `RESTORE VERIFIED`. **If this does not print, stop. The whole plan rests on it.**

**Verification for Task 0.1**
- [ ] `$FB` contains: `repo-all-refs.bundle`, `untracked-and-ignored.tgz`, `fluent-data.tgz`,
      `fluent-data.sha256`, `read-db-before.json`, `baseline.txt`, `refs-before.txt`.
- [ ] The bundle clone shows 63 commits.
- [ ] `RESTORE VERIFIED` printed.
- [ ] `baseline.txt` holds the six database numbers and the three test counts.

*No commit — this task touches nothing in the repo.*

---

## Phase 1 — Reshape the Repository

> **Ordering is load-bearing.** The filesystem is case-insensitive and
> `core.ignorecase=true`, so `Tests/` and `tests/` are the same path, as are `Tools/` and
> `tools/`. Fluent's files move out of the root **first** (Task 1.2); only then does the
> app move in (Task 1.3). Reversing them lands the Swift suite inside the Python one, with
> exit 0 and no warning.

### Task 1.1: Point the repository at perapera

**Files:** none — remotes only.

- [ ] **Step 1: Re-point `origin` and add `upstream`**

`origin` currently points at `m98/fluent`, the project this forked from. Pushing our
commits there is neither wanted nor possible; the fork relationship becomes `upstream`.

```bash
cd /Users/r/prj/p/lang/fluent
git remote set-url origin git@github.com:little-arhat/perapera.git
git remote add upstream https://github.com/m98/fluent
git remote -v
```

- [ ] **Step 2: Verify both ends resolve**

```bash
git ls-remote origin | head -3          # empty repo: no output, exit 0
git fetch upstream --quiet && git log --oneline -1 upstream/main
git merge-base HEAD upstream/main | xargs git log --oneline -1   # expect 86fb80f
```

- [ ] **Step 3: Confirm our divergence from upstream is what we think**

```bash
git diff --stat upstream/main..HEAD -- .claude data-examples docs/DB_SCRIPTS.md tests
```

Expected: 13 files, ~244 insertions — the streak fix, our tests, and small skill and doc
edits. This is the diff a submodule of pristine upstream would have thrown away.

- [ ] **Step 4: Commit the plan itself**

`TransitionPlan.md` is untracked. Phase 1 is about to move most of the repository; an
untracked file at the root is one more thing in the "invisible to git" category Phase 0
exists to catch.

```bash
git add TransitionPlan.md
git commit -m "docs: plan for reshaping this repo into perapera"
```

**Verification for Task 1.1**
- [ ] `git remote -v` shows `origin` to perapera and `upstream` to m98/fluent.
- [ ] `git merge-base HEAD upstream/main` is `86fb80f`.
- [ ] Working tree clean.

### Task 1.2: Move fluent into `fluent/`

**Files:**
- Move into `fluent/`: `AGENTS.md`, `CHANGELOG.md`, `CLAUDE.md`, `CONTRIBUTING.md`,
  `LEARNING_SYSTEM.md`, `PRACTICE.md`, `README.md`, `.claude-plugin/`, `.claude/hooks/`,
  `.claude/skills/`, `.claude/references/`, `.claude/settings.json`, `data/`,
  `data-examples/`, `docs/DB_SCRIPTS.md`, `tests/`
- Delete: `results/` (superseded by Task 2.2)
- Stay at the root: `LICENSE`, `.gitignore`, `.env.example`, `docs/research/`,
  `tools/imgbench/`, `app/`, `.claude/settings.local.json`

- [ ] **Step 1: Create the directory and move the tracked files**

```bash
cd /Users/r/prj/p/lang/fluent
mkdir -p fluent/.claude fluent/docs
git mv AGENTS.md CHANGELOG.md CLAUDE.md CONTRIBUTING.md LEARNING_SYSTEM.md \
       PRACTICE.md README.md fluent/
git mv .claude-plugin fluent/.claude-plugin
git mv .claude/hooks .claude/skills .claude/references .claude/settings.json fluent/.claude/
git mv data data-examples tests fluent/
git mv docs/DB_SCRIPTS.md fluent/docs/DB_SCRIPTS.md
git rm -r --quiet results
```

- [ ] **Step 2: Clear what `git mv` and `git rm` leave behind**

`git mv` moves tracked files only. `tests/` keeps an untracked, gitignored `__pycache__`,
so the directory survives on disk — and `git mv app/Tests Tests` in the next task would
then mean "move `app/Tests` **into** `tests/`", landing the Swift suite at `Tests/Tests/`.

```bash
rm -rf tests results data .pytest_cache
test ! -e tests && test ! -e results && test ! -e data && echo "CLEAR FOR THE APP MOVE"
```

Expected: `CLEAR FOR THE APP MOVE`. **If it does not print, stop.**

- [ ] **Step 3: Update `.gitignore` for the new locations**

One `.gitignore` at the root covers both halves. Replace the fluent-relative rules
(`/data/*.json`, `/results/*.md` and their negations) with:

```
# Fluent's own data directory. Real learner state lives in Application Support;
# anything appearing here is a stray from a CLI run.
/fluent/data/*.json
/fluent/data/*.json.backup-*
!/fluent/data/README.md
!/fluent/data/.gitkeep
```

Replace the Swift block (`/app/.build/`, `/app/Fluent.app/`, `/app/*.xcodeproj/`) with:

```
/.build/
/Fluent.app/
/*.xcodeproj/
```

and add:

```
# Machine-specific Claude Code settings (hold an absolute FLUENT_DATA_DIR)
/.claude/settings.local.json
/fluent/.claude/settings.local.json
```

Then untrack the local settings without deleting them:

```bash
git rm --cached .claude/settings.local.json
```

- [ ] **Step 4: Verify fluent still works from its new home**

```bash
FLUENT_DATA_DIR="$HOME/.claude/fluent-data" python3 fluent/.claude/hooks/read-db.py \
  | python3 -c 'import json,sys; c=json.load(sys.stdin)["computed"]; print(c["due_reviews_count"], c["next_session_id"])'
( cd fluent && python3 -m unittest discover -s tests -q 2>&1 | tail -3 )
```

Expected: the baseline due count and next session id from `$FB/baseline.txt`, then
`Ran 19 tests ... OK`. The tests resolve the repo root from `__file__`, so they follow the
move without edits.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: move fluent into fluent/"
```

**Verification for Task 1.2**
- [ ] `ls` shows `LICENSE`, `TODO.md`, `TransitionPlan.md`, `app`, `docs`, `fluent`,
      `tools`, and no `tests`/`data`/`results`/`LEARNING_SYSTEM.md`.
- [ ] `git log --follow --oneline fluent/.claude/hooks/update-db.py | wc -l` is at least 5 —
      history walks through the move.
- [ ] 19 Python tests pass from `fluent/`.
- [ ] `cd app && swift test` still reports 127 tests.

### Task 1.3: Move the app to the root

**Files:**
- Move: `app/Package.swift` to `Package.swift`; `app/Makefile` to `Makefile`;
  `app/README.md` to `README.md`; `app/Sources` to `Sources`; `app/Tests` to `Tests`;
  `app/Resources` to `Resources`; `app/Tools/make-icon.swift` to `tools/make-icon.swift`
- Modify: `Makefile`

- [ ] **Step 1: Re-assert the path is clear, then move**

`app/Tools/make-icon.swift` goes to lowercase `tools/` — the repo already has one, and a
second `Tools/` would be the same directory under a different name.

```bash
cd /Users/r/prj/p/lang/fluent
test ! -e tests || { echo "tests/ still exists; see Task 1.2 Step 2"; exit 1; }
test ! -e README.md || { echo "README.md still exists; fluent's should have moved"; exit 1; }
git mv app/Package.swift Package.swift
git mv app/Makefile Makefile
git mv app/README.md README.md
git mv app/Sources Sources
git mv app/Tests Tests
git mv app/Resources Resources
git mv app/Tools/make-icon.swift tools/make-icon.swift
git status --porcelain | grep -c '^R'
```

Expected: around 100 renames.

- [ ] **Step 2: Clear the build leftovers**

```bash
rm -rf app/.build app/Fluent.app app/_probes
rmdir app/Tools app 2>/dev/null || true
ls app 2>&1 | grep -c 'No such file'      # expect 1
```

- [ ] **Step 3: Fix the icon path in the Makefile**

```make
icon:
	swift tools/make-icon.swift Resources
```

- [ ] **Step 4: Build and test from the new root**

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | tail -1
```

Expected: clean build, `127 tests ... passed`. `Package.swift` needs no edit — SPM's default
target paths resolve at the new root, and the two `.copy("Resources/...")` rules are relative
to the target directory, which did not change.

- [ ] **Step 5: Commit and verify the history survived**

```bash
git add -A
git commit -m "refactor: move the macOS app to the repository root"
git log --follow --oneline Sources/FluentApp/AppModel.swift | tail -1
git log --oneline -- app/Sources/FluentApp/AppModel.swift | wc -l
```

Expected: the `--follow` tail names `03dd30b feat(app): macOS SwiftUI front end for Fluent`;
the old path still resolves in history.

**Verification for Task 1.3**
- [ ] `swift test` gives 127 passing tests from the repository root.
- [ ] `make app` produces `./Fluent.app` and it launches.
- [ ] `git log --follow Sources/FluentApp/AppModel.swift` reaches pre-move commits.

### Task 1.4: Write the app's `CLAUDE.md` (R3)

**Files:**
- Create: `CLAUDE.md`

- [ ] **Step 1: Write it**

The content is given in full in [Appendix A](#appendix-a--the-apps-claudemd), kept out of
line here so this task reads as one action.

- [ ] **Step 2: Commit and confirm the persona is gone**

```bash
git add CLAUDE.md
git commit -m "docs: a CLAUDE.md for the app, not the tutor"
claude -p "In one sentence, what kind of project is this?" --model haiku --tools "" --max-budget-usd 0.05
```

**Verification for Task 1.4**
- [ ] The probe describes a Swift/macOS app, not a language tutor.

### Task 1.5: App-development Claude settings

**Files:**
- Create: `.claude/settings.json`, `fluent/.claude/settings.local.json`
- Modify: `.claude/settings.local.json` (untracked)

- [ ] **Step 1: Write `.claude/settings.json`**

Fluent's four hooks now live under `fluent/`. Keep only the welcome banner, and let the
hook resolve the data directory from the environment. The old inline `PreCompact` hook is
dropped: it copied `$CLAUDE_PROJECT_DIR/data/*.json`, a path that has not existed since the
data moved, so it has been backing up nothing.

```json
{
  "description": "Perapera - app development settings",
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "description": "Show the active learner profile's stats",
            "command": "python3 \"$CLAUDE_PROJECT_DIR/fluent/.claude/hooks/session-start.py\" 2>/dev/null || true",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

The `|| true` matters: a developer with no profile yet must not get a failing hook on every
session start.

- [ ] **Step 2: Point both roots at the data directory**

Until Phase 3 migrates, the value stays `/Users/r/.claude/fluent-data`; Task 3.5 updates
both copies.

`.claude/settings.local.json` gains an `env` block with `FLUENT_DATA_DIR` and
`FLUENT_KIT_ROOT` (`/Users/r/prj/p/lang/fluent/fluent`), keeping its existing `permissions`
block untouched.

`fluent/.claude/settings.local.json` needs the same `FLUENT_DATA_DIR` — a session rooted
there reads only its own settings, and without it `data_dir()` falls through to a default
that Phase 3 renames away, silently creating an empty second profile.

```bash
git status --porcelain fluent/.claude/settings.local.json   # must be empty (ignored)
```

- [ ] **Step 3: Commit**

```bash
git add .claude/settings.json
git commit -m "chore(claude): app-development settings, fluent hooks via fluent/"
```

**Verification for Task 1.5**
- [ ] Both `settings.local.json` files are gitignored (`git status --porcelain` silent).
- [ ] A new Claude Code session in this directory prints the Fluent welcome banner.

### Task 1.6: Push to perapera

- [ ] **Step 1: Push**

```bash
cd /Users/r/prj/p/lang/fluent
git push -u origin main
git ls-remote origin main
```

- [ ] **Step 2: Back up the reshaped repository**

```bash
export FB="$(cat "$HOME/fluent-transition-backup/LATEST")"
git bundle create "$FB/perapera-after-phase1.bundle" --all
git bundle verify "$FB/perapera-after-phase1.bundle"
```

**Verification for Phase 1**
- [ ] `swift test` gives 127 passing tests.
- [ ] `cd fluent && python3 -m unittest discover -s tests -q` gives 19 passing tests.
- [ ] `python3 fluent/.claude/hooks/read-db.py` reports the baseline six numbers —
      **no learner state has moved yet.**
- [ ] `du -sh ~/.claude/fluent-data` unchanged from Phase 0.
- [ ] GitHub shows the reshaped tree.

---

## Phase 2 — Fluent-Side Changes

*Two changes to `fluent/` that later phases depend on. Both are written to stay mergeable
with upstream.*

### Task 2.1: Split the surface-independent methodology out of `LEARNING_SYSTEM.md`

**Files:**
- Create: `fluent/docs/METHODOLOGY.md`
- Modify: `fluent/LEARNING_SYSTEM.md`

**Interfaces:**
- Produces: `fluent/docs/METHODOLOGY.md` — the file Task 4.1's `teacher-context.json`
  names. Its path relative to the fluent root is the contract.

**Why:** the app's generator and grader have no tools and must never write files.
`LEARNING_SYSTEM.md` interleaves teaching principles with instructions to read `/data`,
greet the learner, present one question at a time, and update six databases — and still
names its slash commands `/dutch`. Feeding that whole document to a JSON generator hands it
a script for a different surface.

- [ ] **Step 1: Create `docs/METHODOLOGY.md` by moving these sections verbatim**

Move, do not copy — each section leaves `LEARNING_SYSTEM.md`:

| Section in `LEARNING_SYSTEM.md` | Becomes |
|---|---|
| `### Core Principles` (under Learning Methodology) | `## Core principles` |
| `### Adaptive Difficulty Selection` | `## Choosing difficulty` |
| `### Exercise Types by Skill` | `## Exercise types by skill` |
| `### Severity Levels` | `## Error severity` |
| `## Quality Checks Before Every Output` | `## Quality checks` |

Header:

```markdown
# Teaching Methodology

How Fluent teaches, independent of the surface it teaches through. The CLI skills and the
macOS app both follow this document; `LEARNING_SYSTEM.md` covers only how a terminal
session is run.
```

- [ ] **Step 2: Replace each moved section with a pointer**

```markdown
### Core Principles

See [`docs/METHODOLOGY.md`](docs/METHODOLOGY.md) — active recall, spaced repetition,
immediate feedback, interleaving, comprehensible input, desirable difficulty.
```

- [ ] **Step 3: Verify nothing was lost in the move**

```bash
cd /Users/r/prj/p/lang/fluent
git diff HEAD -- fluent/LEARNING_SYSTEM.md | grep '^-' | grep -v '^---' \
  | sed 's/^-//' | grep -v '^[[:space:]]*$' | sort -u > /tmp/removed.txt
sort -u fluent/docs/METHODOLOGY.md > /tmp/added.txt
comm -23 /tmp/removed.txt /tmp/added.txt
```

Expected: only the lines deliberately rewritten as pointers. Any teaching content in that
output is a line you dropped — put it back.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs(fluent): separate teaching methodology from CLI choreography"
```

**Verification for Task 2.1**
- [ ] `grep -nE '/data|update-db|/dutch|one at a time|[Gg]reet' fluent/docs/METHODOLOGY.md`
      returns nothing.
- [ ] `fluent/LEARNING_SYSTEM.md` links to `docs/METHODOLOGY.md` at least five times.
- [ ] 19 Python tests still pass.

### Task 2.2: Send CLI session transcripts to the data directory

**Files:**
- Modify: `fluent/.claude/hooks/fluent_paths.py`, `fluent/.claude/hooks/read-db.py`
- Modify (write transcripts — five, not six):
  `fluent/.claude/skills/{fluent-learn,fluent-writing,fluent-speaking,fluent-reading,fluent-review}/SKILL.md`
- Modify (reference the location): `fluent/.claude/skills/fluent-session-analyzer/SKILL.md`
  (reads them), `fluent/.claude/skills/fluent-feedback-formatter/SKILL.md:97`,
  `fluent/.claude/references/session-file-template.md:3,8` — the canonical template the five
  writers point at; missing it leaves the format doc contradicting the skills
- Modify (prose): `fluent/PRACTICE.md`, `fluent/AGENTS.md`, `fluent/README.md`,
  `fluent/CLAUDE.md`, `fluent/LEARNING_SYSTEM.md`
- Modify: `fluent/tests/test_update_db.py`

`fluent-vocab` writes no transcript and needs no change.

**Interfaces:**
- Produces: `fluent_paths.results_dir()` and `ensure_results_dir()`, both returning `Path`,
  mirroring the existing `backups_dir()` / `ensure_backups_dir()` pair.

**Why:** five skills write `results/session-*.md` relative to the project directory. That is
learner state landing inside a git repository — exactly what R6 forbids — and it collides
the moment there is more than one profile.

- [ ] **Step 1: Write the failing test**

Append `ResultsDirTests` to `fluent/tests/test_update_db.py`. It must:

1. Save and restore `os.environ["FLUENT_DATA_DIR"]` around each case. Without the restore
   it leaks into `UpdateDbSmokeTest`, which runs `python3 update-db.py` with no `env=`,
   inherits it, and writes every one of its cases into this directory instead of its own
   fixture. Alphabetical ordering puts `ResultsDirTests` first, so the leak is not
   hypothetical.
2. Use `tempfile.mkdtemp()` and compare against `pathlib.Path(base).resolve()` — `data_dir()`
   calls `.resolve()`, and on macOS `/tmp` is a symlink to `/private/tmp`, so a literal
   string comparison fails for a reason unrelated to the feature.
3. `importlib.reload(fluent_paths)` per case: every resolver is `@lru_cache`d.
4. Use `REPO_ROOT` — the constant in this file. `REPO` belongs to `test_stdlib_only.py`.

Two cases: `results_dir()` equals `<data dir>/results`, and `ensure_results_dir()` creates
a missing one.

- [ ] **Step 2: Run it and watch it fail**

```bash
cd /Users/r/prj/p/lang/fluent/fluent
python3 -m unittest discover -s tests -q 2>&1 | tail -5
```

Expected: `AttributeError: module 'fluent_paths' has no attribute 'results_dir'`.

- [ ] **Step 3: Add the resolvers**

In `fluent/.claude/hooks/fluent_paths.py`, after `ensure_backups_dir()`, add
`results_dir()` (decorated `@lru_cache(maxsize=1)`, returning `data_dir() / "results"`) and
`ensure_results_dir()` (which `mkdir(parents=True, exist_ok=True)`s it and returns it) —
the same shape as the backups pair directly above. The docstring should say why they nest
inside `data_dir`: transcripts are learner state and must follow the learner rather than
the checkout. Update the module docstring's path-resolution summary to mention them.

- [ ] **Step 4: Run the tests and watch them pass**

```bash
python3 -m unittest discover -s tests -q 2>&1 | tail -3
```

Expected: `Ran 21 tests ... OK`.

- [ ] **Step 5: Point the skills and docs at the new location**

Replace every instruction naming `/results/` or `results/session-*.md` with a direction to
write into `$FLUENT_DATA_DIR/results/`, and — for when that variable is unset — a one-line
`python3 -c` that imports `ensure_results_dir` from `.claude/hooks` and prints it. Do not
introduce a `jq` dependency: fluent is stdlib-only Python and must run on a learner's
machine unprepared.

Also expose the resolved directory in `read-db.py`'s `computed` block as
`"data_dir": str(DATA_DIR)`.

- [ ] **Step 6: Move the two existing transcripts and re-baseline**

```bash
cd /Users/r/prj/p/lang/fluent
export FB="$(cat "$HOME/fluent-transition-backup/LATEST")"
mkdir -p "$HOME/.claude/fluent-data/results"
tar -xzf "$FB/untracked-and-ignored.tgz" -O results/fluent-learn-session-001.md \
  > "$HOME/.claude/fluent-data/results/fluent-learn-session-001.md"
tar -xzf "$FB/untracked-and-ignored.tgz" -O results/fluent-review-session-002.md \
  > "$HOME/.claude/fluent-data/results/fluent-review-session-002.md"
ls "$HOME/.claude/fluent-data/results/"    # expect 2 files

find "$HOME/.claude/fluent-data" -type f -print0 | sort -z | xargs -0 shasum -a 256 \
  > "$FB/fluent-data.sha256.post-2.2"
diff <(awk '{print $1}' "$FB/fluent-data.sha256" | sort) \
     <(awk '{print $1}' "$FB/fluent-data.sha256.post-2.2" | sort) | grep -c '^>'
```

Those two files change the data directory, so the Phase-0 digest manifest no longer
describes it. Re-capture, or every later "no state lost" check fails for a reason that is
not state loss. Expected: `2` — exactly the two transcripts, nothing else changed.

- [ ] **Step 7: Commit and push**

```bash
git add -A
git commit -m "feat(fluent): keep session transcripts with the learner, not the checkout"
git push
```

**Verification for Phase 2**
- [ ] 21 Python tests pass.
- [ ] `grep -rn '/results/\|results/session' fluent/.claude fluent/*.md | grep -v FLUENT_DATA_DIR`
      returns nothing.
- [ ] `swift test` gives 127 passing tests.
- [ ] `python3 fluent/.claude/hooks/read-db.py` still reports the baseline numbers.

---

## Phase 3 — Separate State from the Repository (R6, R7 foundations)

### Task 3.1: Profile slugs and migration decisions, as pure values

**Files:**
- Create: `Sources/FluentCore/Profile.swift`
- Test: `Tests/FluentCoreTests/ProfileTests.swift`

**Interfaces:**
- Produces: `LearnerIdentity(name:targetLanguage:)`, `ProfileSlug.make(_:)`,
  `ProfileSlug.unique(_:taken:)`, `MigrationDecision.decide(legacyHasProfile:existingSlugs:identity:)`.
  Task 3.2 (`Locations`), 3.3 (`ProfileStore`) and 3.4 (`Migrator`) consume all four.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import FluentCore

// A profile id is a directory name a person will read in Finder and a path the
// terminal will have to quote. It has to be stable, obvious, and free of
// anything a shell or a filesystem treats specially.

@Test func slugIsNameAndLanguage() {
    #expect(ProfileSlug.make(LearnerIdentity(name: "Roma", targetLanguage: "Japanese"))
            == "roma-japanese")
}

@Test func slugFlattensSpacesPunctuationAndCase() {
    #expect(ProfileSlug.make(LearnerIdentity(name: "Ana María", targetLanguage: "Brazilian Portuguese"))
            == "ana-maria-brazilian-portuguese")
}

@Test func slugSurvivesANameWithNothingLatinInIt() {
    // A slug that collapses to nothing would name every such profile the same
    // directory, which is a data-loss bug wearing a naming bug's clothes.
    let slug = ProfileSlug.make(LearnerIdentity(name: "ローマ", targetLanguage: "日本語"))
    #expect(!slug.isEmpty)
    #expect(!slug.contains("/"))
    #expect(!slug.contains(" "))
}

@Test func slugIsStableAcrossRuns() {
    // The fallback must not be `String.hashValue`: Swift seeds it per process, so
    // a learner with no ASCII in their name would get a fresh directory every
    // launch and lose their history to an orphan each time. This asserts the
    // value, not merely that two calls in one process agree.
    #expect(ProfileSlug.make(LearnerIdentity(name: "ローマ", targetLanguage: "日本語"))
            == "profile-3acccf77d146")
}

@Test func uniqueSuffixesOnlyOnCollision() {
    let identity = LearnerIdentity(name: "Roma", targetLanguage: "Japanese")
    #expect(ProfileSlug.unique(identity, taken: []) == "roma-japanese")
    #expect(ProfileSlug.unique(identity, taken: ["roma-japanese"]) == "roma-japanese-2")
    #expect(ProfileSlug.unique(identity, taken: ["roma-japanese", "roma-japanese-2"])
            == "roma-japanese-3")
}

@Test func migrationRunsOnceAndOnlyWithSomethingToMove() {
    let roma = LearnerIdentity(name: "Roma", targetLanguage: "Japanese")
    #expect(MigrationDecision.decide(legacyHasProfile: true, existingSlugs: [], identity: roma)
            == .migrate(slug: "roma-japanese"))
    // Already migrated: the profile exists, so a second copy would resurrect
    // whatever the old directory still held.
    #expect(MigrationDecision.decide(legacyHasProfile: true,
                                     existingSlugs: ["roma-japanese"], identity: roma)
            == .skip("already migrated"))
    #expect(MigrationDecision.decide(legacyHasProfile: false, existingSlugs: [], identity: nil)
            == .skip("nothing to migrate"))
    // A legacy directory whose profile will not parse is a case for a human,
    // not for a guess about whose data it is.
    #expect(MigrationDecision.decide(legacyHasProfile: true, existingSlugs: [], identity: nil)
            == .skip("legacy profile unreadable"))
}
```

- [ ] **Step 2: Run them and watch them fail**

```bash
swift test --filter slugIsNameAndLanguage 2>&1 | tail -5
```

Expected: `cannot find 'ProfileSlug' in scope`.

- [ ] **Step 3: Implement**

```swift
import CryptoKit
import Foundation

/// Who a profile belongs to, and what they are learning.
///
/// One learner learning two languages is two profiles: `learner-profile.json`
/// holds exactly one `target_language`, and the six databases are keyed to it.
public struct LearnerIdentity: Equatable, Sendable {
    public let name: String
    public let targetLanguage: String

    public init(name: String, targetLanguage: String) {
        self.name = name
        self.targetLanguage = targetLanguage
    }
}

/// The directory name a profile lives under.
///
/// Human-readable on purpose: this is a path the learner will see in Finder and
/// paste into a shell. A UUID would be easier to generate and worse to live with.
public enum ProfileSlug {
    public static func make(_ identity: LearnerIdentity) -> String {
        let joined = "\(identity.name)-\(identity.targetLanguage)"
        let folded = joined.folding(options: [.diacriticInsensitive, .widthInsensitive],
                                   locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        var slug = ""
        var lastWasDash = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                slug.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash, !slug.isEmpty {
                slug.append("-")
                lastWasDash = true
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        // A name with no Latin characters folds away entirely — `ローマ` / `日本語`
        // is not a hypothetical for this app. The fallback must be a *stable*
        // digest: `String.hashValue` is seeded per process, so it would name a
        // new directory on every launch and orphan the learner's data each time.
        guard slug.isEmpty else { return slug }
        let digest = SHA256.hash(data: Data(joined.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "profile-\(digest.prefix(12))"
    }

    public static func unique(_ identity: LearnerIdentity, taken: Set<String>) -> String {
        let base = make(identity)
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }
}

/// Whether the one-shot move out of `~/.claude/fluent-data` should run.
///
/// A value, not a side effect, so the rule is testable without a filesystem and
/// readable without tracing the copy.
public enum MigrationDecision: Equatable, Sendable {
    case migrate(slug: String)
    case skip(String)

    public static func decide(
        legacyHasProfile: Bool, existingSlugs: Set<String>, identity: LearnerIdentity?
    ) -> MigrationDecision {
        guard legacyHasProfile else { return .skip("nothing to migrate") }
        guard let identity else { return .skip("legacy profile unreadable") }
        let slug = ProfileSlug.make(identity)
        guard !existingSlugs.contains(slug) else { return .skip("already migrated") }
        return .migrate(slug: slug)
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

The expected digest is a real SHA-256 prefix. Compute it rather than trusting the value
above, then run the suite:

```bash
python3 -c "import hashlib; print('profile-' + hashlib.sha256('ローマ-日本語'.encode()).hexdigest()[:12])"
swift test --filter "slug|migrationRuns" 2>&1 | tail -3
swift test 2>&1 | tail -1     # expect 133 tests
```

Then confirm stability across process boundaries, which one test run cannot:

```bash
for i in 1 2 3; do swift test --filter slugIsStableAcrossRuns 2>&1 | tail -1; done
```

Expected: three identical passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/FluentCore/Profile.swift Tests/FluentCoreTests/ProfileTests.swift
git commit -m "feat(core): profile slugs and the migration decision, as values"
```

### Task 3.2: Replace `Paths` with `Locations`

**Files:**
- Delete: `Sources/FluentApp/Paths.swift`
- Create: `Sources/FluentApp/Locations.swift`

**Interfaces:**
- Produces: `Locations.appSupport: URL`, `Locations.profilesRoot: URL`,
  `Locations.credentialsFile: URL`, `Locations.migrationLog: URL`,
  `Locations.legacyDataDirectory: URL`, `Locations.kitRoot() -> URL?`,
  `Locations.toolSearchPaths: [String]`.

- [ ] **Step 1: Write `Locations.swift`**

```swift
import Foundation

/// Where things are, now that "where things are" is four questions rather than one.
///
/// `Paths.dataDirectory(pluginRoot:)` answered all four with one setting: the repo
/// held the databases, the scripts, the prompts and the key. An installed app has
/// no repo, and a learner may have more than one profile, so each concept gets its
/// own resolver and its own override.
enum Locations {
    /// `~/Library/Application Support/Fluent`. Everything mutable lives under here.
    static var appSupport: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support")
        return base.appending(path: "Fluent")
    }

    static var profilesRoot: URL { appSupport.appending(path: "profiles") }
    static var credentialsFile: URL { appSupport.appending(path: "credentials.env") }
    static var migrationLog: URL { appSupport.appending(path: "migration.log") }

    /// Where learner state lived before 2026-09. Read once, by the migrator.
    static var legacyDataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/fluent-data")
    }

    /// The Fluent kit: `update-db.py`, `read-db.py`, the DB templates and the
    /// methodology the teacher is briefed with.
    ///
    /// Nil rather than a guess. A wrong kit path fails at the first subprocess with
    /// an unreadable error; nil fails at launch with a sentence that says what to do.
    static func kitRoot() -> URL? {
        let env = ProcessInfo.processInfo.environment
        if let override = env["FLUENT_KIT_ROOT"], !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            return isKit(url) ? url : nil
        }
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appending(path: "fluent")
            if isKit(bundled) { return bundled }
        }
        return nil
    }

    /// A directory is the fluent root if it can do the two things the app needs of it.
    private static func isKit(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.appending(path: ".claude/hooks/update-db.py").path)
            && fm.fileExists(atPath: url.appending(path: "data-examples").path)
    }

    /// Homebrew and the usual installs, for locating `claude` when the app's
    /// inherited PATH is the minimal GUI one.
    static let toolSearchPaths = [
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".brew/bin").path,
        "/opt/homebrew/bin",
        "/usr/local/bin",
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin").path,
    ]
}
```

- [ ] **Step 2: Remove the old file and build**

```bash
git rm Sources/FluentApp/Paths.swift
swift build 2>&1 | grep -c 'error:'
```

Expected: several errors naming `Paths` — `AppModel.swift` is the only consumer. Leave
them; Task 3.3 fixes them in the same edit that introduces `ProfileStore`.

### Task 3.3: `ProfileStore` — list, create, switch (R7)

**Files:**
- Create: `Sources/FluentApp/ProfileStore.swift`
- Modify: `Sources/FluentApp/AppModel.swift`, `Sources/FluentApp/FluentStore.swift`,
  `Sources/FluentApp/LessonService.swift` (the `ResourceLoader` half),
  `Sources/FluentApp/Secrets.swift`,
  `Sources/FluentApp/Views/ArchiveView.swift` (holds `SettingsView`, lines 111-230),
  `Sources/FluentApp/Views/HomeView.swift` (lines 279, 295),
  `Sources/FluentApp/Views/ImagesView.swift` (line 61, the `.env` message),
  `Sources/FluentApp/ImagePipeline.swift` (line 42, the `.env` message)

**Interfaces:**
- Consumes: `LearnerIdentity`, `ProfileSlug` (Task 3.1); `Locations` (Task 3.2).
- Produces: `ProfileStore.Profile(id:identity:directory:)`, `ProfileStore.list() -> [Profile]`,
  `ProfileStore.active -> Profile?`, `ProfileStore.activate(_ id: String)`,
  `ProfileStore.create(identity:currentLevel:targetLevel:nativeLanguage:explanationLanguage:kitRoot:) throws -> Profile`.
  Task 5.1's UI consumes all of them.

- [ ] **Step 1: Write `ProfileStore.swift`**

```swift
import Foundation
import FluentCore

/// The learner profiles on this machine.
///
/// The list is derived by scanning `profiles/*/learner-profile.json` rather than
/// kept in an index. An index is a second answer to "which profiles exist", and
/// the directory is the first one.
@MainActor
final class ProfileStore {
    struct Profile: Identifiable, Equatable {
        let id: String
        let identity: LearnerIdentity
        let directory: URL
    }

    enum Failure: LocalizedError {
        case noKit
        case templateMissing(String)

        var errorDescription: String? {
            switch self {
            case .noKit:
                "Couldn't find the Fluent kit. Reinstall the app, or set FLUENT_KIT_ROOT."
            case let .templateMissing(name):
                "The kit is missing \(name); it can't create a profile without it."
            }
        }
    }

    /// The six files `update-db.py` owns, and the templates they start from.
    static let databases = [
        "learner-profile.json": "learner-profile-template.json",
        "progress-db.json": "progress-db-template.json",
        "mistakes-db.json": "mistakes-db-template.json",
        "mastery-db.json": "mastery-db-template.json",
        "spaced-repetition.json": "spaced-repetition-template.json",
        "session-log.json": "session-log-template.json",
    ]

    private let defaultsKey = "activeProfileID"

    func list() -> [Profile] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: Locations.profilesRoot, includingPropertiesForKeys: [.isDirectoryKey])
        else { return [] }

        return entries.compactMap { directory -> Profile? in
            let profileFile = directory.appending(path: "learner-profile.json")
            guard let data = try? Data(contentsOf: profileFile),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let learner = json["learner"] as? [String: Any],
                  let name = learner["name"] as? String,
                  let language = learner["target_language"] as? String
            else { return nil }
            return Profile(
                id: directory.lastPathComponent,
                identity: LearnerIdentity(name: name, targetLanguage: language),
                directory: directory)
        }
        .sorted { $0.id < $1.id }
    }

    /// Which profile is open on this Mac. A per-machine preference, not learner
    /// state, so it lives in UserDefaults rather than in Application Support.
    var activeID: String? {
        get { UserDefaults.standard.string(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// Falls back to the first profile when the stored id names one that is gone,
    /// so deleting a directory in Finder degrades to "opens the other one" rather
    /// than "the app is empty and won't say why".
    var active: Profile? {
        let profiles = list()
        if let id = activeID, let match = profiles.first(where: { $0.id == id }) {
            return match
        }
        return profiles.first
    }

    func activate(_ id: String) { activeID = id }

    /// Creates a profile from fluent's own templates, so fluent stays the single
    /// authority on what a database looks like.
    func create(
        identity: LearnerIdentity, currentLevel: String, targetLevel: String,
        nativeLanguage: String, explanationLanguage: String, kitRoot: URL?
    ) throws -> Profile {
        guard let kitRoot else { throw Failure.noKit }
        let fm = FileManager.default
        let slug = ProfileSlug.unique(identity, taken: Set(list().map(\.id)))
        let directory = Locations.profilesRoot.appending(path: slug)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        for (target, template) in Self.databases {
            let source = kitRoot.appending(path: "data-examples/\(template)")
            guard fm.fileExists(atPath: source.path) else {
                throw Failure.templateMissing(template)
            }
            try fm.copyItem(at: source, to: directory.appending(path: target))
        }
        try personalise(directory: directory, identity: identity,
                        currentLevel: currentLevel, targetLevel: targetLevel,
                        nativeLanguage: nativeLanguage,
                        explanationLanguage: explanationLanguage)
        return Profile(id: slug, identity: identity, directory: directory)
    }

    /// Fills the learner block the template leaves blank.
    ///
    /// The template ships placeholders — `{YOUR_NATIVE_LANGUAGE}`,
    /// `{OTHER_LANGUAGES_YOU_SPEAK}`, `{conversational|academic|immersive|balanced}`,
    /// `{travel|work|exam|living_abroad|personal|family}`, three `{YYYY-MM-DD}` —
    /// and `LessonService.buildGenerationPrompt` substitutes `native_language`,
    /// `other_languages`, `motivation` and `learning_style` straight into the
    /// prompt. Leaving any of them means every lesson for a new profile is
    /// generated against a literal `{YOUR_NATIVE_LANGUAGE}`. The two the app does
    /// not ask for are dropped rather than guessed, and `verify` refuses anything
    /// still in brace form.
    private func personalise(
        directory: URL, identity: LearnerIdentity, currentLevel: String, targetLevel: String,
        nativeLanguage: String, explanationLanguage: String
    ) throws {
        let url = directory.appending(path: "learner-profile.json")
        let data = try Data(contentsOf: url)
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var learner = json["learner"] as? [String: Any]
        else { return }

        learner["name"] = identity.name
        learner["target_language"] = identity.targetLanguage
        learner["current_level"] = currentLevel
        learner["target_level"] = targetLevel
        learner["native_language"] = nativeLanguage
        learner["explanation_language"] = explanationLanguage
        // Present in the live profile, absent from the template.
        learner["other_languages"] = []
        learner["bridge_languages"] = []
        learner["learning_style"] = "balanced"
        learner["motivation"] = "personal"
        json["learner"] = learner

        let today = ISO8601DateFormatter()
        today.formatOptions = [.withFullDate]
        json["profile_created"] = today.string(from: Date())
        json["last_updated"] = today.string(from: Date())

        let out = try JSONSerialization.data(
            withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try out.write(to: url, options: .atomic)
        try refuseLeftoverPlaceholders(in: out)
    }

    /// A `"{LIKE_THIS}"` value that survives into a live profile reaches the model
    /// as literal text and is invisible in the UI. Fail at creation, where it can
    /// still be fixed, rather than in a lesson three days later.
    private func refuseLeftoverPlaceholders(in data: Data) throws {
        let text = String(decoding: data, as: UTF8.self)
        let pattern = try NSRegularExpression(pattern: #""\{[^"]*\}""#)
        let found = pattern.matches(
            in: text, range: NSRange(text.startIndex..., in: text))
        guard found.isEmpty else {
            throw Failure.unfilledTemplate(found.compactMap {
                Range($0.range, in: text).map { String(text[$0]) }
            })
        }
    }
}
```

Add the case to `Failure`:

```swift
        case unfilledTemplate([String])
        // ...
            case let .unfilledTemplate(fields):
                "The kit's profile template has fields this app doesn't fill: "
                    + fields.joined(separator: ", ")
                    + ". Create the profile with /fluent-setup in the terminal instead."
```

- [ ] **Step 2: Rewire `AppModel`**

Replace the `pluginRoot` property and its `UserDefaults` round trip with:

```swift
    let profiles = ProfileStore()
    private(set) var activeProfile: ProfileStore.Profile?
    let kitRoot: URL? = Locations.kitRoot()

    var dataDirectory: URL? { activeProfile?.directory }

    /// Switching is a change of subject, not a reload. Everything derived from the
    /// previous learner has to go first, or their name sits in the title bar and a
    /// half-open lesson id resolves to "that lesson isn't here any more".
    func switchProfile(to id: String) async {
        profiles.activate(id)
        activeProfile = profiles.active
        snapshot = nil
        records = []
        savedItems = SavedItems()
        pictures = []
        spending = SpendLog()
        unreadableLessons = []
        error = nil
        screen = .home
        returnTo = nil
        rebuildServices()
        await refresh()
    }
```

In `init()`, drop the `pluginRoot` lookup and set `activeProfile = profiles.active`; keep
every other `UserDefaults`-backed preference exactly as it is.

**`lessonStore` must become optional, and that is not a small edit.** It is declared
`private(set) var lessonStore: LessonStore` (`AppModel.swift:175`) and assigned
unconditionally in `init()` (`:195`). An `init` cannot `guard … else { return }` before all
stored properties are initialised, so "no profile yet" — a real state on a fresh install —
cannot be expressed with the current type. Change the declaration to:

```swift
    private(set) var lessonStore: LessonStore?
```

and delete its assignment from `init()`; `rebuildServices()` becomes the only place it is
set. Every use then needs unwrapping. The full list, from `rg -n 'lessonStore' Sources`:

| Site | Handling |
|---|---|
| `init()` `:195` | delete the assignment |
| `rebuildServices()` `:251` | assign, or set `nil` when there is no profile |
| `refresh()` — `loadSavedItems`, `loadPictures`, `loadSpending`, `loadAll` | already `try?`-guarded; prefix with `guard let lessonStore else { return }` |
| `persistSavedItems()`, `noteSpend(_:_:_:)`, `update(_:)`, `delete(id:)` | `guard let lessonStore else { return }` |
| `makePicture(_:)` — `saveImage`, `savePictures` | inside the existing `do` block; `guard` at the top beside the `canGenerateImages` check |
| `imageURL(lessonId:fileName:)`, `imageURL(for:exercise:)` | `guard let lessonStore else { return nil }` |
| `generate(…)`, `practice(…)`, `submit(id:)` | already `guard let lessons else { return }`; extend to `guard let lessons, let lessonStore else { return }` |
| `deleteUnreadableLessons()` `:578` | uses `dataDirectory`, now optional — `guard let directory = dataDirectory else { return }` |

`dataDirectory` becoming optional also breaks **three view sites the compiler will find**:
`Views/HomeView.swift:279` and `:295` (the "where are my lessons" text and its Finder
button) and `Views/ArchiveView.swift:147` (the Settings path row). Render "—" when nil.

And `pluginRoot` has **two view call sites** that must go with it:
`Views/ArchiveView.swift:140` (`Text(model.pluginRoot.path)`) and `:225`
(`model.pluginRoot = url`, in `chooseRepo()`). Delete `chooseRepo()` and its button
outright — there is no repo to choose any more. In `rebuildServices()`,
replace `pluginRoot:` with the two explicit values:

```swift
    func rebuildServices() {
        guard let directory = dataDirectory, let kitRoot else {
            lessonStore = nil
            lessons = nil
            return
        }
        let store = LessonStore(dataDirectory: directory)
        lessonStore = store
        lessons = LessonService(
            claude: ClaudeClient(config: .init(
                executable: claudePath, model: model, workingDirectory: directory)),
            store: FluentStore(config: .init(kitRoot: kitRoot, dataDirectory: directory)),
            lessons: store,
            resources: ResourceLoader(),
            kitRoot: kitRoot,
            images: openRouterKey.isEmpty ? nil
                : ImagePipeline(config: .init(apiKey: openRouterKey)))
    }
```

`ClaudeClient` is untouched in this task. The system prompt is threaded in **Task 4.2
Step 3**, where it becomes a per-`request` argument rather than a `Config` field — a
generation and a grading call are briefed differently, so it cannot live on the client.
Add `let kitRoot: URL` to `LessonService`'s stored properties now, so Task 4.2 has it.

- [ ] **Step 3: Rewire `FluentStore.Config`**

```swift
    struct Config {
        var kitRoot: URL
        var dataDirectory: URL
        var python: String = "/usr/bin/python3"

        var readScript: URL { kitRoot.appending(path: ".claude/hooks/read-db.py") }
        var updateScript: URL { kitRoot.appending(path: ".claude/hooks/update-db.py") }
    }
```

and make the environment explicit — the old comment said `FLUENT_DATA_DIR` was left unset
so the scripts would apply their own precedence, which stops being true the moment a
second profile exists:

```swift
    /// Both coordinates are stated. Leaving `FLUENT_DATA_DIR` unset would let the
    /// scripts fall back to `~/.claude/fluent-data`, which after profiles is not
    /// "the same databases the CLI uses" but "some other learner's".
    private func environmentForScripts() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["CLAUDE_PLUGIN_ROOT"] = config.kitRoot.path
        env["FLUENT_DATA_DIR"] = config.dataDirectory.path
        return env
    }
```

- [ ] **Step 4: Rewire `ResourceLoader` (D8)**

```swift
/// Loads the prompt and schema files that ship with the app.
///
/// The bundle is the source. An installed app has no repository to prefer, and a
/// path that silently resolves differently on two machines is worse than a rebuild.
struct ResourceLoader {
    /// Set `FLUENT_APP_RESOURCES` to the repo's `Sources/FluentApp/Resources` to
    /// edit a prompt without rebuilding.
    var override: URL? = ProcessInfo.processInfo.environment["FLUENT_APP_RESOURCES"]
        .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }

    func text(_ relativePath: String) throws -> String {
        if let override,
           let text = try? String(contentsOf: override.appending(path: relativePath),
                                  encoding: .utf8) {
            return text
        }
        let name = (relativePath as NSString).lastPathComponent
        let directory = (relativePath as NSString).deletingLastPathComponent
        // nil, not "": `teacher-context.json` sits at the resource root, and an
        // empty subdirectory string is not the same as no subdirectory.
        guard let url = Bundle.module.url(
            forResource: (name as NSString).deletingPathExtension,
            withExtension: (name as NSString).pathExtension,
            subdirectory: directory.isEmpty ? nil : directory)
        else { throw CocoaError(.fileNoSuchFile) }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
```

Update the two `ResourceLoader(pluginRoot:)` call sites to `ResourceLoader()`.

- [ ] **Step 5: Rewire `Secrets` (D9)**

```swift
enum Secrets {
    static let openRouterKey = "OPENROUTER_FLUENT"

    /// Environment first, then a 0600 file in Application Support. The repo `.env`
    /// is gone: an installed app has no repo, and a key that only works from a
    /// checkout is a key that stops working when the app is installed.
    static func openRouter() -> String {
        if let value = ProcessInfo.processInfo.environment[openRouterKey], !value.isEmpty {
            return value
        }
        guard let contents = try? String(contentsOf: Locations.credentialsFile,
                                         encoding: .utf8) else { return "" }
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { continue }
            let withoutExport = trimmed.hasPrefix("export ")
                ? String(trimmed.dropFirst("export ".count)) : trimmed
            guard withoutExport.hasPrefix("\(openRouterKey)=") else { continue }
            return String(withoutExport.dropFirst(openRouterKey.count + 1))
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }
        return ""
    }

    /// Writes the key, owner-readable only.
    static func setOpenRouter(_ value: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Locations.appSupport, withIntermediateDirectories: true)
        try "\(openRouterKey)=\(value)\n".write(
            to: Locations.credentialsFile, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o600],
                             ofItemAtPath: Locations.credentialsFile.path)
    }
}
```

Update `AppModel.openRouterKey` to `Secrets.openRouter()` and the two error strings that
say "add OPENROUTER_FLUENT to .env in the Fluent repo" to name Settings instead.

- [ ] **Step 6: Build and test**

```bash
swift build 2>&1 | grep 'error:' | head
swift test 2>&1 | tail -1     # expect 133 tests
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(app): four locations instead of one pluginRoot

Kit root, profile directory, app resources and credentials were one setting
that only resolved correctly from a git checkout. Each gets its own resolver
and its own override, and FLUENT_DATA_DIR is now stated rather than inferred."
```

### Task 3.4: Migrate the live state, verified byte for byte (R6)

**Files:**
- Create: `Sources/FluentApp/Migrator.swift`
- Modify: `Sources/FluentApp/AppModel.swift` (call it once at launch)

**Interfaces:**
- Consumes: `MigrationDecision`, `LearnerIdentity` (3.1); `Locations` (3.2);
  `ProfileStore` (3.3).
- Produces: `Migrator.runIfNeeded() throws -> String?` — a sentence to show the learner,
  or nil when nothing happened — and `Migrator.resumeIfInterrupted() throws`, which must
  be called first.

- [ ] **Step 1: Write `Migrator.swift`**

```swift
import Foundation
import CryptoKit
import FluentCore

/// The one-shot move out of `~/.claude/fluent-data`.
///
/// Copies, verifies every file's digest, and only then retires the old directory
/// by renaming it. The rename is the point: both the app and the CLI resolve the
/// old path as a default, and a readable copy left behind is an invitation to a
/// split brain where the terminal advances one set of databases and the app another.
@MainActor
struct Migrator {
    let profiles: ProfileStore

    enum Failure: LocalizedError {
        case verificationFailed([String])
        var errorDescription: String? {
            switch self {
            case let .verificationFailed(files):
                "The copy didn't match for: \(files.joined(separator: ", ")). "
                    + "Nothing was removed; your data is still in ~/.claude/fluent-data."
            }
        }
    }

    func runIfNeeded() throws -> String? {
        let legacy = Locations.legacyDataDirectory
        let identity = readIdentity(at: legacy.appending(path: "learner-profile.json"))
        let decision = MigrationDecision.decide(
            legacyHasProfile: FileManager.default.fileExists(
                atPath: legacy.appending(path: "learner-profile.json").path),
            existingSlugs: Set(profiles.list().map(\.id)),
            identity: identity)

        guard case let .migrate(slug) = decision else { return nil }

        let destination = Locations.profilesRoot.appending(path: slug)
        try FileManager.default.createDirectory(
            at: Locations.profilesRoot, withIntermediateDirectories: true)
        // A crash between the copy and the retire would leave a populated profile
        // AND a readable legacy directory, and `decide` would then say "already
        // migrated" forever -- the split-brain D6 forbids, reached by crashing
        // rather than by choosing. The marker makes the half-finished state
        // nameable, and `resumeIfInterrupted` finishes the job.
        let marker = destination.appendingPathExtension("migrating")
        try Data().write(to: marker)
        try FileManager.default.copyItem(at: legacy, to: destination)

        let mismatches = try verify(source: legacy, copy: destination)
        guard mismatches.isEmpty else {
            try? FileManager.default.removeItem(at: destination)
            throw Failure.verificationFailed(mismatches)
        }

        try retire(legacy, movedTo: destination)
        try? FileManager.default.removeItem(at: marker)
        profiles.activate(slug)
        log("migrated \(legacy.path) -> \(destination.path)")
        return "Moved your learning data to \(destination.path). "
            + "The old copy is at \(retiredURL(for: legacy).path)."
    }

    private func readIdentity(at url: URL) -> LearnerIdentity? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let learner = json["learner"] as? [String: Any],
              let name = learner["name"] as? String,
              let language = learner["target_language"] as? String
        else { return nil }
        return LearnerIdentity(name: name, targetLanguage: language)
    }

    /// Every regular file under `source` must exist under `copy` with the same
    /// SHA-256. Counting files is not enough: a truncated image passes a count.
    private func verify(source: URL, copy: URL) throws -> [String] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey])
        else { return ["<could not enumerate>"] }

        var mismatches: [String] = []
        for case let file as URL in walker {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            let relative = file.path.replacingOccurrences(of: source.path + "/", with: "")
            let target = copy.appending(path: relative)
            guard let a = try? Data(contentsOf: file), let b = try? Data(contentsOf: target),
                  SHA256.hash(data: a) == SHA256.hash(data: b)
            else { mismatches.append(relative); continue }
        }
        return mismatches
    }

    /// Never collides. A second migration on the same day would otherwise throw
    /// from `moveItem` *after* the copy had already succeeded, leaving both
    /// directories live -- the worst of the available outcomes.
    private func retiredURL(for legacy: URL) -> URL {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let base = legacy.deletingLastPathComponent()
        var candidate = base.appending(path: "fluent-data.migrated-\(stamp.string(from: Date()))")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = base.appending(
                path: "fluent-data.migrated-\(stamp.string(from: Date()))-\(n)")
            n += 1
        }
        return candidate
    }

    /// Finishes a migration that died between the copy and the retire.
    ///
    /// Called before `runIfNeeded`, because `decide` cannot tell a completed
    /// migration from an abandoned one -- both look like "the profile exists".
    func resumeIfInterrupted() throws {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: Locations.profilesRoot, includingPropertiesForKeys: nil) else { return }
        for marker in entries where marker.pathExtension == "migrating" {
            let destination = marker.deletingPathExtension()
            let legacy = Locations.legacyDataDirectory
            guard fm.fileExists(atPath: destination.path) else {
                try? fm.removeItem(at: marker)   // copy never got anywhere
                continue
            }
            if fm.fileExists(atPath: legacy.path) {
                let mismatches = try verify(source: legacy, copy: destination)
                guard mismatches.isEmpty else {
                    throw Failure.verificationFailed(mismatches)
                }
                try retire(legacy, movedTo: destination)
            }
            try? fm.removeItem(at: marker)
            log("resumed interrupted migration into \(destination.path)")
        }
    }

    private func retire(_ legacy: URL, movedTo destination: URL) throws {
        let retired = retiredURL(for: legacy)
        try FileManager.default.moveItem(at: legacy, to: retired)
        let note = """
            This directory is a retired copy of Fluent's learning data.

            The live data moved to:
              \(destination.path)

            Nothing reads this directory any more. It is kept so the move is
            reversible; delete it once you are satisfied nothing was lost.
            """
        try? note.write(to: retired.appending(path: "README.txt"),
                        atomically: true, encoding: .utf8)
    }

    private func log(_ line: String) {
        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: Locations.migrationLog) {
            handle.seekToEndOfFile()
            handle.write(Data(stamped.utf8))
            try? handle.close()
        } else {
            try? stamped.write(to: Locations.migrationLog, atomically: true, encoding: .utf8)
        }
    }
}
```

- [ ] **Step 2: Call it once at launch, before anything reads a database**

In `AppModel.start()`:

```swift
    func start() async {
        do {
            let migrator = Migrator(profiles: profiles)
            try migrator.resumeIfInterrupted()
            if let note = try migrator.runIfNeeded() {
                statusMessage = note
            }
        } catch {
            self.error = error.localizedDescription
        }
        activeProfile = profiles.active
        rebuildServices()
        await refresh()
    }
```

- [ ] **Step 3: Rehearse the migration against a copy, not the real data**

```bash
export FB="$(cat "$HOME/fluent-transition-backup/LATEST")"
rm -rf /tmp/mig && mkdir -p /tmp/mig/home/.claude /tmp/mig/support
tar -xzf "$FB/fluent-data.tgz" -C /tmp/mig/home/.claude
find /tmp/mig/home/.claude/fluent-data -type f | wc -l
```

Then run the app with `HOME=/tmp/mig/home` so both `Locations.appSupport` and
`legacyDataDirectory` land inside the rehearsal tree:

`UserDefaults` goes through `cfprefsd`, which resolves the *real* user home regardless of
`$HOME` — so without `CFFIXED_USER_HOME` the rehearsal writes `activeProfileID` into the
learner's live preferences, pointing at a profile that exists only under `/tmp`.

```bash
make app
HOME=/tmp/mig/home CFFIXED_USER_HOME=/tmp/mig/home \
  ./Fluent.app/Contents/MacOS/FluentApp &
sleep 20 && kill %1
find /tmp/mig/home/Library/Application\ Support/Fluent -type f | head -20
ls /tmp/mig/home/.claude/
```

Expected: `profiles/roma-japanese/` holds the databases, and
`/tmp/mig/home/.claude/` shows `fluent-data.migrated-<date>` with a `README.txt` and no
`fluent-data`.

- [ ] **Step 4: Verify the rehearsal copy digest-for-digest**

```bash
# Belt and braces: if CFFIXED_USER_HOME was missed, this clears the stray key.
defaults read dev.fluent.app activeProfileID 2>/dev/null \
  && defaults delete dev.fluent.app activeProfileID
cd "/tmp/mig/home/Library/Application Support/Fluent/profiles/roma-japanese"
find . -type f -print0 | sort -z | xargs -0 shasum -a 256 | awk '{print $1}' | sort > /tmp/new.txt
cd /tmp/mig/home/.claude/fluent-data.migrated-*/
find . -type f ! -name README.txt -print0 | sort -z | xargs -0 shasum -a 256 | awk '{print $1}' | sort > /tmp/old.txt
diff /tmp/old.txt /tmp/new.txt && echo "REHEARSAL VERIFIED"
```

Expected: `REHEARSAL VERIFIED`. **If it does not print, stop and fix `Migrator` before
touching the real data.**

- [ ] **Step 5: Run it for real**

**Quit every terminal Claude Code session first.** The migration renames the directory a
running tutor session is reading; that session's next write would recreate an empty one
beside the migrated profile (see D7a).

```bash
pgrep -fl 'claude' | grep -v 'Claude.app' || echo "no CLI sessions running"
make run
```

- [ ] **Step 6: Verify the real migration against the Phase-0 baseline**

```bash
export FB="$(cat "$HOME/fluent-transition-backup/LATEST")"
export P="$HOME/Library/Application Support/Fluent/profiles/roma-japanese"
# -print0/-0: $P contains a space ("Application Support"), and a plain
# `find | xargs` word-splits on it, silently producing an empty digest list and
# a diff that fails for the wrong reason.
find "$P" -type f -print0 | sort -z | xargs -0 shasum -a 256 \
  | awk '{print $1}' | sort > /tmp/after.txt
awk '{print $1}' "$FB/fluent-data.sha256.post-2.2" | sort > /tmp/before.txt
diff /tmp/before.txt /tmp/after.txt && echo "MIGRATION VERIFIED"

FLUENT_DATA_DIR="$P" python3 fluent/.claude/hooks/read-db.py > /tmp/read-db-after.json
python3 - <<'PY'
import json
a = json.load(open("/tmp/read-db-after.json"))
b = json.load(open(f"{__import__('os').environ['FB']}/read-db-before.json"))
for k in ("current_streak_days", "total_sessions"):
    assert a["databases"]["learner_profile"][k] == b["databases"]["learner_profile"][k], k
assert len(a["databases"]["spaced_repetition"]["items"]) == len(b["databases"]["spaced_repetition"]["items"])
assert len(a["databases"]["session_log"]["sessions"]) == len(b["databases"]["session_log"]["sessions"])
assert a["computed"]["next_session_id"] == b["computed"]["next_session_id"]
print("DATABASES IDENTICAL")
PY
```

Expected: `MIGRATION VERIFIED` and `DATABASES IDENTICAL`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(app): move learner state to Application Support, verified

Copies ~/.claude/fluent-data into a named profile, compares every file's
SHA-256, and only then renames the old directory so nothing can quietly
keep writing to it."
```

### Task 3.5: Point the terminal at the migrated profile

- [ ] **Step 1: Update the untracked local settings**

Set `FLUENT_DATA_DIR` in `.claude/settings.local.json` to
`/Users/r/Library/Application Support/Fluent/profiles/roma-japanese`.

- [ ] **Step 2: Move the OpenRouter key out of the repo**

```bash
mkdir -p "$HOME/Library/Application Support/Fluent"
cp .env "$HOME/Library/Application Support/Fluent/credentials.env"
chmod 600 "$HOME/Library/Application Support/Fluent/credentials.env"
grep -c OPENROUTER_FLUENT "$HOME/Library/Application Support/Fluent/credentials.env"
```

Leave `.env` in place for `tools/imgbench`, which reads it independently — and write down
which is which, because there are now two live copies of one secret:

| Copy | Read by | Authority |
|---|---|---|
| `~/Library/Application Support/Fluent/credentials.env` | the app (`Secrets`) | **yes** — this is the one the app uses |
| `<repo>/.env` | `tools/imgbench` only | a convenience copy for the benchmark |

Rotating the key means editing **both**. Add that sentence to `.env.example` in Task 7.1,
and to FL-29 — moving the app's copy into the Keychain has to solve `imgbench`'s read too,
which is why it is not done here.

- [ ] **Step 3: Verify a fresh Claude Code session sees the right data**

Open a new terminal and run, from the repository root:

`settings.local.json` is a Claude Code setting, not a shell export, so a plain terminal
has to be told the path explicitly. Check both surfaces:

```bash
# 1. The path itself resolves and the data is there.
FLUENT_DATA_DIR="$P" python3 fluent/.claude/hooks/session-start.py < /dev/null

# 2. Claude Code applies the setting. In a NEW Claude Code session started in
#    fluent/, run:  !printenv FLUENT_DATA_DIR
```

Expected from the first: the welcome banner naming Roma, Japanese, the streak and the due
count from `$FB/baseline.txt`. Expected from the second: the profile path, space intact.
A bare `python3 fluent/.claude/hooks/session-start.py` with no variable set is **not** a
valid check — it prints the `/fluent-setup` welcome, and creates an empty data directory
while doing so.

**Verification for Phase 3**
- [ ] `MIGRATION VERIFIED` and `DATABASES IDENTICAL` both printed.
- [ ] `~/.claude/fluent-data` no longer exists; `~/.claude/fluent-data.migrated-*` does.
- [ ] The app launches, shows the archive with 7 lessons, the pictures, the saved items
      and the $0.74 spend total.
- [ ] `swift test` → 133 tests pass.
- [ ] `git status --porcelain` is clean; no `data/` or `results/` directory in the repo.

---

## Phase 4 — Give `claude -p` an Explicit Teaching Context (R4)

> **Measured facts this phase acts on.** A `claude -p` run from the repository loads
> `/Users/r/.claude/CLAUDE.md` and the repo's `CLAUDE.md`, and nothing else — verified
> 2026-09-02 by asking a `--tools ""` call to list its memory files. After Phase 2 the
> repo's `CLAUDE.md` is *the app's development instructions*, so without this phase every
> lesson would be generated by a model briefed on Rich Hickey and Swift package layout.
> Also verified: `--safe-mode` returns `[]` for the same question while `--json-schema`,
> `--output-format stream-json`, `--include-partial-messages` and `total_cost_usd` all
> keep working, and `--system-prompt` composes with `--json-schema`.

### Task 4.1: Assemble the teacher's brief from fluent

**Files:**
- Create: `Sources/FluentCore/TeacherBrief.swift`
- Create: `Sources/FluentApp/TeacherContext.swift`
- Create: `Sources/FluentApp/Resources/teacher-context.json`
- Test: `Tests/FluentCoreTests/TeacherBriefTests.swift`
- Modify: `Package.swift` (one more `.copy`)

**Interfaces:**
- Produces: `TeacherBrief.assemble(preamble:documents:) -> String` (pure, FluentCore) and
  `TeacherContext.systemPrompt(kitRoot:call:) throws -> String` (effectful, FluentApp).
  Task 4.2's `ClaudeClient` consumes the second.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import FluentCore

// The brief is the only thing the teacher knows. If a document silently fails to
// load, the model is briefed on less than we think and nothing says so.

@Test func briefKeepsDocumentOrderAndLabelsEachSource() {
    let brief = TeacherBrief.assemble(
        preamble: "You are the teacher.",
        documents: [
            .init(name: "docs/METHODOLOGY.md", text: "Aim for 60-70% success."),
            .init(name: "refs/feedback.md", text: "Say what was right first."),
        ])
    #expect(brief.hasPrefix("You are the teacher."))
    #expect(brief.contains("docs/METHODOLOGY.md"))
    #expect(brief.range(of: "Aim for 60-70%")!.lowerBound
            < brief.range(of: "Say what was right first")!.lowerBound)
}

@Test func briefWithNoDocumentsIsJustThePreamble() {
    #expect(TeacherBrief.assemble(preamble: "Only this.", documents: []) == "Only this.")
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
swift test --filter briefKeepsDocumentOrder 2>&1 | tail -4
```

- [ ] **Step 3: Implement `TeacherBrief`**

```swift
import Foundation

/// The teacher's brief: a preamble the app owns, plus documents fluent owns.
///
/// Assembling it as a value keeps the question "what does the teacher know?"
/// answerable by reading one manifest, rather than by reasoning about which
/// CLAUDE.md files a working directory happens to sit under.
public enum TeacherBrief {
    public struct Document: Equatable, Sendable {
        public let name: String
        public let text: String
        public init(name: String, text: String) {
            self.name = name
            self.text = text
        }
    }

    public static func assemble(preamble: String, documents: [Document]) -> String {
        guard !documents.isEmpty else { return preamble }
        let body = documents.map { "# \($0.name)\n\n\($0.text)" }
            .joined(separator: "\n\n---\n\n")
        return "\(preamble)\n\n---\n\n\(body)"
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
swift test --filter brief 2>&1 | tail -3
```

- [ ] **Step 5: Write the manifest, `Sources/FluentApp/Resources/teacher-context.json`**

The manifest is data so that changing what the teacher knows is an edit, not a rebuild-
shaped decision. Note what is *not* here: `fluent/CLAUDE.md` and `fluent/LEARNING_SYSTEM.md`
are instructions for an interactive terminal session that reads files and writes six
databases. Handing them to a tool-less JSON generator briefs it for the wrong surface.

```json
{
  "preamble": "You are the teacher in Fluent, a spaced-repetition language tutor. You have no tools: you cannot read files, run commands, or write anything. Your entire output is one JSON object matching the schema you are given. The application validates it, records it, and updates the learner's databases itself — never describe database updates, never address the learner in prose outside the JSON, and never ask a follow-up question. The documents below are Fluent's teaching methodology and are binding.",
  "generation": ["docs/METHODOLOGY.md"],
  "grading": ["docs/METHODOLOGY.md", ".claude/references/feedback-template.md"]
}
```

- [ ] **Step 6: Write `TeacherContext.swift`**

```swift
import Foundation
import FluentCore

/// Reads the manifest and the fluent documents it names.
///
/// A missing document throws rather than being skipped. Silently shipping a
/// shorter brief would change how every lesson is taught with nothing to show for
/// it in the output.
enum TeacherContext {
    enum Call: String { case generation, grading }

    struct Manifest: Decodable {
        let preamble: String
        let generation: [String]
        let grading: [String]

        func documents(for call: Call) -> [String] {
            switch call {
            case .generation: generation
            case .grading: grading
            }
        }
    }

    enum Failure: LocalizedError {
        case missing(String)
        var errorDescription: String? {
            switch self {
            case let .missing(path):
                "The Fluent kit is missing \(path), which the teacher's brief needs."
            }
        }
    }

    static func systemPrompt(
        kitRoot: URL, call: Call, resources: ResourceLoader = ResourceLoader()
    ) throws -> String {
        let manifest = try JSONDecoder().decode(
            Manifest.self, from: Data(resources.text("teacher-context.json").utf8))
        let documents = try manifest.documents(for: call).map { relative -> TeacherBrief.Document in
            let url = kitRoot.appending(path: relative)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw Failure.missing(relative)
            }
            return TeacherBrief.Document(name: relative, text: text)
        }
        return TeacherBrief.assemble(preamble: manifest.preamble, documents: documents)
    }
}
```

- [ ] **Step 7: Add a test target for the app layer, and cover the throw**

`Tests/FluentCoreTests` cannot import `FluentApp` (it is an executable target), so
`TeacherContext`, `ProfileStore` and `Migrator` currently have no home for tests. The rule
D3 rests on — *a missing kit document throws rather than shortening the brief* — must not
ship uncovered.

In `Package.swift`, make the app importable and add the target:

```swift
        .executableTarget(
            name: "FluentApp",
            // ... unchanged
        ),

        .testTarget(
            name: "FluentAppTests",
            dependencies: ["FluentApp", "FluentCore"]
        ),
```

Create `Tests/FluentAppTests/TeacherContextTests.swift`:

```swift
import Foundation
import Testing
@testable import FluentApp

/// A brief that silently loses a document changes how every lesson is taught and
/// leaves nothing in the output to say so.
@Test func missingKitDocumentThrowsRatherThanShorteningTheBrief() throws {
    let empty = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "kit-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: empty) }

    #expect(throws: TeacherContext.Failure.self) {
        _ = try TeacherContext.systemPrompt(kitRoot: empty, call: .generation)
    }
}

@Test func gradingBriefCarriesMoreThanGeneration() throws {
    let kitRoot = try #require(Locations.kitRoot())
    let generation = try TeacherContext.systemPrompt(kitRoot: kitRoot, call: .generation)
    let grading = try TeacherContext.systemPrompt(kitRoot: kitRoot, call: .grading)
    #expect(grading.count > generation.count)
    #expect(grading.contains("feedback-template"))
}
```

The second test needs `FLUENT_KIT_ROOT` set (see Task 2.5); it is skipped by `#require`
returning nil otherwise.

- [ ] **Step 8: Ship the manifest in the bundle**

In `Package.swift`, add to the `FluentApp` target's `resources:` array:

```swift
                .copy("Resources/teacher-context.json"),
```

- [ ] **Step 8: Commit**

```bash
swift test 2>&1 | tail -1     # expect 135 in FluentCoreTests + 2 in FluentAppTests
git add -A
git commit -m "feat(app): assemble the teacher's brief from fluent's methodology

The kit's pedagogy now reaches the model explicitly, from a manifest, instead
of arriving as whichever CLAUDE.md the working directory happened to sit under."
```

### Task 4.2: Run `claude -p` in `--safe-mode` with that brief

**Files:**
- Modify: `Sources/FluentApp/ClaudeClient.swift`, `Sources/FluentApp/LessonService.swift`,
  `Sources/FluentApp/AppModel.swift`

- [ ] **Step 1: Take a per-call system prompt in `ClaudeClient.Config`**

```swift
    struct Config {
        var executable: String
        var model: String = "opus"
        var maxBudgetUSD: Double = 2.0
        /// A neutral, writable directory. With `--safe-mode` nothing is discovered
        /// from it; it exists because a process needs one.
        var workingDirectory: URL
    }
```

and add the prompt to the request, not the config, because generation and grading are
briefed differently:

```swift
    func request<T: Decodable>(
        _ type: T.Type,
        prompt: String,
        systemPrompt: String,
        schema: String,
        progress: (@Sendable (Progress) -> Void)? = nil,
        onSpend: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> T {
```

Thread `systemPrompt` through `attempt` unchanged.

- [ ] **Step 2: Change the argument list**

```swift
            [
                "-p", prompt,
                "--model", config.model,
                // Nothing ambient: no CLAUDE.md, no project settings, no hooks,
                // no skills. Everything the teacher knows arrives below, on
                // purpose. Verified 2026-09-02 that this leaves auth, streaming,
                // --json-schema and cost reporting untouched.
                "--safe-mode",
                "--system-prompt", systemPrompt,
                "--output-format", "stream-json",
                "--verbose",
                "--include-partial-messages",
                "--json-schema", schema,
                "--max-budget-usd", String(config.maxBudgetUSD),
                // `--tools ""` removes the tools. The old `--allowedTools ""` only
                // emptied the permission allowlist, leaving the tools defined and
                // the model free to attempt one.
                "--tools", "",
            ],
```

- [ ] **Step 3: Brief each call in `LessonService`**

In `generate(...)`:

```swift
        let systemPrompt = try TeacherContext.systemPrompt(kitRoot: kitRoot, call: .generation)
        let generated = try await claude.request(
            GeneratedLesson.self, prompt: prompt, systemPrompt: systemPrompt,
            schema: schema, progress: progress,
            onSpend: { cost, model in onSpend?("Lesson", cost, model) })
```

In `submit(...)`, the same with `call: .grading`. Add `let kitRoot: URL` to
`LessonService`'s stored properties and pass it from `AppModel.rebuildServices()`.

- [ ] **Step 4: Verify a real generation end to end**

```bash
make run
```

Generate one small lesson. Then check what it cost and that it is well formed:

```bash
python3 - <<'PY'
import json, os, glob
p = os.path.expanduser("~/Library/Application Support/Fluent/profiles/roma-japanese")
newest = max(glob.glob(p + "/lessons/lesson-*.json"), key=os.path.getmtime)
d = json.load(open(newest))
print("title:", d["lesson"]["title"])
print("exercises:", len(d["lesson"]["exercises"]))
spend = json.load(open(p + "/spending.json"))["entries"][0]
print("cost:", spend["costUSD"], spend["model"], spend["purpose"])
PY
```

Expected: a titled lesson with the requested number of exercises, and one recorded spend.
Compare the cost against the $0.58 measured for a five-image Opus lesson in `TODO.md`; a
figure in the same range confirms the brief did not balloon the prompt.

- [ ] **Step 5: Confirm the ambient context is really gone**

```bash
timeout 120 claude -p "List the absolute paths of every CLAUDE.md in your context as a JSON array." \
  --model haiku --tools "" --safe-mode --max-budget-usd 0.10
```

Expected: `[]`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "fix(app): brief the teacher explicitly, and actually remove the tools

Every lesson call was silently loading the machine's global CLAUDE.md — a
software-engineering compass — and the repo's, while never seeing Fluent's
methodology at all. --safe-mode plus an assembled --system-prompt makes the
teacher's context exactly what the manifest says. --allowedTools \"\" also
becomes --tools \"\": the former emptied the permission list, it did not
remove the tools."
```

**Verification for Phase 4**
- [ ] `swift test` → 135 FluentCore + 2 FluentApp tests pass.
- [ ] A generated lesson is well formed and validates.
- [ ] The probe in Step 5 prints `[]`.
- [ ] Grading one lesson still writes back through `update-db.py`, and
      `read-db.py` shows `total_sessions` incremented by exactly 1.

---

## Phase 5 — Create and Switch Profiles in the App (R7)

### Task 5.1: A profile switcher and a first-run screen

**Files:**
- Create: `Sources/FluentApp/Views/ProfileSwitcher.swift`,
  `Sources/FluentApp/Views/NewProfileSheet.swift`,
  `Sources/FluentApp/Views/WelcomeView.swift`
- Modify: `Sources/FluentApp/Views/RootView.swift`,
  `Sources/FluentApp/Views/HomeView.swift` (Settings section)

- [ ] **Step 1: `ProfileSwitcher` — a menu at the top of the sidebar**

```swift
import SwiftUI

/// Who the app is currently teaching. Sits above the sidebar sections because it
/// scopes every one of them: switching changes the archive, the pictures, the
/// saved words and the schedule together.
struct ProfileSwitcher: View {
    @Environment(AppModel.self) private var model
    @State private var creating = false

    var body: some View {
        Menu {
            ForEach(model.profiles.list()) { profile in
                Button {
                    Task { await model.switchProfile(to: profile.id) }
                } label: {
                    Label("\(profile.identity.name) — \(profile.identity.targetLanguage)",
                          systemImage: profile.id == model.activeProfile?.id
                              ? "checkmark" : "person")
                }
            }
            Divider()
            Button("New profile…") { creating = true }
            Button("Reveal in Finder") {
                if let directory = model.dataDirectory {
                    NSWorkspace.shared.activateFileViewerSelecting([directory])
                }
            }
        } label: {
            Label(model.activeProfile.map {
                "\($0.identity.name) · \($0.identity.targetLanguage)"
            } ?? "No profile", systemImage: "person.crop.circle")
        }
        .sheet(isPresented: $creating) { NewProfileSheet() }
    }
}
```

There is deliberately no **Delete profile** item. Deleting a profile deletes a learner's
entire history; *Reveal in Finder* puts that decision where it can be reconsidered.

- [ ] **Step 2: `NewProfileSheet` — name, language, levels**

```swift
import SwiftUI
import FluentCore

struct NewProfileSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var language = "Japanese"
    // Asked for, not defaulted: the generation prompt substitutes both, and a
    // wrong native language quietly changes how every explanation is written.
    @State private var nativeLanguage = ""
    @State private var explanationLanguage = "English"
    @State private var currentLevel = "A1"
    @State private var targetLevel = "B2"
    @State private var failure: String?

    private let levels = ["A1", "A2", "B1", "B2", "C1", "C2"]

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("Target language", text: $language)
            TextField("Native language", text: $nativeLanguage)
            TextField("Explain things in", text: $explanationLanguage)
            Picker("Current level", selection: $currentLevel) {
                ForEach(levels, id: \.self, content: Text.init)
            }
            Picker("Target level", selection: $targetLevel) {
                ForEach(levels, id: \.self, content: Text.init)
            }
            if let failure { Text(failure).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || language.trimmingCharacters(in: .whitespaces).isEmpty
                              || nativeLanguage.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 380)
    }

    private func create() {
        do {
            let profile = try model.profiles.create(
                identity: LearnerIdentity(
                    name: name.trimmingCharacters(in: .whitespaces),
                    targetLanguage: language.trimmingCharacters(in: .whitespaces)),
                currentLevel: currentLevel, targetLevel: targetLevel,
                nativeLanguage: nativeLanguage.trimmingCharacters(in: .whitespaces),
                explanationLanguage: explanationLanguage.trimmingCharacters(in: .whitespaces),
                kitRoot: model.kitRoot)
            dismiss()
            Task { await model.switchProfile(to: profile.id) }
        } catch {
            failure = error.localizedDescription
        }
    }
}
```

- [ ] **Step 3: `WelcomeView` — what a fresh install shows**

`RootView` shows `WelcomeView` whenever `model.profiles.list().isEmpty`: one sentence of
explanation and the same `NewProfileSheet`. Without it, a fresh install shows an empty
Practice screen and an unexplained database error.

```swift
import SwiftUI

struct WelcomeView: View {
    @State private var creating = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome to Fluent").font(.largeTitle)
            Text("Create a profile to begin. One profile holds one learner and one "
                 + "target language, with its own schedule, archive and vocabulary.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .foregroundStyle(.secondary)
            Button("Create a profile…") { creating = true }
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $creating) { NewProfileSheet() }
    }
}
```

- [ ] **Step 4: Update Settings**

Remove the "Fluent repo path" field — `pluginRoot` no longer exists. Add, read-only where
noted:

| Field | Behaviour |
|---|---|
| Kit | `model.kitRoot?.path ?? "not found"`, read-only, with the bundled commit from `fluent-version.txt` |
| Profile directory | read-only path, **Copy** button |
| Terminal snippet | read-only JSON line setting `FLUENT_DATA_DIR` to the active profile, **Copy** button |
| OpenRouter key | secure field; **Save** calls `Secrets.setOpenRouter(_:)` |

The terminal snippet closes the loop from D7: switching profiles in the app tells the
learner exactly what to paste into `.claude/settings.local.json` so the CLI follows.

- [ ] **Step 5: Verify by creating and switching to a second profile**

```bash
make run
```

Create `Test Learner / Spanish`. Then:

```bash
ls "$HOME/Library/Application Support/Fluent/profiles/"
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/Library/Application Support/Fluent/profiles/test-learner-spanish")
d = json.load(open(p + "/learner-profile.json"))
print(d["learner"]["name"], d["learner"]["target_language"],
      d["learner"]["current_level"], "->", d["learner"]["target_level"])
print("files:", sorted(os.listdir(p)))
# The check that matters: no template placeholder survived into a live profile.
import re, pathlib
left = [f.name for f in pathlib.Path(p).glob("*.json")
        if re.search(r'"\{[^"]*\}"', f.read_text())]
print("files with unfilled placeholders:", left or "none")
PY
```

Expected: `roma-japanese` and `test-learner-spanish`; the second holds all six databases,
a personalised learner block, and **`files with unfilled placeholders: none`**. The other
five templates carry `{YYYY-MM-DD}` and similar too — if any is listed, `create()` is
writing a profile the lesson generator will read literally.

- [ ] **Step 6: Verify the switch is complete, not partial**

Switch back to `roma-japanese` in the app and confirm the archive shows 7 lessons, the
pictures return, the saved items return and the streak reads as before. Switch to the test
profile and confirm all four are empty. **A profile switch that leaves one of them behind
is the bug this step exists to catch.**

- [ ] **Step 7: Remove the test profile and commit**

```bash
rm -rf "$HOME/Library/Application Support/Fluent/profiles/test-learner-spanish"
git add -A
git commit -m "feat(app): create and switch learner profiles"
```

**Verification for Phase 5**
- [ ] `swift test` → 135 FluentCore + 2 FluentApp tests pass.
- [ ] Creating a profile writes six databases from fluent's templates.
- [ ] Switching swaps archive, pictures, saved items, spending and schedule together.
- [ ] With no profiles, the app shows `WelcomeView` rather than an error.

---

## Phase 6 — Make the App Installable (R5)

### Task 6.1: Bundle a kit snapshot and refuse to build without one

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Add the snapshot steps**

```make
KIT := fluent

.PHONY: all build app run test clean icon check-kit install

# An app bundled without fluent cannot read a database or grade a lesson. Failing
# here is far better than failing at the learner's first click.
check-kit:
	@test -f $(KIT)/.claude/hooks/update-db.py || { \
	  echo "error: $(KIT)/ is missing or incomplete."; exit 1; }
	@test -z "$$(git status --porcelain -- $(KIT))" || { \
	  echo "error: $(KIT)/ has uncommitted changes; git archive would not ship them."; \
	  git status --short -- $(KIT); exit 1; }

app: build check-kit
	@rm -rf $(APP)
	@mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	@cp $(BUILD_DIR)/FluentApp $(CONTENTS)/MacOS/FluentApp
	@cp Resources/Info.plist $(CONTENTS)/Info.plist
	@cp Resources/Fluent.icns $(CONTENTS)/Resources/Fluent.icns
	@if [ -d "$(BUILD_DIR)/Fluent_FluentApp.bundle" ]; then \
		cp -R "$(BUILD_DIR)/Fluent_FluentApp.bundle" $(CONTENTS)/Resources/; \
	fi
	@# git archive HEAD:$(KIT) ships exactly the tracked files of that subtree at
	@# HEAD: no .git, no __pycache__, no .venv, and crucially no data/*.json a CLI
	@# run left behind. cp -R would ship whatever happens to be on disk.
	@mkdir -p $(CONTENTS)/Resources/fluent
	@git archive HEAD:$(KIT) | tar -x -C $(CONTENTS)/Resources/fluent
	@git rev-parse HEAD > $(CONTENTS)/Resources/fluent-version.txt
	@codesign --force --sign - --timestamp=none $(APP) 2>/dev/null \
		|| echo "warning: ad-hoc signing failed; the app still runs"
	@echo "Built $(APP) with fluent at $$(cut -c1-8 $(CONTENTS)/Resources/fluent-version.txt)"

install: app
	@rm -rf /Applications/$(APP)
	@cp -R $(APP) /Applications/
	@echo "Installed /Applications/$(APP)"
```

- [ ] **Step 2: Verify the snapshot's contents**

```bash
make app
ls Fluent.app/Contents/Resources/fluent/
cat Fluent.app/Contents/Resources/fluent-version.txt
find Fluent.app/Contents/Resources/fluent \( -name '__pycache__' -o -name '.git' \
  -o -name '*.pyc' \) | wc -l      # expect 0
ls Fluent.app/Contents/Resources/fluent/data/     # only .gitkeep and README.md
```

- [ ] **Step 3: Verify `make app` refuses an unshippable tree**

```bash
echo "stray" >> fluent/README.md && make app; echo "exit=$?"
git checkout fluent/README.md
mv fluent /tmp/fluent-hidden && make app; echo "exit=$?"
mv /tmp/fluent-hidden fluent
```

Expected: both fail with a non-zero exit — the first because `git archive` would silently
omit the edit, the second because there is nothing to ship.

- [ ] **Step 4: Install and verify the app runs with the repository out of reach**

This is the real test of R5: nothing in the bundle may depend on the checkout.

```bash
make install
cd /Users/r/prj/p/lang && mv fluent fluent-hidden
open /Applications/Fluent.app
```

In the app: the profile loads, the archive lists 7 lessons, pictures render, and
**generating a new lesson succeeds**. Then:

```bash
cd /Users/r/prj/p/lang && mv fluent-hidden fluent
```

- [ ] **Step 5: Confirm the installed app used the bundled kit, not a stale path**

While a lesson is being finished in the installed app, in another terminal:

```bash
ps -Ao args | grep '[u]pdate-db.py'
```

Expected: the path shown is under `/Applications/Fluent.app/Contents/Resources/fluent`,
not under `/Users/r/prj`.

- [ ] **Step 6: Commit**

```bash
git add Makefile
git commit -m "build: bundle a kit snapshot into the app, and install it

git archive HEAD:fluent ships exactly the tracked files of that subtree at
that commit, with the repository SHA recorded beside them. The build refuses
to run against an uncommitted or missing fluent/ rather than producing an app
that disagrees with the repository."
```

**Verification for Phase 6**
- [ ] `/Applications/Fluent.app` generates, answers and grades a lesson with the repo
      directory renamed away.
- [ ] `fluent-version.txt` matches `git rev-parse HEAD`.
- [ ] No `.git`, `__pycache__` or `*.pyc` in the bundled snapshot.
- [ ] `make app` fails loudly when `fluent/` is missing or has uncommitted changes.

---

## Phase 7 — Documentation, Publication, and the Final Check

### Task 7.1: Bring the documents up to date

**Files:**
- Modify: `README.md`, `.env.example`, `TODO.md` (untracked)
- Modify (kit): `fluent-kit/README.md`

- [ ] **Step 1: `README.md`** — update the Layout table to the new root paths, replace the
  "Settings" section's repo-path talk with the four locations from `CLAUDE.md`, and add:

```markdown
## Install

```bash
git clone git@github.com:little-arhat/perapera.git && cd perapera
make install        # builds, bundles the fluent snapshot, copies to /Applications
```

Fluent lives at `fluent/` in this repository; `make app` snapshots it into the bundle
with `git archive`, so the installed app needs no checkout at all.

## Where your data lives

**Use one surface at a time.** The app and a terminal tutor session write the same six
databases through the same script, and nothing serialises them; overlapping writes lose one
session's scheduling.

`~/Library/Application Support/Fluent/profiles/<profile>/` — databases, lesson archive,
pictures, saved words, spending and backups. Nothing learner-specific is stored in this
repository. Data from before 2026-09 is migrated automatically from
`~/.claude/fluent-data` on first launch, with the old copy renamed rather than removed.
```

- [ ] **Step 2: `.env.example`** — it now documents `tools/imgbench` only; add a line saying
  the app reads its key from `~/Library/Application Support/Fluent/credentials.env` or the
  Settings screen, and that rotating the key means editing both copies.

- [ ] **Step 2b: Bump the app version**

This release moves every piece of learner state. A support conversation — or the learner
six months from now — needs to be able to tell a pre-migration bundle from a post-migration
one, and `CFBundleShortVersionString 0.1.0` / `CFBundleVersion 1` cannot. In
`Resources/Info.plist`:

```xml
	<key>CFBundleShortVersionString</key>
	<string>0.2.0</string>
	<key>CFBundleVersion</key>
	<string>2</string>
```

Leave `CFBundleIdentifier` at `dev.fluent.app`: changing it would orphan the app's
`UserDefaults` (including `activeProfileID`) and its saved window state.

Then show it. `SettingsView` already gains a Kit row in Task 5.1 Step 4; make it read
version *and* kit SHA, so one screenshot answers both questions:

```swift
    Text("Fluent \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")"
         + " · kit \(kitVersion.prefix(8))")
        .font(.caption).foregroundStyle(.secondary)
```

where `kitVersion` reads `Contents/Resources/fluent-version.txt`.

- [ ] **Step 3: `TODO.md`** — add a "Recently done" entry for the transition, and record two
  findings this work surfaced as tickets:

```markdown
### FL-29 — The OpenRouter key belongs in the Keychain · S
`credentials.env` at 0600 is the same protection the repo `.env` had. The Keychain
encrypts at rest and scopes access to the app. `tools/imgbench` reads the same key from
a file, so moving it needs an export path.

### FL-31 — Nothing stops the app and the CLI writing one profile at once · M
Two `update-db.py` runs from different surfaces can each read the pre-update state and the
second discard the first's SM-2 updates. Documented as "one surface at a time" (D7a); a
lockfile needs a real design — scope, staleness, and whether a skill-invoked writer can
honour it — rather than a reflex.

### FL-30 — Measure whether the methodology brief earns its tokens · S
`docs/METHODOLOGY.md` is now in every generation and grading call. Generate the same
lesson spec with and without it and compare cost against lesson quality.
```

- [ ] **Step 4: Commit**

```bash
git add README.md .env.example
git commit -m "docs: install, the four locations, and where your data lives"
```

### Task 7.2: Confirm the repository is self-contained

`origin` and `upstream` were settled in Task 1.1. What remains is proving that a fresh
clone of `perapera` builds and runs with nothing else on the machine.

- [ ] **Step 1: Clone and build from scratch**

```bash
rm -rf /tmp/clone-check
git clone git@github.com:little-arhat/perapera.git /tmp/clone-check
cd /tmp/clone-check
ls fluent/.claude/hooks/update-db.py fluent/docs/METHODOLOGY.md fluent/data-examples/
swift test 2>&1 | tail -1
FLUENT_KIT_ROOT=/tmp/clone-check/fluent make app 2>&1 | tail -2
```

Expected: `fluent/` is an ordinary directory, the full suite passes, and `make app` builds
a bundle carrying its own fluent snapshot.

- [ ] **Step 2: Confirm upstream is still mergeable**

```bash
git -C /Users/r/prj/p/lang/fluent fetch upstream --quiet
git -C /Users/r/prj/p/lang/fluent diff --stat upstream/main..HEAD -- fluent/ | tail -3
```

Expected: our fluent-side changes, and nothing from the app — the separation held.

### Task 7.3: The end-to-end check

- [ ] **Step 1: Compare against the Phase-0 baseline one last time**

```bash
export FB="$(cat "$HOME/fluent-transition-backup/LATEST")"
export P="$HOME/Library/Application Support/Fluent/profiles/roma-japanese"
FLUENT_DATA_DIR="$P" python3 fluent/.claude/hooks/read-db.py > /tmp/final.json
python3 - <<'PY'
import json, os
a = json.load(open("/tmp/final.json"))
b = json.load(open(f"{os.environ['FB']}/read-db-before.json"))
pa, pb = a["databases"]["learner_profile"], b["databases"]["learner_profile"]
print("streak  ", pb["current_streak_days"], "->", pa["current_streak_days"])
print("sessions", pb["total_sessions"], "->", pa["total_sessions"])
print("sr items", len(b["databases"]["spaced_repetition"]["items"]), "->",
      len(a["databases"]["spaced_repetition"]["items"]))
print("log      ", len(b["databases"]["session_log"]["sessions"]), "->",
      len(a["databases"]["session_log"]["sessions"]))
PY
```

Expected: identical, except `sessions` and `log` which grow by exactly the number of
lessons finished during Phase 4–6 verification.

- [ ] **Step 2: Confirm the lesson archive is whole**

```bash
ls "$P/lessons/"*.json | wc -l        # >= 7
ls "$P/lessons/assets/" | wc -l       # >= 2
python3 -c "
import json,os
p=os.path.expanduser('$P')
print('pictures', len(json.load(open(p+'/pictures.json'))))
print('saved', len(json.load(open(p+'/saved-items.json')).get('items',[])))
print('spend', sum(e['costUSD'] for e in json.load(open(p+'/spending.json'))['entries']))
"
```

Expected: at least the counts recorded in `$FB/baseline.txt`, and spend ≥ $0.74.

- [ ] **Step 3: Confirm both histories are intact**

```bash
git -C /Users/r/prj/p/lang/fluent log --oneline | wc -l           # 63 + Phase 2–7 commits
git -C /Users/r/prj/p/lang/fluent-kit log --oneline | wc -l       # 63 + Phase 1 commits
git -C /Users/r/prj/p/lang/fluent log --follow --oneline Sources/FluentApp/AppModel.swift | tail -1
git -C /Users/r/prj/p/lang/fluent cat-file -e edb680379a4437adfa546df03f54ea846d8d637b && echo "pre-transition HEAD reachable"
git -C /Users/r/prj/p/lang/fluent fsck --no-progress 2>&1 | grep -v dangling | head
```

Expected: the `--follow` tail names `03dd30b feat(app): macOS SwiftUI front end for Fluent`,
the old HEAD is reachable, and `fsck` reports no errors.

- [ ] **Step 4: Confirm no state is left in either repository**

```bash
cd /Users/r/prj/p/lang/fluent
git status --porcelain --ignored=matching | grep -E '\.json$' | grep -vE 'imgbench|Fixtures|Schemas|teacher-context|Package|settings' 
find . -path ./fluent -prune -o -name 'learner-profile.json' -print
```

Expected: no output from either.

- [ ] **Step 5: One full lesson, start to finish, in the installed app**

Generate → answer every exercise → Finish. Then confirm `total_sessions` incremented by
exactly 1, the streak advanced, and `spending.json` gained one entry.

---

## If Something Goes Wrong: Rollback

Each phase is reversible from `$FB` alone. Work from newest to oldest.

**Undo the state migration (Phase 3)**

```bash
rm -rf "$HOME/Library/Application Support/Fluent"
mv "$HOME"/.claude/fluent-data.migrated-* "$HOME/.claude/fluent-data"
rm -f "$HOME/.claude/fluent-data/README.txt"   # written by Migrator.retire
find "$HOME/.claude/fluent-data" -type f -print0 | sort -z | xargs -0 shasum -a 256 \
  | diff - "$FB/fluent-data.sha256.post-2.2" && echo "RESTORED"
```

Compare against `.post-2.2`, not the Phase-0 manifest: Task 2.2 added two session
transcripts to the directory on purpose.

If the retired directory is gone too:

```bash
rm -rf "$HOME/.claude/fluent-data"
tar -xzf "$FB/fluent-data.tgz" -C "$HOME/.claude"
```

**Undo the repository reshape (Phase 1)**

Everything Phase 1 did is `git mv` in one repository, so one reset undoes it. Nothing
is checked out from elsewhere and nothing needs deinitialising.

```bash
cd /Users/r/prj/p/lang/fluent
git reset --hard <sha of the commit before Task 1.2>
git clean -fd            # removes the now-empty fluent/ scaffolding
git status --porcelain   # expect only the untracked files Phase 0 archived
```

**Rebuild the repository from scratch**

```bash
rm -rf /Users/r/prj/p/lang/fluent-restored
git clone "$FB/repo-all-refs.bundle" /Users/r/prj/p/lang/fluent-restored
cd /Users/r/prj/p/lang/fluent-restored
tar -xzf "$FB/untracked-and-ignored.tgz"    # includes .git/info/exclude
git log --oneline | wc -l    # 63
```

**Restore UserDefaults**

```bash
defaults import dev.fluent.app "$FB/userdefaults-dev.fluent.app.plist"
```

---

## Decisions the Learner Should Confirm

None of these block a start; each changes one later task.

1. ~~**Kit repository name and host.**~~ **Settled 2026-09-03:**
   `git@github.com:little-arhat/perapera.git`, used from Task 1.1 onward.
2. ~~**App repository origin.**~~ `origin` still points at `m98/fluent` and is wrong after
   ~~Phase 2.~~ **Settled 2026-09-03:** `origin` is `little-arhat/perapera` and
   `m98/fluent` is `upstream` (Task 1.1).
3. **Retiring `~/.claude/fluent-data`.** The plan renames it after a verified copy (D6). If
   it should be left in place instead, drop `Migrator.retire` — and accept that the CLI and
   the app can then diverge silently.
4. **Application Support directory name.** `Fluent` (human-navigable) rather than
   `dev.fluent.app` (bundle-identifier convention). Easy to change now, awkward later.
5. **What the teacher's brief contains.** `Resources/teacher-context.json` currently names
   `docs/METHODOLOGY.md` for generation and adds the feedback template for grading. It
   deliberately excludes `fluent/CLAUDE.md` and `LEARNING_SYSTEM.md` (D3, D4). If "all of
   fluent's instructions" was meant literally, say so — but read D4 first, because the
   literal reading tells a tool-less JSON generator to read files and update databases.

---

## Plan Self-Review

**Spec coverage.** R1 → Tasks 1.1–1.2, 2.2. R2 → Task 2.3 (with `--follow` verification).
R3 → Task 2.4. R4 → Tasks 1.3, 4.1, 4.2. R5 → Task 6.1. R6 → Tasks 1.4, 3.2–3.5.
R7 → Tasks 3.1, 3.3, 5.1. R8 → held as a global constraint; no task generalises the
Japanese-specific code.

**One thing found while checking D7, worth knowing.** The repo's
`.claude/settings.json` carries its own inline `PreCompact` hook that copies
`$CLAUDE_PROJECT_DIR/data/*.json` into `$CLAUDE_PROJECT_DIR/.backups/precompact`. There is
no `data/*.json` in the repo and no `.backups/` directory has ever appeared, so that safety
net has been backing up nothing since the data moved to `~/.claude/fluent-data`. The kit's
own `hooks.json` wires the correct `precompact-backup.sh` — which resolves the path through
`fluent_paths` — but this repo's `settings.json` shadows it with the broken inline version.
Task 2.5 drops the inline hook; if pre-compact backups are wanted for terminal tutor
sessions, run them from `fluent/`, where `hooks.json` applies.

**Traps this plan is built around.** The case-insensitive collision between `Tests/` and
`tests/` (Phase 2 ordering). The untracked-but-irreplaceable files — `TODO.md`, `.env`, the
two session transcripts (Task 0.1 Step 4). `refs/claude/checkpoint-8e19f5f3`, which a plain
`git bundle main` would drop (Task 0.1 Step 2). The split-brain risk of leaving a readable
`~/.claude/fluent-data` behind (D6). `--allowedTools ""` never having removed the tools
(Task 4.2 Step 2). Feeding a tool-less generator a document that tells it to write files
(D4).

**Reviewed 2026-09-02.** A dedicated reviewer checked every claim against the tree and
found twenty-two defects, all since fixed above. Four were reproduced as hard failures and
would each have stopped execution:

| | Defect | Now |
|---|---|---|
| 1 | `git submodule add` with a local path dies on `fatal: transport 'file' not allowed` (git ≥ 2.38, CVE-2022-39253) | Moot: the design moved to one repository plus an `upstream` remote, so no submodule is ever added (D2) |
| 2 | `ProfileSlug.make`'s fallback used `String.hashValue`, which Swift seeds per process — a learner named `ローマ` would get a new directory every launch and orphan their history each time | SHA-256 prefix, with a test asserting the literal value across three separate runs (Task 3.1) |
| 3 | `git rm -r tests` leaves an untracked `__pycache__`, so `git mv app/Tests Tests` means "move *into* `tests/`" and lands the Swift suite at `Tests/Tests/` — exit 0, no warning | `rm -rf tests` plus an explicit `test ! -e tests` gate (Tasks 2.1, 2.3) |
| 4 | The migration's primary verification `find "$P" … \| xargs shasum` word-splits on the space in *Application Support*, producing an empty digest list and a failure that looks like data loss | `-print0 \| sort -z \| xargs -0` (Task 3.4) |

The rest were of a kind: enumerations taken from memory rather than from `rg`. The
"three call sites" for `dataDirectory` were six; `lessonStore` is non-optional and cannot
be guarded inside `init`, so making it optional touches thirteen places, not three;
`SettingsView` lives in `ArchiveView.swift`, not `HomeView.swift`; five skills write
transcripts, not six; the profile template ships eleven placeholders and `personalise`
filled four. Each is now listed with its file and line.

**What this plan does not do.** It does not move the OpenRouter key to the Keychain
(FL-29), does not generalise the app beyond Japanese (R8), does not add profile deletion,
and does not merge from `m98/fluent` — the `upstream` remote is configured for that
but no merge is attempted here.

---

## Appendix A — The app's `CLAUDE.md`

Written in Task 1.4. Reproduced here so the task above reads as one action.

````markdown
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
````
