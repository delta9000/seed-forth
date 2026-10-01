#!/bin/sh
# Milestone A: run the whole ladder in a root whose only initial executable is
# stage0-posix's 229-byte hex0-seed.  Inside it: hex0-seed builds seed-forth
# from 000-seed.hex0, the seed route reaches tcc, tools/ladder.recipe reaches
# musl and the first tools, ladder/stage10.sh carries on with bash, stage11.sh
# builds binutils and GCC (gcc64 stages 4-10), stage12.sh builds Linux.
#
# The host only prepares the root (copies sources, hard-links distfiles) and
# enters it through a user + mount namespace with /dev/null and /proc bound in
# (musl's fchmodat uses /proc/self/fd).  The
# host kernel is the substrate.  Run from the repository root:
#   tools/chain-root.sh            fresh root, run everything
#   tools/chain-root.sh --resume   keep the root, rerun ladder/stage10-12.sh
# Then tools/boot-linux.sh boots the result.
set -eu
cd "$(dirname "$0")/.."
R=build-out/chain-root
HEX0=vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed
ulimit -f 4194304                      # no single file over 4 GiB
unshare -rm true || { echo "chain-root: SKIP: no user/mount namespaces" >&2; exit 77; }

if [ "${1:-}" != --resume ]; then
    rm -rf build-out/chain-root
    python3 - "$R" "$HEX0" <<'PY'
import pathlib, shutil, sys, os
root = pathlib.Path('.').resolve()
dest, hex0 = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
dest.mkdir(parents=True)
files = [root / '000-seed.hex0'] + list(root.glob('[0-9][0-9][0-9]-*.fth'))
for d in ('tools', 'ladder', 'patches/amd64/exact', 'patches/gcc64', 'patches/ladder', 'tests/pnut/amd64',
          'tests/gcc64', 'gcc64'):
    files += [p for p in (root / d).rglob('*') if p.is_file()]
files += [root / l.split()[1] for l in (root / 'tools/amd64-inputs.sha256').read_text().splitlines()]
for src in files:
    t = dest / src.relative_to(root)
    t.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, t)
    t.chmod(0o644)
dist = dest / 'build-out/distfiles'
dist.mkdir(parents=True)
for f in (root / 'build-out/distfiles').iterdir():
    os.link(f, dist / f.name)          # hard links: same bytes, no copy
shutil.copyfile(hex0, dest / 'hex0-seed')
(dest / 'hex0-seed').chmod(0o755)
for d in ('tmp', 'dev', 'proc'):
    (dest / d).mkdir()
(dest / 'dev/null').touch()
ex = sorted(str(p.relative_to(dest)) for p in dest.rglob('*')
            if p.is_file() and p.stat().st_mode & 0o111 and 'distfiles' not in p.parts)
assert ex == ['hex0-seed'], ex
print('chain-root: initial executable inventory: hex0-seed only')
PY
fi

# Inside the namespace: bind /dev/null, then chroot.  Everything after the
# chroot runs only programs the chain built.
unshare -rm sh -c '
    mount --bind /dev/null "$1/dev/null"
    exec chroot "$1" /hex0-seed /000-seed.hex0 /seed-forth
' sh "$PWD/$R"
chmod 755 "$R/seed-forth"
unshare -rm sh -c '
    set -e
    mount --bind /dev/null "$1/dev/null"
    mount --rbind /proc "$1/proc"
    cd "$1"
    if [ "$2" != --resume ]; then
        chroot "$1" /seed-forth < "$1/tools/amd64-start.fth" | tail -1
        chroot "$1" /build-out/amd64-runner --recipe /tools/ladder.recipe
    fi
    chroot "$1" /build-out/pnut-amd64/usr/bin/bash /ladder/stage10.sh
    chroot "$1" /usr/bin/bash /ladder/stage11.sh
    exec chroot "$1" /usr/bin/bash /ladder/stage12.sh
' sh "$PWD/$R" "${1:-}"
