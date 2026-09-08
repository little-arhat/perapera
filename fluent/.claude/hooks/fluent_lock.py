"""
One writer at a time, across every surface.

The six databases are read, changed and written back as a set. Two writers
overlapping -- a terminal tutor session finishing a review while the app submits
a lesson -- each read the pre-update state, and the second silently discards the
first's SM-2 updates. Every file is written atomically, so nothing is corrupt;
the loss is a whole session's scheduling, which is worse, because nothing about
it looks wrong afterwards.

The lock lives with the data rather than with either surface, so profiles are
independent and both the app and the CLI are covered by the same mechanism:
they both write through update-db.py.

Advisory, not mandatory. A writer that does not take the lock is not stopped --
the point is that the two writers that exist both go through this module.
"""
from __future__ import annotations

import contextlib
import os
import sys
import time
from pathlib import Path

LOCK_NAME = ".write.lock"

if sys.platform == "win32":  # pragma: no cover - not exercised on macOS
    import msvcrt

    def _acquire(handle, exclusive: bool) -> bool:
        try:
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            return True
        except OSError:
            return False

    def _release(handle) -> None:
        with contextlib.suppress(OSError):
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
else:
    import fcntl

    def _acquire(handle, exclusive: bool) -> bool:
        mode = fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH
        try:
            fcntl.flock(handle.fileno(), mode | fcntl.LOCK_NB)
            return True
        except OSError:
            return False

    def _release(handle) -> None:
        with contextlib.suppress(OSError):
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


@contextlib.contextmanager
def database_lock(data_dir: Path, exclusive: bool = True, timeout: float = 20.0):
    """Hold the lock for the whole read-modify-write, or fail loudly.

    A timeout rather than an unbounded wait: a lock held for twenty seconds is a
    crashed writer or a person staring at a prompt, and blocking a lesson
    submission forever is not better than saying so. The lock is released by the
    operating system when the process dies, so a crash cannot strand it.
    """
    data_dir.mkdir(parents=True, exist_ok=True)
    path = data_dir / LOCK_NAME
    handle = open(path, "a+")
    deadline = time.monotonic() + timeout
    try:
        while not _acquire(handle, exclusive):
            if time.monotonic() >= deadline:
                raise TimeoutError(
                    f"another Fluent writer has held {path} for {timeout:g}s. "
                    "Close the other session, or delete the file if nothing is running."
                )
            time.sleep(0.1)
        try:
            handle.seek(0)
            handle.truncate()
            handle.write(f"{os.getpid()} {time.time():.0f}\n")
            handle.flush()
            yield
        finally:
            _release(handle)
    finally:
        handle.close()
