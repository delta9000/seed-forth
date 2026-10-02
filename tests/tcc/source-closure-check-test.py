#!/usr/bin/env python3
"""Focused fail-closed tests for source-closure-check.py and the Forth starter.

Uses only Python as host harness and the original seed as compiler. No host C
compiler, preprocessor, assembler, or linker participates in any test.
"""
from pathlib import Path
import importlib.util
import json
import shutil
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('source_closure', Path(__file__).with_name('source-closure-check.py'))
closure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(closure)


class ClosureCheck(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sf-tcc-closure-test-')
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def source_tree(self):
        repo, sources = self.root / 'repo', self.root / 'sources'
        repo.mkdir()
        sources.mkdir()
        for name in closure.FORTH_FILES:
            path = repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'\\ reviewed Forth source\n')
        source = b'int main(void) { return 0; }\n'
        (sources / 'direct-input.c').write_bytes(source)
        (sources / 'source-manifest.json').write_text(json.dumps({'direct-input.c': closure.sha(source)}))
        return repo, sources

    def audit(self, tail):
        path = self.root / 'exec.log'
        path.write_text('10 execve("/usr/bin/unshare", ["unshare"], 0x1) = 0\n'
                        '10 execve("/usr/sbin/chroot", ["chroot"], 0x1) = 0\n'
                        '10 execve("/seed-forth", ["/seed-forth"], 0x1) = 0\n' + tail)
        return closure.audit_exec(path)

    def test_current_seed(self):
        seed = (ROOT / 'seed-forth').read_bytes()
        self.assertEqual(closure.sha(seed), closure.SEED_SHA256)
        closure.static_amd64(seed, 'seed-forth')

    def test_relative_path_rejections(self):
        for name in ('', '/root', '../root', 'a/../b', 'a//b', './a', 'a/', 'a\\b'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                closure.relative(name)

    def test_duplicate_json_key(self):
        path = self.root / 'bad.json'
        path.write_text('{"x": 1, "x": 2}')
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            closure.read_json(path)

    def test_verified_source_inventory(self):
        repo, sources = self.source_tree()
        self.assertEqual(len(closure.source_inputs(repo, sources)), len(closure.FORTH_FILES) + 1)
        (sources / 'direct-input.c').write_bytes(b'changed\n')
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            closure.source_inputs(repo, sources)

    def test_hidden_file_rejected(self):
        repo, sources = self.source_tree()
        (sources / 'concealed').write_bytes(b'\x7fELF\0')
        with self.assertRaisesRegex(ValueError, 'unmanifested'):
            closure.source_inputs(repo, sources)

    def test_manifested_binary_rejected(self):
        repo, sources = self.source_tree()
        payload = b'\x7fELF\0hidden'
        (sources / 'direct-input.c').write_bytes(payload)
        (sources / 'source-manifest.json').write_text(json.dumps({'direct-input.c': closure.sha(payload)}))
        with self.assertRaisesRegex(ValueError, 'binary'):
            closure.source_inputs(repo, sources)

    def test_source_symlink_rejected(self):
        repo, sources = self.source_tree()
        (sources / 'link').symlink_to('direct-input.c')
        with self.assertRaisesRegex(ValueError, 'symlink'):
            closure.source_inputs(repo, sources)

    def test_pnut_compiler_rejected(self):
        with self.assertRaisesRegex(ValueError, 'pnut compiler'):
            closure.source_text(b'int main(void){}', 'pnut.c')

    def test_dynamic_elf_rejected(self):
        seed = bytearray((ROOT / 'seed-forth').read_bytes())
        phoff = struct.unpack_from('<Q', seed, 32)[0]
        struct.pack_into('<I', seed, phoff, 3)
        with self.assertRaisesRegex(ValueError, 'dynamic'):
            closure.static_amd64(seed, 'bad')

    def test_truncated_elf_rejected(self):
        with self.assertRaises(ValueError):
            closure.static_amd64((ROOT / 'seed-forth').read_bytes()[:80], 'bad')

    def test_exec_inventory_reads_permissions(self):
        (self.root / 'source').write_bytes(b'source')
        (self.root / 'source').chmod(0o444)
        (self.root / 'seed').write_bytes(b'seed')
        (self.root / 'seed').chmod(0o555)
        self.assertEqual(closure.inventory(self.root), ['seed'])

    def test_exact_exec_audit(self):
        events = self.audit('11 execve("./seed-forth", ["./seed-forth"], NULL) = 0\n')
        self.assertEqual(len(events), 2)

    def test_exec_audit_rejects_foreign_attempts(self):
        for line in ('11 execve("/bin/sh", ["sh"], NULL) = 0\n',
                     '11 execve("/bin/sh", ["sh"], NULL) = -1 ENOENT\n',
                     '11 execveat(3, "", [], NULL, AT_EMPTY_PATH) = 0\n',
                     '11 execve("./seed-forth", ["./seed-forth"], NULL <unfinished ...>\n',
                     ''):
            with self.subTest(line=line), self.assertRaises(ValueError):
                self.audit(line)

    def launcher_tree(self, source):
        root = self.root / 'launcher'
        root.mkdir()
        shutil.copyfile(ROOT / 'seed-forth', root / 'seed-forth')
        (root / 'seed-forth').chmod(0o555)
        for name in closure.FORTH_FILES:
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        source_dir = root / 'build-out/tcc-sources'
        (source_dir / 'libc64/include').mkdir(parents=True)
        (source_dir / 'direct-input.c').write_text(source)
        return root

    def run_launcher(self, root):
        with (root / closure.START).open('rb') as stdin:
            return subprocess.run([str(root / 'seed-forth')], cwd=root, stdin=stdin,
                                  capture_output=True, timeout=20)

    def test_launcher_builds_tiny_program(self):
        root = self.launcher_tree('int main(void) { return 37; }\n')
        result = self.run_launcher(root)
        self.assertEqual(result.returncode, 0, result.stderr)
        product = root / closure.PRODUCT
        closure.static_amd64(product.read_bytes(), 'test program')
        self.assertEqual(subprocess.run([str(product)]).returncode, 37)
        self.assertFalse((root / 'build-out/tcc-seed.partial').exists())
        self.assertEqual((root / 'build-out/tcc-compile.stdout').read_bytes(), b'')

    def test_launcher_missing_source_fails(self):
        root = self.launcher_tree('int main(void) { return 0; }\n')
        (root / 'build-out/tcc-sources/direct-input.c').unlink()
        self.assertEqual(self.run_launcher(root).returncode, 104)
        self.assertFalse((root / closure.PRODUCT).exists())

    def test_launcher_checks_child_status_and_removes_stale_product(self):
        root = self.launcher_tree('int main(void) { return 0; }\n')
        driver = root / 'tools/tcc-compile.fth'
        driver.write_bytes(b'[lit] 7 die\n' + driver.read_bytes())
        (root / closure.PRODUCT).write_bytes(b'stale')
        self.assertEqual(self.run_launcher(root).returncode, 114)
        self.assertFalse((root / closure.PRODUCT).exists())

    def test_launcher_rejects_forth_diagnostics(self):
        root = self.launcher_tree('int main(void) { return 0; }\n')
        driver = root / 'tools/tcc-compile.fth'
        driver.write_bytes(b'undefined-tcc-test-word\n' + driver.read_bytes())
        self.assertEqual(self.run_launcher(root).returncode, 115)
        self.assertFalse((root / closure.PRODUCT).exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
