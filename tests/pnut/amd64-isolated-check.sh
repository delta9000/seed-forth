#!/usr/bin/env bash
# Verification harness only: prepare a source-only root, then deny every host
# executable by its absence. The initial seed is the only executable present.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
DEST=$ROOT/build-out/amd64-isolated-root
if ! unshare -rm true 2>/dev/null; then
    echo 'amd64-isolated-check: SKIP: user/mount namespaces unavailable'
    exit 77
fi
python3 - "$ROOT" "$DEST" <<'PY'
import pathlib, shutil, sys
root, dest = map(pathlib.Path, sys.argv[1:])
if dest.exists():
    shutil.rmtree(dest)
dest.mkdir(parents=True)
files = list(root.glob('[0-9][0-9][0-9]-*.fth'))
files += [root / 'tools' / name for name in ('amd64-start.fth', 'amd64-syscalls.fth', 'amd64-runner.c', 'amd64.recipe', 'amd64-inputs.sha256', 'amd64-libc.sha256', 'flatten-includes.c', 'simple-patch.c')]
for directory in ('patches/amd64/exact', 'tests/pnut/amd64'):
    files += [p for p in (root / directory).rglob('*') if p.is_file()]
files += [root / line.split()[1] for line in (root / 'tools/amd64-inputs.sha256').read_text().splitlines()]
for src in files:
    target = dest / src.relative_to(root)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, target)
    target.chmod(0o644)
shutil.copyfile(root / 'seed-forth', dest / 'seed-forth')
(dest / 'seed-forth').chmod(0o755)
(dest / 'tmp').mkdir()
executables = [str(p.relative_to(dest)) for p in dest.rglob('*') if p.is_file() and p.stat().st_mode & 0o111]
assert executables == ['seed-forth'], executables
assert not (dest / 'bin').exists() and not (dest / 'usr').exists()
print('amd64-isolated-check: initial executable inventory: seed-forth only')
PY
unshare -rm chroot "$DEST" /seed-forth < "$DEST/tools/amd64-start.fth"
python3 - "$DEST" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
log = (root / 'build-out/pnut-amd64/executables.log').read_text().splitlines()
assert log
# Runtime inventory is emitted by the runner immediately before each fork.
# The filesystem isolation, not this report, excludes host execution.
print(f'amd64-isolated-check: PASS: {len(log)} child executions; no host executables available')
print('amd64-isolated-check: executed paths:')
for path in sorted(set(log)):
    print('  ' + path)
PY
