# Install

## Requirements

| | |
|---|---|
| macOS | 14 or later |
| Xcode | for the SDK and the test frameworks; Swift 6 |
| `claude` | logged in. The app shells out to it for lesson generation and grading |
| `python3` | the system one at `/usr/bin/python3`. Fluent's hooks are stdlib-only, so there is no venv and no install step |
| OpenRouter key | optional, for generated photographs |

## Build

```bash
git clone git@github.com:little-arhat/perapera.git && cd perapera
make app     # build, assemble Fluent.app, ad-hoc sign
make run     # and launch it
swift test   # 127 tests, no network
```

There is no `.xcodeproj` on purpose. This is a plain Swift package, and the bundle is four
files of metadata rather than a reason to adopt a project format.

The ad-hoc signature matters even though nobody is distributing this: macOS keys a stable
app identity off the signature, and without one, window state and permissions reset on
every rebuild.

The app spawns `claude` and `python3`, so **App Sandbox is off**. A sandboxed build cannot
work.

## Create a learner profile

The app reads a profile; it does not yet create one. Run Fluent's onboarding in a terminal:

```bash
cd fluent
claude
> /fluent-setup
```

It asks eleven questions (name, target and native language, CEFR level now and wanted,
timeline, daily minutes, goal, learning style), runs a five-question placement assessment
if you are unsure of your level, computes a study plan, and writes the six databases. Say
Japanese unless you intend to do without kana input, furigana and the Japanese voice.

Creating profiles from inside the app is planned; see [TransitionPlan.md](TransitionPlan.md).

## Where your data lives

Today: `~/.claude/fluent-data/` — six JSON databases, the lesson archive, generated
pictures, saved words, spending, and dated backups. Nothing learner-specific is stored in
the checkout.

That location is Fluent's plugin-install default and predates this app. It is moving to
`${XDG_DATA_HOME:-~/.local/share}/perapera/profiles/<profile>/`, one directory per learner
and target language.

Two reasons for XDG over `~/Library/Application Support`. The data is co-owned by a shell:
Python hooks, five Fluent skills, and `$FLUENT_DATA_DIR` in two settings files all touch
it, and a path containing a space needs quoting in every one of them. It already caused a
real bug here, where a `find | xargs shasum` check word-split and reported data loss on a
good copy. Second, `~/Library/Application Support` buys nothing in return: Time Machine and
Migration Assistant take the whole home directory, dotfiles included.

The migration copies, compares every file's SHA-256, and only then retires the old
directory by renaming it. Nothing is deleted.

## Point the terminal at your data

Fluent resolves its data directory from `$FLUENT_DATA_DIR` first. Claude Code exports an
`env` block from `.claude/settings.local.json`, and a session rooted at `fluent/` reads
only its own copy, so both files need the value:

```json
{
  "env": {
    "FLUENT_DATA_DIR": "/Users/you/.claude/fluent-data",
    "FLUENT_KIT_ROOT": "/Users/you/prj/perapera/fluent"
  }
}
```

Both are gitignored. If `$FLUENT_DATA_DIR` is unset, Fluent creates an empty database set
at `~/.claude/fluent-data` rather than failing, which is how you end up with two divergent
copies of your progress.

## OpenRouter key

Only needed for generated photographs. Put it in a gitignored `.env` at the repo root:

```
OPENROUTER_FLUENT=sk-or-...
```

The name is Fluent-specific so revoking it cannot break other projects. `tools/imgbench`
reads the same variable. Without a key, photograph exercises are dropped from a lesson
rather than shown blank.

## Settings

Open with ⌘,. The `claude` binary is located on `PATH` at first launch, including
`~/.brew/bin`, `/opt/homebrew/bin`, `/usr/local/bin` and `~/.local/bin`, since a GUI app
inherits a minimal `PATH`. Repo path, `claude` path and model are editable there.

Opus generates and grades by default. Generation is the high-volume call, so moving it to
Sonnet is the main cost lever. Every call carries a `--max-budget-usd` ceiling, so a
runaway generation fails loudly instead of quietly costing money.
