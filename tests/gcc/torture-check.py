#!/usr/bin/env python3
"""Focused checks for the pinned execute suite's exception semantics."""
import importlib.util
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("torture", ROOT / "gcc-direct/torture.py")
torture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(torture)
INVENTORY = json.loads((ROOT / "gcc-direct/torture-x.json").read_text())


class TortureChecks(unittest.TestCase):
    def policy(self, name, target="x86_64-pc-linux-gnu", option="-O2"):
        return torture.evaluate_x(name, INVENTORY[name], target, option, INVENTORY)

    def test_native_inventory(self):
        self.assertEqual(len(INVENTORY), 25)
        skips = {name for name in INVENTORY if self.policy(name)["skip"]}
        self.assertEqual(skips, {"20010724-1.x", "20040208-2.x"})
        self.assertEqual(self.policy("eeprof-1.x")["flags"], ["-finstrument-functions"])
        self.assertEqual(self.policy("20021127-1.x")["flags"], ["-std=c99"])
        self.assertEqual(self.policy("va-arg-25.x")["flags"], ["-mpreferred-stack-boundary=4"])
        self.assertTrue(all(not self.policy(n)["compile_xfail"] and not self.policy(n)["run_xfail"] for n in INVENTORY))

    def test_targets_and_hooks(self):
        self.assertIsNone(self.policy("20010724-1.x", "mips-sgi-irix6.5")["skip"])
        self.assertTrue(self.policy("990413-2.x", "arm-linux-gnu")["skip"])
        self.assertTrue(self.policy("20010122-1.x", option="-O3 -fomit-frame-pointer")["skip"])
        self.assertEqual(self.policy("20010129-1.x", "i686-pc-linux-gnu")["flags"], ["-mtune=i686"])
        self.assertEqual(self.policy("20010129-1.x", "i686-pc-linux-gnu", "-O2 -m64")["flags"], [])
        self.assertTrue(self.policy("bf64-1.x", "mcore-elf-gnu")["run_xfail"])
        self.assertTrue(self.policy("20020720-1.x", "arm-elf-gnu")["compile_xfail"])
        self.assertIsNone(self.policy("20020720-1.x", "arm-elf-gnu", "-O0")["compile_xfail"])
        self.assertTrue(self.policy("941014-1.x", "arm-elf-gnu", "-O0 -mthumb")["run_xfail"])
        self.assertIsNone(self.policy("941014-1.x", "arm-elf-gnu", "-O2 -mthumb")["run_xfail"])
        self.assertTrue(self.policy("980709-1.x", "powerpc-ibm-aix5", "-O2 -msoft-float")["run_xfail"])
        self.assertIsNone(self.policy("931004-12.x", "powerpc-apple-darwin")["run_xfail"])

    def test_unknown_even_in_inactive_branch(self):
        script = INVENTORY["eeprof-1.x"] + '\nif {[istarget "mips-*"]} { set compile_only 1 }'
        with self.assertRaisesRegex(ValueError, "unrecognised"):
            torture.evaluate_x("eeprof-1.x", script, "x86_64-pc-linux-gnu", "-O2", INVENTORY)
        with self.assertRaisesRegex(ValueError, "unrecognised"):
            torture.evaluate_x("new.x", "return 0", "x86_64-pc-linux-gnu", "-O2", INVENTORY)
        self.assertEqual(torture.evaluate_x("eeprof-1.x", "# comment\n" + INVENTORY["eeprof-1.x"],
                                          "x86_64-pc-linux-gnu", "-O2", INVENTORY)["flags"], ["-finstrument-functions"])

    def test_unknown_orphan_script_fails_cli_with_reports(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "build-out") as scratch:
            root = Path(scratch)
            build = root / "configured/build/gcc"
            build.mkdir(parents=True)
            (build / "Makefile").write_text("target=x86_64-pc-linux-gnu\n")
            (build.parent.parent / "configure-command.json").write_text('{"environment": {}}')
            source = root / "source"
            suite = source / "gcc/testsuite/gcc.c-torture/execute"
            suite.mkdir(parents=True)
            (suite / "witness.c").write_text("int main(void) { return 0; }\n")
            (suite / "orphan.x").write_text("set compile_only 1\nreturn 0\n")
            out = root / "report"
            result = subprocess.run([sys.executable, str(ROOT / "gcc-direct/torture.py"),
                                     sys.executable, str(build), "--source", str(source), "--out", str(out)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            report = json.loads((out / "report.json").read_text())
            self.assertIn("unrecognised", report["x_files"][0]["error"])
            self.assertEqual(report["results"][0]["status"], "FAIL(cc1)")
            self.assertTrue((out / "report.md").is_file())
            self.assertFalse((out / "header-build").exists())

    def test_compile_xfail_and_unexpected_pass(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "build-out") as scratch:
            root = Path(scratch)
            source = root / "witness.c"
            source.write_text("int main(void) { return 0; }\n")
            policy = {"flags": [], "skip": None, "compile_xfail": "known compiler bug", "run_xfail": None}
            for index, (codes, status) in enumerate([([1], "XFAIL"), ([0, 1], "XFAIL"), ([0, 0], "FAIL(link)")]):
                with patch.object(torture, "run", side_effect=[{"returncode": code} for code in codes]):
                    result = torture.test_one(source, "-O2", policy, root / "cc1", root / "include",
                                              "/usr/bin/gcc", root / str(index), [])
                self.assertEqual(result["status"], status)
                if status.startswith("FAIL"):
                    self.assertIn("XPASS", result["reason"])

    def test_failure_stage_and_xfail_scope(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "build-out") as scratch:
            root = Path(scratch)
            source = root / "witness.c"
            source.write_text("int main(void) { return 0; }\n")
            for index, (codes, xfail, status) in enumerate([
                ([1], None, "FAIL(cc1)"), ([0, 1], None, "FAIL(link)"),
                ([0, 0, 124], None, "FAIL(run)"), ([0, 0, 1], "expected run failure", "XFAIL"),
                ([1], "expected run failure", "FAIL(cc1)"), ([0, 0, 0], "expected run failure", "FAIL(run)"),
                ([0, 0, 0], None, "PASS"),
            ]):
                policy = {"flags": ["-finstrument-functions"], "skip": None, "compile_xfail": None, "run_xfail": xfail}
                responses = [{"command": [], "returncode": code} for code in codes]
                with patch.object(torture, "run", side_effect=responses) as run:
                    result = torture.test_one(source, "-O2", policy, root / "cc1", root / "include",
                                              "/usr/bin/gcc", root / str(index), [])
                self.assertEqual(result["status"], status)
                self.assertIn("-finstrument-functions", run.call_args_list[0].args[0])
                if len(codes) > 1:
                    self.assertNotIn(str(source), run.call_args_list[1].args[0])


if __name__ == "__main__":
    unittest.main()
