#!/usr/bin/env python3
"""
Smoke test for .claude/hooks/update-db.py.

Runs the script against a fresh fixture DB in a temp dir, feeds it a sample
session report, and asserts schema invariants on the output files.

Usage:
    python3 tests/test_update_db.py
"""
import importlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / ".claude" / "hooks" / "update-db.py"


def make_fixtures(data_dir: Path):
    (data_dir / "learner-profile.json").write_text(json.dumps({
        "learner": {"name": "Test", "target_language": "Dutch",
                    "current_level": "A1", "target_level": "A2"},
        "profile_created": "2026-04-20",
        "last_updated": "2026-04-23",
        "current_streak_days": 2,
        "total_sessions": 1,
        "total_study_minutes": 10,
        "skills": {
            "vocabulary": {"current_level": 1, "confidence": 60,
                           "last_practiced": "2026-04-23",
                           "total_practice_time": 10}
        },
        "focus_areas": [],
        "achievements": [],
        "preferences": {}
    }))
    (data_dir / "progress-db.json").write_text(json.dumps({
        "metadata": {"last_updated": "2026-04-23", "language": "Dutch",
                     "tracking_started": "2026-04-20"},
        "overall_stats": {"total_sessions": 1, "total_exercises": 4,
                          "total_correct": 3, "total_incorrect": 1,
                          "accuracy_rate": 0.75,
                          "total_study_minutes": 10,
                          "average_session_duration": 10},
        "accuracy_trend": [{"date": "2026-04-23", "accuracy": 0.75,
                            "exercises": 4}],
        "skill_progress": {
            "vocabulary": {"sessions": 1, "accuracy": 0.75,
                           "last_practiced": "2026-04-23",
                           "exercises_completed": 4, "correct_count": 3,
                           "incorrect_count": 1}
        },
        "weekly_summary": []
    }))
    (data_dir / "mistakes-db.json").write_text(json.dumps({
        "metadata": {"last_updated": "2026-04-23",
                     "total_patterns_tracked": 0, "language": "Dutch"},
        "error_patterns": {}
    }))
    (data_dir / "mastery-db.json").write_text(json.dumps({
        "metadata": {"last_updated": "2026-04-23", "language": "Dutch"},
        "skills": {
            "vocabulary": {"mastery_level": 1, "confidence_score": 0.75,
                           "total_practice_time": 10,
                           "last_practiced": "2026-04-23",
                           "practice_count": 4, "avg_accuracy": 0.75}
        },
        "patterns": {}
    }))
    (data_dir / "spaced-repetition.json").write_text(json.dumps({
        "metadata": {"algorithm": "SM-2", "last_updated": "2026-04-23",
                     "total_items_tracked": 1, "language": "Dutch"},
        "review_queue": {"today": [], "tomorrow": ["vocab_dag"],
                         "this_week": [], "later": []},
        "items": {
            "vocab_dag": {
                "id": "vocab_dag", "type": "vocabulary", "content": "dag",
                "answer": "day / hi-bye", "category": "greetings",
                "difficulty": "A1", "created_date": "2026-04-23",
                "due_date": "2026-04-24", "interval_days": 1,
                "repetitions": 1, "easiness_factor": 2.5,
                "consecutive_correct": 1, "consecutive_incorrect": 0,
                "last_reviewed": "2026-04-23", "last_quality": 4,
                "mastery_level": 1, "total_reviews": 1, "priority": "medium"
            }
        }
    }))
    (data_dir / "session-log.json").write_text(json.dumps({
        "metadata": {"language": "Dutch", "learner_name": "Test",
                     "total_sessions": 1},
        "sessions": [{
            "session_id": "session-001", "date": "2026-04-23",
            "duration_minutes": 10,
            "skills_practiced": ["vocabulary"],
            "exercises_completed": 4, "accuracy": 0.75,
            "score_breakdown": {"vocabulary": 0.75},
            "topics_covered": [], "breakthroughs": [],
            "focus_next_session": [], "notes": "",
            "achievements_earned": []
        }],
        "milestones": []
    }))


SESSION_PAYLOAD = {
    "session_id": "session-002",
    "date": "2026-04-24",
    "duration_minutes": 15,
    "command_used": "/fluent-learn",
    "skills_practiced": ["vocabulary"],
    "skill_scores": {
        "vocabulary": {"exercises": 5, "correct": 4, "time_minutes": 15}
    },
    "errors": [{
        "pattern_id": "verb_spreek",
        "category": "grammar",
        "subcategory": "verb_conjugation",
        "your_answer": "Hij spreek",
        "correct_answer": "Hij spreekt",
        "context": "3rd person",
        "severity": "critical",
        "difficulty_score": 0.7
    }],
    "new_vocabulary": [{
        "item_id": "het_huis",
        "item_type": "vocabulary",
        "content": "het huis",
        "answer": "the house",
        "category": "nouns",
        "difficulty": "A1",
        "initial_quality": 4
    }],
    "review_results": [{"item_id": "vocab_dag", "quality": 5}],
    "topics_covered": ["house_vocab"],
    "breakthroughs": ["Got 'het huis' on first try"],
    "focus_next_session": ["de/het drill"],
    "session_notes": "Good session.",
    "milestones": []
}


class UpdateDbSmokeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="fluent-test-"))
        (self.tmp / "data").mkdir()
        make_fixtures(self.tmp / "data")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _run(self, payload: dict):
        # The data directory is stated, not inherited. `update-db.py` resolves
        # $FLUENT_DATA_DIR ahead of the working directory, and a subprocess with
        # no `env=` takes the developer's environment with it -- so relying on
        # `cwd` alone pointed the whole suite at whatever real profile happened
        # to be named there. It wrote sixteen fixture sessions into a learner's
        # databases before this line existed.
        env = dict(os.environ)
        env["FLUENT_DATA_DIR"] = str(self.tmp / "data")
        proc = subprocess.run(
            ["python3", str(SCRIPT)],
            input=json.dumps(payload).encode(),
            cwd=str(self.tmp),
            env=env,
            capture_output=True,
        )
        return proc

    def test_an_inherited_data_dir_cannot_redirect_the_suite(self):
        """A stray $FLUENT_DATA_DIR must not aim the tests at real data.

        This is the regression guard for the accident above: the failure is
        silent, destructive, and looks exactly like a passing test run.
        """
        decoy = self.tmp / "decoy"
        decoy.mkdir()
        with mock.patch.dict(os.environ, {"FLUENT_DATA_DIR": str(decoy)}):
            proc = self._run(SESSION_PAYLOAD)
        self.assertEqual(proc.returncode, 0,
                         msg=f"stdout={proc.stdout!r} stderr={proc.stderr!r}")
        self.assertEqual(sorted(decoy.iterdir()), [],
                         "the suite wrote outside its own fixture directory")
        self.assertTrue((self.tmp / "data" / "session-log.json").exists())

    def test_happy_path(self):
        proc = self._run(SESSION_PAYLOAD)
        self.assertEqual(proc.returncode, 0,
                         msg=f"stdout={proc.stdout!r} stderr={proc.stderr!r}")

        with open(self.tmp / "data" / "session-log.json") as f:
            log = json.load(f)
        latest = log["sessions"][-1]
        self.assertEqual(latest["session_id"], "session-002")
        self.assertIn("skills_practiced", latest)
        self.assertIsInstance(latest["skills_practiced"], list)
        self.assertIn("score_breakdown", latest)
        self.assertIn("topics_covered", latest)
        self.assertIn("breakthroughs", latest)
        self.assertIn("focus_next_session", latest)
        self.assertIn("achievements_earned", latest)
        self.assertEqual(latest["streak_day"], 3)  # was 2, yesterday -> +1

        with open(self.tmp / "data" / "learner-profile.json") as f:
            profile = json.load(f)
        self.assertEqual(profile["current_streak_days"], 3)
        conf = profile["skills"]["vocabulary"]["confidence"]
        self.assertIsInstance(conf, int)
        self.assertGreaterEqual(conf, 0)
        self.assertLessEqual(conf, 100)

        with open(self.tmp / "data" / "spaced-repetition.json") as f:
            sr = json.load(f)
        dag = sr["items"]["vocab_dag"]
        # Schema preserved
        for k in ("consecutive_correct", "consecutive_incorrect",
                  "mastery_level", "total_reviews", "priority",
                  "content", "answer", "category", "difficulty"):
            self.assertIn(k, dag, f"lost field {k} on vocab_dag")
        self.assertEqual(dag["total_reviews"], 2)  # was 1, +1 review
        self.assertEqual(dag["last_quality"], 5)

        # New vocabulary item fully populated
        huis = sr["items"]["het_huis"]
        for k in ("id", "type", "content", "answer", "category",
                  "difficulty", "due_date", "interval_days", "repetitions",
                  "easiness_factor", "consecutive_correct",
                  "consecutive_incorrect", "mastery_level",
                  "total_reviews", "priority"):
            self.assertIn(k, huis, f"new item missing {k}")

        with open(self.tmp / "data" / "mistakes-db.json") as f:
            mistakes = json.load(f)
        self.assertIn("verb_spreek", mistakes["error_patterns"])
        pat = mistakes["error_patterns"]["verb_spreek"]
        self.assertEqual(pat["consecutive_incorrect"], 1)
        self.assertEqual(pat["examples"][-1]["incorrect"], "Hij spreek")
        self.assertEqual(pat["examples"][-1]["correct"], "Hij spreekt")

        # Backup directory exists (nested inside data/ to avoid collisions
        # with other plugins when the global fallback ~/.claude/fluent-data is used).
        backup = self.tmp / "data" / ".backups" / "pre-update-session-002"
        self.assertTrue(backup.exists(), "pre-update backup missing")

    def test_missing_required_field_exits_1(self):
        proc = self._run({"date": "2026-04-24"})  # no session_id
        self.assertEqual(proc.returncode, 1)

    def test_same_day_does_not_bump_streak(self):
        # Profile last_updated = 2026-04-23; send a session on 2026-04-23.
        payload = dict(SESSION_PAYLOAD)
        payload["session_id"] = "session-003"
        payload["date"] = "2026-04-23"
        proc = self._run(payload)
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        with open(self.tmp / "data" / "learner-profile.json") as f:
            profile = json.load(f)
        self.assertEqual(profile["current_streak_days"], 2)

    # --- Milestones (issue #8) ---

    def _payload_with(self, session_id, milestones, date="2026-04-24"):
        payload = dict(SESSION_PAYLOAD)
        payload["session_id"] = session_id
        payload["date"] = date
        payload["milestones"] = milestones
        return payload

    def _load(self, name):
        with open(self.tmp / "data" / name) as f:
            return json.load(f)

    def test_milestone_string_form(self):
        text = "Reached A2 vocabulary milestone"
        proc = self._run(self._payload_with("session-100", [text]))
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)

        log = self._load("session-log.json")
        m = log["milestones"][-1]
        self.assertEqual(m["milestone"], text)
        self.assertEqual(m["date"], "2026-04-24")
        self.assertEqual(m["session_id"], "session-100")

        profile = self._load("learner-profile.json")
        ach = profile["achievements"][-1]
        self.assertEqual(ach["name"], text)
        self.assertEqual(ach["description"], text)
        self.assertEqual(ach["earned_date"], "2026-04-24")
        self.assertTrue(ach["id"].startswith("session_session-100_"))

    def test_milestone_object_form(self):
        ms = {"milestone": "Wrote first paragraph", "date": "2026-04-24",
              "session_id": "session-101"}
        proc = self._run(self._payload_with("session-101", [ms]))
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)

        log = self._load("session-log.json")
        m = log["milestones"][-1]
        self.assertEqual(m["milestone"], "Wrote first paragraph")  # flat string
        self.assertEqual(m["date"], "2026-04-24")
        self.assertEqual(m["session_id"], "session-101")

        profile = self._load("learner-profile.json")
        self.assertEqual(profile["achievements"][-1]["name"], "Wrote first paragraph")

    def test_milestone_object_preserves_own_date(self):
        ms = {"milestone": "Backdated win", "date": "2026-04-20"}
        proc = self._run(self._payload_with("session-102", [ms], date="2026-04-24"))
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)

        log = self._load("session-log.json")
        self.assertEqual(log["milestones"][-1]["date"], "2026-04-20")
        profile = self._load("learner-profile.json")
        self.assertEqual(profile["achievements"][-1]["earned_date"], "2026-04-20")

    def test_milestone_bad_date_falls_back_to_session_date(self):
        ms = {"milestone": "Typo date", "date": "not-a-date"}
        proc = self._run(self._payload_with("session-103", [ms], date="2026-04-24"))
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        log = self._load("session-log.json")
        self.assertEqual(log["milestones"][-1]["date"], "2026-04-24")

    def test_milestone_malformed_exits_1_no_mutation(self):
        bad_cases = [
            {"date": "2026-04-24"},          # missing milestone
            {"milestone": None},
            {"milestone": ""},
            {"milestone": "   "},
            {"milestone": 5},
            42,                              # neither str nor dict
            "",                              # empty string form
        ]
        for n, bad in enumerate(bad_cases):
            with self.subTest(case=bad):
                proc = self._run(self._payload_with(f"session-2{n:02d}", [bad]))
                self.assertEqual(proc.returncode, 1,
                                 msg=f"case={bad!r} stderr={proc.stderr!r}")
                self.assertTrue(proc.stderr, "expected an error message on stderr")
                # No DB mutation: session-log still has its single original session.
                log = self._load("session-log.json")
                self.assertEqual(len(log["sessions"]), 1)
                self.assertEqual(log["milestones"], [])

    def test_milestone_nested_session_id_overridden(self):
        ms = {"milestone": "X", "session_id": "WRONG-999"}
        proc = self._run(self._payload_with("session-104", [ms]))
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        log = self._load("session-log.json")
        self.assertEqual(log["milestones"][-1]["session_id"], "session-104")

    def test_milestone_distinct_achievement_ids(self):
        # Two strings sharing the first 30 chars would slugify identically;
        # the index prefix must keep their IDs distinct.
        prefix = "Mastered the perfect tense fo"  # 29 chars
        ms = [prefix + "r regular verbs", prefix + "r irregular verbs"]
        proc = self._run(self._payload_with("session-105", ms))
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        profile = self._load("learner-profile.json")
        ids = [a["id"] for a in profile["achievements"][-2:]]
        self.assertEqual(len(set(ids)), 2, msg=f"colliding ids: {ids}")

    def test_milestone_non_latin_distinct_nonempty_ids(self):
        # All-non-Latin text slugifies to empty; fallback + index keep IDs valid.
        ms = ["مرحلة أولى", "مرحلة ثانية"]
        proc = self._run(self._payload_with("session-106", ms))
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        profile = self._load("learner-profile.json")
        ids = [a["id"] for a in profile["achievements"][-2:]]
        self.assertEqual(len(set(ids)), 2, msg=f"colliding ids: {ids}")
        for i in ids:
            self.assertFalse(i.endswith("_"), f"bare trailing underscore: {i}")

    def test_milestones_empty_and_omitted_are_noops(self):
        for n, payload in enumerate([
            self._payload_with("session-107", []),
            {k: v for k, v in self._payload_with("session-108", []).items()
             if k != "milestones"},
        ]):
            with self.subTest(n=n):
                before = len(self._load("learner-profile.json").get("achievements", []))
                proc = self._run(payload)
                self.assertEqual(proc.returncode, 0, msg=proc.stderr)
                after = len(self._load("learner-profile.json").get("achievements", []))
                self.assertEqual(after, before)

    # --- Streak (last_session_date) ---
    #
    # The streak keys off `last_session_date` (when the learner last practiced),
    # NOT `last_updated` (when the profile file last changed). /fluent-setup
    # stamps last_updated at profile creation, so keying off it made every
    # learner's first session hit the "same day" no-op branch and never start
    # the streak.

    def _write(self, name, data):
        (self.tmp / "data" / name).write_text(json.dumps(data))

    def _fresh_profile(self, **overrides):
        """A profile exactly as /fluent-setup leaves it: last_updated stamped at
        creation, no last_session_date, zero streak."""
        profile = {
            "learner": {"name": "Test", "target_language": "Dutch",
                        "current_level": "A1", "target_level": "A2"},
            "profile_created": "2026-04-24",
            "last_updated": "2026-04-24",
            "current_streak_days": 0,
            "total_sessions": 0,
            "total_study_minutes": 0,
            "skills": {}, "focus_areas": [], "achievements": [],
            "preferences": {},
        }
        profile.update(overrides)
        return profile

    def _empty_log(self):
        return {"metadata": {"language": "Dutch", "learner_name": "Test",
                             "total_sessions": 0},
                "sessions": [], "milestones": []}

    def test_first_session_starts_streak(self):
        """Regression: a brand-new profile whose last_updated == the session date
        must still start the streak at 1."""
        self._write("learner-profile.json", self._fresh_profile())
        self._write("session-log.json", self._empty_log())

        payload = dict(SESSION_PAYLOAD)
        payload["session_id"] = "session-001"
        payload["date"] = "2026-04-24"
        proc = self._run(payload)

        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        profile = self._load("learner-profile.json")
        self.assertEqual(profile["current_streak_days"], 1)
        self.assertEqual(profile["last_session_date"], "2026-04-24")

    def test_consecutive_days_increment_streak(self):
        self._write("learner-profile.json", self._fresh_profile(
            last_session_date="2026-04-23", current_streak_days=4,
            last_updated="2026-04-23"))

        payload = dict(SESSION_PAYLOAD)
        payload["session_id"] = "session-002"
        payload["date"] = "2026-04-24"
        proc = self._run(payload)

        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        self.assertEqual(self._load("learner-profile.json")["current_streak_days"], 5)

    def test_gap_resets_streak(self):
        self._write("learner-profile.json", self._fresh_profile(
            last_session_date="2026-04-19", current_streak_days=9,
            last_updated="2026-04-19"))

        payload = dict(SESSION_PAYLOAD)
        payload["session_id"] = "session-002"
        payload["date"] = "2026-04-24"
        proc = self._run(payload)

        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        self.assertEqual(self._load("learner-profile.json")["current_streak_days"], 1)

    def test_migration_derives_last_session_date_from_log(self):
        """A pre-existing profile has no last_session_date. It must be derived
        from the session log's last entry -- never from last_updated, which is
        the conflation being removed."""
        self._write("learner-profile.json", self._fresh_profile(
            last_updated="2026-04-24", current_streak_days=2))
        # Log says the learner last practiced 2026-04-23 (i.e. yesterday).
        log = self._empty_log()
        log["sessions"] = [{"session_id": "session-001", "date": "2026-04-23",
                            "duration_minutes": 10, "skills_practiced": [],
                            "exercises_completed": 0, "accuracy": 0.0,
                            "score_breakdown": {}, "topics_covered": [],
                            "breakthroughs": [], "focus_next_session": [],
                            "notes": "", "achievements_earned": []}]
        self._write("session-log.json", log)

        payload = dict(SESSION_PAYLOAD)
        payload["session_id"] = "session-002"
        payload["date"] = "2026-04-24"
        proc = self._run(payload)

        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        profile = self._load("learner-profile.json")
        # Derived 2026-04-23 == yesterday -> increment, not reset.
        self.assertEqual(profile["current_streak_days"], 3)
        self.assertEqual(profile["last_session_date"], "2026-04-24")

    def test_last_updated_no_longer_drives_streak(self):
        """last_updated far in the past must not reset a streak whose
        last_session_date is current."""
        self._write("learner-profile.json", self._fresh_profile(
            last_updated="2026-01-01", last_session_date="2026-04-23",
            current_streak_days=7))

        payload = dict(SESSION_PAYLOAD)
        payload["session_id"] = "session-002"
        payload["date"] = "2026-04-24"
        proc = self._run(payload)

        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        self.assertEqual(self._load("learner-profile.json")["current_streak_days"], 8)


if __name__ == "__main__":
    unittest.main()


class ResultsDirTests(unittest.TestCase):
    """Session transcripts are learner state and belong beside the databases.

    Five skills wrote them into the project directory, which puts a learner's
    words inside a git checkout and collides the moment there is more than one
    profile.
    """

    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix="fluent-results-")).resolve()
        sys.path.insert(0, str(REPO_ROOT / ".claude" / "hooks"))

    def tearDown(self):
        shutil.rmtree(self.base, ignore_errors=True)

    def _resolve(self, data_dir: Path, resolver: str):
        """Reload fluent_paths under a given FLUENT_DATA_DIR and call one resolver.

        Every resolver is @lru_cache'd and reads the environment when first
        called, so the reload and the call both have to happen inside the patch.
        """
        import fluent_paths
        with mock.patch.dict(os.environ, {"FLUENT_DATA_DIR": str(data_dir)}):
            importlib.reload(fluent_paths)
            return getattr(fluent_paths, resolver)()

    def test_results_dir_is_nested_in_data_dir(self):
        # Compare against the resolved path: data_dir() calls .resolve(), and on
        # macOS /tmp is a symlink to /private/tmp, so comparing to the literal
        # string fails for a reason that has nothing to do with the feature.
        self.assertEqual(self._resolve(self.base, "results_dir"),
                         self.base / "results")

    def test_ensure_results_dir_creates_it(self):
        created = self._resolve(self.base / "missing", "ensure_results_dir")
        self.assertTrue(created.is_dir())
        self.assertEqual(created.name, "results")
