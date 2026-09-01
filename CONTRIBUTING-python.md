# Python development

The Python side is managed with [uv](https://docs.astral.sh/uv/).

```bash
uv sync --extra dev      # create .venv and install pytest + ruff
uv run pytest            # tests: hooks, imgbench, the stdlib guard
uv run ruff check .      # lint
uv run ruff check . --fix
```

## uv is a development tool, not a runtime requirement

Fluent's hooks are invoked by Claude Code as:

```
python3 "${CLAUDE_PLUGIN_ROOT}/.claude/hooks/read-db.py"
```

That runs against whatever interpreter the learner happens to have — no venv,
no install step, often no uv. **So the runtime code has no dependencies and must
keep none.** A single `import requests` would break the plugin for everyone who
installs it.

`tests/test_stdlib_only.py` enforces this by parsing each hook's imports, rather
than trusting a comment. It fails if a hook grows a third-party import, and it
also asserts that it found hooks to check — a guard that silently checks nothing
is worse than no guard.

`tools/imgbench` is developer tooling and is likewise stdlib-only, though for a
weaker reason: it just never needed anything.

## Lint scope

Ruff's line length is 100, which is what this codebase already is (p95 of
existing lines is 81). Adopting a linter is not a licence to reformat working,
tested code.

`.claude/hooks/*.py` is upstream code this fork inherited. Correctness rules
(pyflakes `F`) apply there — a real bug is worth a merge conflict. Style rules
do not, because reformatting them buys nothing and makes every future merge from
upstream harder. Code this fork owns (`tools/`, `tests/`) is held to the full
set.

## The Swift app

Separate toolchain, in `app/`:

```bash
cd app && make test && make app
```
