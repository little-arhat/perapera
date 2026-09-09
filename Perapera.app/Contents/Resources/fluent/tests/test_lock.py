#!/usr/bin/env python3
"""One writer at a time.

Two writers overlapping do not corrupt anything -- every file is written
atomically -- they lose a whole session's scheduling, silently, because each
computed its update from a state the other replaced.
"""
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
HOOKS = REPO_ROOT / ".claude" / "hooks"
sys.path.insert(0, str(HOOKS))

from fluent_lock import LOCK_NAME, database_lock  # noqa: E402


class LockTests(unittest.TestCase):
    def setUp(self):
        self.dir = pathlib.Path(tempfile.mkdtemp(prefix="fluent-lock-"))

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_a_second_writer_is_refused_while_the_first_holds_it(self):
        with database_lock(self.dir, timeout=0.5):
            with self.assertRaises(TimeoutError):
                with database_lock(self.dir, timeout=0.5):
                    pass

    def test_the_lock_is_released_when_the_first_writer_finishes(self):
        with database_lock(self.dir, timeout=0.5):
            pass
        with database_lock(self.dir, timeout=0.5):
            pass  # no exception

    def test_it_gives_up_rather_than_blocking_a_lesson_forever(self):
        with database_lock(self.dir, timeout=0.3):
            started = time.monotonic()
            with self.assertRaises(TimeoutError):
                with database_lock(self.dir, timeout=0.3):
                    pass
            self.assertLess(time.monotonic() - started, 3.0)

    def test_a_crashed_writer_does_not_strand_the_lock(self):
        # The operating system drops the lock when the process dies, so a
        # crash cannot leave a profile permanently unwritable.
        code = (f"import sys; sys.path.insert(0, {str(HOOKS)!r});"
                f"from fluent_lock import database_lock;"
                f"ctx = database_lock({str(self.dir)!r});"
                f"ctx.__enter__(); import os; os._exit(1)")
        subprocess.run([sys.executable, "-c", code], capture_output=True)
        with database_lock(self.dir, timeout=1.0):
            pass  # no exception

    def test_profiles_do_not_block_each_other(self):
        other = pathlib.Path(tempfile.mkdtemp(prefix="fluent-lock-other-"))
        try:
            with database_lock(self.dir, timeout=0.5):
                with database_lock(other, timeout=0.5):
                    pass  # different profile, different lock
        finally:
            shutil.rmtree(other, ignore_errors=True)

    def test_the_lock_file_names_who_holds_it(self):
        # A learner who hits the timeout needs something to look at.
        with database_lock(self.dir, timeout=0.5):
            content = (self.dir / LOCK_NAME).read_text().split()
        self.assertTrue(content[0].isdigit(), "should record the holding pid")


if __name__ == "__main__":
    unittest.main()
