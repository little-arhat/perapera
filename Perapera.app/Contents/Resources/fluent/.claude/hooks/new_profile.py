#!/usr/bin/env python3
"""
Seed a new learner's six databases from the templates in data-examples/.

The templates are *examples*. They carry a sample session, a sample error
pattern, a sample review item and 37 `{PLACEHOLDER}` strings between them.
Copied verbatim into a real profile those become fake history: read-db.py
reports the sample session as real, and the lesson generator reads it as the
learner's record. So the templates are transformed rather than copied:

  1. Known placeholders are substituted with the interview's answers.
  2. Dict keys named `example_*` are dropped.
  3. Any list entry still holding a placeholder is dropped, which empties the
     example-only collections without needing to name each one.
  4. Anything still holding a placeholder is an error. A profile that ships
     `"{YOUR_NATIVE_LANGUAGE}"` reaches the model as literal text and is
     invisible in the UI, so it must fail here where it can still be fixed.

Structure is preserved throughout: the five skills, the mastery scale and the
four review queues survive, because update-db.py and read-db.py rely on them.

Usage:
    python3 new_profile.py --data-dir DIR --name NAME --target-language LANG \\
        --native-language LANG --current-level A1 --target-level B2 [...]

Exit codes: 0=created, 1=refused (profile exists, or a placeholder survived).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fluent_paths import force_utf8_io, plugin_root  # noqa: E402

force_utf8_io()

PLACEHOLDER = re.compile(r"\{[^{}]*\}")

# template file -> the database it seeds
DATABASES = {
    "learner-profile-template.json": "learner-profile.json",
    "progress-db-template.json": "progress-db.json",
    "mistakes-db-template.json": "mistakes-db.json",
    "mastery-db-template.json": "mastery-db.json",
    "spaced-repetition-template.json": "spaced-repetition.json",
    "session-log-template.json": "session-log.json",
}


def substitutions(args) -> dict[str, object]:
    today = date.today().isoformat()
    return {
        "{YYYY-MM-DD}": today,
        "{name}": args.name,
        "{YOUR_NAME}": args.name,
        "{target_language}": args.target_language,
        "{LANGUAGE_YOU_WANT_TO_LEARN}": args.target_language,
        "{YOUR_NATIVE_LANGUAGE}": args.native_language,
        "{A1|A2|B1|B2|C1|C2}": args.current_level,
        "{A2|B1|B2|C1|C2}": args.target_level,
        "{conversational|academic|immersive|balanced}": args.learning_style,
        "{travel|work|exam|living_abroad|personal|family}": args.motivation,
        "{3_months|6_months|1_year|2_years}": args.timeline,
    }


def transform(node, subs: dict[str, object]):
    """Drop examples, then substitute. The order is the whole point.

    Substituting first fills `{YYYY-MM-DD}` in the sample accuracy_trend entry
    with today's date, after which nothing marks it as an example and it ships
    as real history. So list entries are tested for placeholders *before* any
    substitution touches them."""
    if isinstance(node, dict):
        return {key: transform(value, subs)
                for key, value in node.items()
                if not key.startswith("example_")}
    if isinstance(node, list):
        return [transform(v, subs) for v in node if not holds_placeholder(v)]
    if isinstance(node, str):
        return subs.get(node, node)
    return node


def holds_placeholder(node) -> bool:
    if isinstance(node, dict):
        return any(holds_placeholder(v) for v in node.values())
    if isinstance(node, list):
        return any(holds_placeholder(v) for v in node)
    if isinstance(node, str):
        return bool(PLACEHOLDER.search(node))
    return False


def personalise(profile: dict, args) -> dict:
    """Fill the fields the interview asked for that no placeholder covers."""
    learner = profile.setdefault("learner", {})
    learner["name"] = args.name
    learner["target_language"] = args.target_language
    learner["native_language"] = args.native_language
    learner["explanation_language"] = args.explanation_language
    learner["current_level"] = args.current_level
    learner["target_level"] = args.target_level
    learner["motivation"] = args.motivation
    learner["learning_style"] = args.learning_style
    learner["timeline"] = args.timeline
    learner["daily_goal_minutes"] = args.daily_minutes
    learner["other_languages"] = list(args.other_languages or [])
    learner["bridge_languages"] = list(args.bridge_languages or [])

    today = date.today().isoformat()
    profile["profile_created"] = today
    profile["last_updated"] = today
    # update-db.py sets both on the learner's first real session. Pre-setting
    # last_session_date makes that session look like a repeat and silently skips
    # the streak -- the bug this fork already fixed once.
    profile["last_session_date"] = None
    profile["current_streak_days"] = 0
    profile["total_sessions"] = 0
    profile["total_study_minutes"] = 0
    return profile


def main() -> int:
    p = argparse.ArgumentParser(description="Seed a new learner profile.")
    p.add_argument("--data-dir", required=True)
    p.add_argument("--name", required=True)
    p.add_argument("--target-language", required=True)
    p.add_argument("--native-language", required=True)
    p.add_argument("--explanation-language", default="English")
    p.add_argument("--current-level", required=True)
    p.add_argument("--target-level", required=True)
    p.add_argument("--timeline", default="1_year")
    p.add_argument("--daily-minutes", type=int, default=30)
    p.add_argument("--motivation", default="personal")
    p.add_argument("--learning-style", default="balanced")
    p.add_argument("--other-languages", nargs="*", default=[])
    p.add_argument("--bridge-languages", nargs="*", default=[])
    p.add_argument("--templates", default=None,
                   help="directory holding *-template.json (default: fluent's own)")
    args = p.parse_args()

    data_dir = Path(args.data_dir).expanduser()
    existing = [name for name in DATABASES.values() if (data_dir / name).exists()]
    if existing:
        print(f"[Fluent] refusing to overwrite: {data_dir} already holds "
              f"{', '.join(sorted(existing))}", file=sys.stderr)
        return 1

    templates = Path(args.templates) if args.templates else plugin_root() / "data-examples"
    subs = substitutions(args)
    data_dir.mkdir(parents=True, exist_ok=True)

    written = []
    for template_name, target_name in DATABASES.items():
        source = templates / template_name
        if not source.exists():
            print(f"[Fluent] missing template: {source}", file=sys.stderr)
            return 1
        seeded = transform(json.loads(source.read_text(encoding="utf-8")), subs)
        if target_name == "learner-profile.json":
            seeded = personalise(seeded, args)
        if holds_placeholder(seeded):
            print(f"[Fluent] {target_name} still holds a template placeholder; "
                  "refusing to write a profile the tutor would read literally.",
                  file=sys.stderr)
            return 1
        (data_dir / target_name).write_text(
            json.dumps(seeded, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        written.append(target_name)

    print(json.dumps({"data_dir": str(data_dir), "created": written}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
