#!/usr/bin/env python3
"""The runtime code must import nothing outside the standard library.

Claude Code invokes the hooks as `python3 "${CLAUDE_PLUGIN_ROOT}/hooks/x.py"`
against whatever interpreter the learner has, with no venv and no install step.
One third-party import would break the plugin for everyone who installs it.

That property is easy to lose by accident and invisible until someone else's
machine fails, so it is asserted here rather than left as a comment.
"""

import ast
import pathlib
import sys
import unittest

REPO = pathlib.Path(__file__).resolve().parent.parent

# Directories whose code runs on a learner's machine, unprepared.
RUNTIME_DIRS = [REPO / ".claude" / "hooks"]

# Modules the runtime code may import: the standard library, plus its own
# siblings.
LOCAL_MODULES = {"fluent_paths"}


def imported_roots(path: pathlib.Path) -> set[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    roots: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            roots.update(alias.name.split(".")[0] for alias in node.names)
        # A relative import cannot reach a third-party package, so only
        # absolute ones are of interest.
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            roots.add(node.module.split(".")[0])
    return roots


class StdlibOnlyTest(unittest.TestCase):
    def test_hooks_import_only_the_standard_library(self):
        stdlib = set(sys.stdlib_module_names)
        offenders: list[str] = []

        for directory in RUNTIME_DIRS:
            for script in sorted(directory.glob("*.py")):
                offenders.extend(
                    f"{script.name} imports {root!r}"
                    for root in sorted(imported_roots(script) - stdlib - LOCAL_MODULES)
                )

        self.assertEqual(
            offenders, [],
            "Runtime code must be stdlib-only — the hooks run against the "
            "learner's own interpreter with no install step:\n  "
            + "\n  ".join(offenders),
        )

    def test_there_is_runtime_code_to_check(self):
        # A passing test that checked nothing would be worse than no test.
        scripts = [s for d in RUNTIME_DIRS for s in d.glob("*.py")]
        self.assertGreater(len(scripts), 3)
