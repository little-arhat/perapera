# Session Result File Template

## Where transcripts go

`$FLUENT_DATA_DIR/results/` — beside the databases they describe, never inside the
checkout. A transcript is learner state: written into the project directory it puts the
learner's own words in a git repository, and it collides the moment one machine holds more
than one profile.

If `$FLUENT_DATA_DIR` is not set, ask for the directory rather than guessing. Fluent is
stdlib-only Python and must run on an unprepared machine, so this is a `python3 -c`, not a
`jq` pipeline:

    python3 -c "import sys; sys.path.insert(0, '.claude/hooks'); from fluent_paths import ensure_results_dir; print(ensure_results_dir())"

Every practice skill saves its session to `$FLUENT_DATA_DIR/results/fluent-{skill}-session-{NNN}.md`. The `fluent-session-analyzer` skill parses these files to plan future sessions — so the format must be consistent.

## File naming

```
$FLUENT_DATA_DIR/results/fluent-{skill}-session-{NNN}.md
```

Examples:
- `fluent-writing-session-012.md`
- `fluent-vocab-session-005.md`
- `fluent-speaking-session-003.md`
- `fluent-review-session-042.md`
- `fluent-learn-session-018.md`
- `fluent-reading-session-007.md`

> Files created before v0.2.0 may use the older `{skill}-session-{NNN}.md` naming (no `fluent-` prefix). The analyzer reads both — do not rename existing files.

`NNN` is the global session counter (not per-skill) — matches `session_id` in `session-log.json`.

## Required structure

```markdown
# {Skill} Practice Session {NNN}

**Date:** YYYY-MM-DD
**Duration:** {X} minutes
**Skill:** {writing/speaking/vocab/reading/review/learn}
**Command:** {/fluent-writing, /fluent-speaking, etc.}

---

## Session Summary
- Questions: {Y}
- Correct: {Z}
- Accuracy: {percent}%

---

## Questions & Answers

### Question 1: {Type}

**Prompt:** {what the learner was asked}
**Your answer:** "{what they wrote}"
**Correct answer:** "{correct version}"

**Analysis:**
- ❌ {error with severity emoji} — {correction} ({category})
- ✅ {what was correct}

**Score:** {X}/10

---

### Question 2: {Type}

[repeat]

---

## Error Pattern Summary

| Pattern | Category | Severity | Count This Session |
|---------|----------|----------|--------------------|
| {pattern} | {category} | 🔴/🟡/🟢 | {N} |

## Strengths

| Skill | Evidence |
|-------|----------|
| {skill} | {what the learner did well} |

## Progress Tracking

**Improvements:**
- {what improved compared to last session}

**Focus Areas:**
- {what needs work}

**Next Session:**
- {recommended focus}
```

## Key parsing markers

The `fluent-session-analyzer` skill relies on these exact markers being present:

- `❌` — error line (parsed for category + severity)
- `✅` — strength line
- `**Score:** {X}/10` — per-question score
- `**Accuracy:** {percent}%` — session accuracy
- `| 🔴` / `| 🟡` / `| 🟢` — severity in tables
- `**Focus Areas:**` — cue for next-session planning

Do not rename these headings or reorder sections. Changes break the analyzer.

## Interaction with databases

Session files are **markdown narrative**. JSON databases (`mistakes-db.json`, `mastery-db.json`) hold aggregated counts and SM-2 state. Both must be updated — the markdown records the story, the JSON records the numbers.

Call `.claude/hooks/update-db.py` once at session end with a full payload (see `db-updater-payload.example.json`). The script handles the JSON side; the practice skill handles the markdown side. The `fluent-db-updater` skill documents the payload schema.
