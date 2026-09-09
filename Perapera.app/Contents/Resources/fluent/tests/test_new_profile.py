#!/usr/bin/env python3
"""A new profile must be empty, complete, and free of template placeholders.

The templates in data-examples/ are *examples*: they carry sample sessions,
sample error patterns and 37 `{PLACEHOLDER}` strings between them. Copied
verbatim into a real profile they become fake history that read-db.py reports
as real and the lesson generator reads as the learner's record.
"""
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / ".claude" / "hooks" / "new_profile.py"
# A placeholder is a string value that is entirely `{...}`; matching bare
# braces would match every JSON object in the file.
PLACEHOLDER = re.compile(r'"\{[^"]*\}"')

EXPECTED_FILES = {
    "learner-profile.json", "progress-db.json", "mistakes-db.json",
    "mastery-db.json", "spaced-repetition.json", "session-log.json",
}


class NewProfileTests(unittest.TestCase):
    def setUp(self):
        self.data = pathlib.Path(tempfile.mkdtemp(prefix="fluent-newprofile-"))

    def tearDown(self):
        shutil.rmtree(self.data, ignore_errors=True)

    def _run(self, *extra):
        return subprocess.run(
            [sys.executable, str(SCRIPT),
             "--data-dir", str(self.data),
             "--name", "Roma", "--target-language", "Japanese",
             "--native-language", "Russian", "--explanation-language", "English",
             "--current-level", "A1", "--target-level", "B2", *extra],
            capture_output=True, text=True)

    def test_writes_all_six_databases(self):
        proc = self._run()
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        self.assertEqual({p.name for p in self.data.glob("*.json")}, EXPECTED_FILES)

    def test_no_placeholder_survives(self):
        self._run()
        for path in self.data.glob("*.json"):
            found = PLACEHOLDER.findall(path.read_text())
            self.assertEqual(found, [], f"{path.name} still has placeholders: {found}")

    def test_history_is_empty_not_exemplary(self):
        self._run()
        load = lambda n: json.loads((self.data / n).read_text())
        self.assertEqual(load("session-log.json")["sessions"], [])
        self.assertEqual(load("session-log.json")["milestones"], [])
        self.assertEqual(load("mistakes-db.json")["error_patterns"], {})
        self.assertEqual(load("spaced-repetition.json")["items"], {})
        self.assertEqual(load("mastery-db.json")["patterns"], {})
        self.assertEqual(load("progress-db.json")["accuracy_trend"], [])
        self.assertEqual(load("progress-db.json")["weekly_summary"], [])

    def test_structure_the_scripts_rely_on_is_kept(self):
        self._run()
        mastery = json.loads((self.data / "mastery-db.json").read_text())
        self.assertEqual(set(mastery["skills"]),
                         {"writing", "speaking", "vocabulary", "reading", "listening"})
        self.assertIn("mastery_scale", mastery)
        sr = json.loads((self.data / "spaced-repetition.json").read_text())
        self.assertEqual(set(sr["review_queue"]), {"today", "tomorrow", "this_week", "later"})

    def test_the_streak_has_not_started(self):
        # update-db.py sets both on the first real session. Pre-setting
        # last_session_date makes that session look like a repeat and silently
        # skips the streak.
        self._run()
        profile = json.loads((self.data / "learner-profile.json").read_text())
        self.assertIsNone(profile["last_session_date"])
        self.assertEqual(profile["current_streak_days"], 0)
        self.assertEqual(profile["total_sessions"], 0)

    def test_the_interview_answers_land_in_the_profile(self):
        self._run("--motivation", "travel", "--daily-minutes", "30")
        learner = json.loads((self.data / "learner-profile.json").read_text())["learner"]
        self.assertEqual(learner["name"], "Roma")
        self.assertEqual(learner["target_language"], "Japanese")
        self.assertEqual(learner["native_language"], "Russian")
        self.assertEqual(learner["current_level"], "A1")
        self.assertEqual(learner["motivation"], "travel")

    def test_refuses_to_overwrite_an_existing_profile(self):
        self.assertEqual(self._run().returncode, 0)
        second = self._run()
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("already", (second.stderr + second.stdout).lower())


if __name__ == "__main__":
    unittest.main()
