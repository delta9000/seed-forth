#!/usr/bin/env python3
"""Pure authoring tests; no strace, compiler, or generated source required."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from ladder_fixture_copies import fixture_copies


class CopyProvenance(unittest.TestCase):
    def test_original_alias(self):
        original = {"awklib/eg/lib/grcat.c": b"original C\n"}
        final = dict(original, **{"awklib/grcat.c": b"original C\n"})
        a, g = fixture_copies("gawk-5.3.1", {"awklib/grcat.c"}, original, final, set(), [])
        self.assertEqual(a, {"awklib/grcat.c": "awklib/eg/lib/grcat.c"})
        self.assertEqual(g, {})

    def test_edited_original_is_not_an_alias(self):
        a, g = fixture_copies("any", {"out.c"}, {"in.c": b"old"},
                              {"in.c": b"edited", "out.c": b"old"}, set(), [])
        self.assertEqual((a, g), ({}, {}))

    def bash(self, outputs={"lsignames.h"}, copies=1, data=b"signals", package="bash-5.2.37"):
        events = [{"kind": "exec", "program": "mksignames",
                   "arguments": ["./mksignames", "lsignames.h"]}] * copies
        return fixture_copies(package, {"signames.h"}, {},
                              {"lsignames.h": data, "signames.h": b"signals"},
                              outputs, events)

    def test_bash_copy_follows_generator(self):
        self.assertEqual(self.bash(), ({}, {0: [("lsignames.h", "signames.h")]}))

    def test_bash_requires_replayed_writer(self):
        self.assertEqual(self.bash(outputs=set()), ({}, {}))

    def test_bash_requires_unique_producer(self):
        self.assertEqual(self.bash(copies=0), ({}, {}))
        self.assertEqual(self.bash(copies=2), ({}, {}))

    def test_bash_requires_identical_bytes(self):
        self.assertEqual(self.bash(data=b"different"), ({}, {}))

    def test_bash_rule_is_scoped(self):
        self.assertEqual(self.bash(package="other"), ({}, {}))


if __name__ == "__main__":
    unittest.main()
