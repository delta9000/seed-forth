#!/bin/sh
# plumbing-root.sh -- one traced run from hex0-seed to the GCC 4.0.4 fixed
# point, inside a root whose only starting executable is stage0-posix's
# 229-byte hex0-seed.
#
# Run from the repository root (needs bwrap, strace and the pinned inputs:
# build-out/plumbing-inputs, build-out/lexer-inputs/archives and the three
# archives in plumbing/chain.SOURCES):
#   tools/plumbing-root.sh [ROOT]          (default build-out/plumbing-root)
#
# The host copies the repository's tracked files (with submodules) into ROOT,
# hard-links the pinned archives, clears every execute bit except
# hex0-seed's, and adds /tmp, /dev/null, /proc and two symlinks, /bin and
# /usr/bin, to the not yet existing build-out/plumbing/bin.  Then, each
# under `strace -f -e trace=execve` and inside bwrap (a user namespace with
# ROOT as /, the host's /dev/null and a new /proc), four entries:
#
#   1. /hex0-seed /000-seed.hex0 /seed-forth
#   2. /seed-forth < tools/seed-cc-start.fth      (seed-cc and seed-ar)
#   3. seed-cc builds kaem
#   4. kaem runs plumbing/chain.kaem: plumbing stages 1-2, the lexers, bash,
#      then gcc-direct/chain.sh (binutils, stage C, stage D)
#
# Between entries 1 and 2 the host marks seed-forth executable (hex0-seed
# writes it without the bit).  Inside the root /bin/sh is the chain's bash
# once it exists, so even a `#!/bin/sh` script runs a program the chain built.
# The traces go to ROOT.trace/, with a summary of every program executed.
set -eu
cd "$(dirname "$0")/.."
REPO=$PWD
R=${1:-build-out/plumbing-root}
T=$R.trace
HEX0=vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed
command -v bwrap >/dev/null || { echo "plumbing-root: bwrap is required" >&2; exit 1; }
command -v strace >/dev/null || { echo "plumbing-root: strace is required" >&2; exit 1; }

rm -rf "$R" "$T"
mkdir -p "$R" "$T"
git ls-files -z --recurse-submodules | tar --null -T - -cf - | tar -xf - -C "$R"
mkdir -p "$R/build-out/plumbing-inputs" "$R/build-out/lexer-inputs/archives" \
  "$R/build-out/direct-gcc-inputs" "$R/build-out/stage-b-inputs" "$R/build-out/stage-c-inputs" \
  "$R/build-out/plumbing/bin" "$R/tmp" "$R/dev" "$R/proc" "$R/usr"
for f in build-out/plumbing-inputs/*.tar.* build-out/lexer-inputs/archives/*; do
  ln "$(readlink -f "$f")" "$R/$f" 2>/dev/null || cp "$(readlink -f "$f")" "$R/$f"
done
for f in direct-gcc-inputs/gcc-4.0.4-git-944765863e.tar stage-b-inputs/binutils-2.30.tar \
         stage-c-inputs/musl-1.1.24.tar.gz; do
  ln "$(readlink -f "build-out/$f")" "$R/build-out/$f" 2>/dev/null || cp "$(readlink -f "build-out/$f")" "$R/build-out/$f"
done
chmod -R a-x+X "$R"
cp "$HEX0" "$R/hex0-seed"
chmod 755 "$R/hex0-seed"
: > "$R/dev/null"
ln -s build-out/plumbing/bin "$R/bin"
ln -s ../build-out/plumbing/bin "$R/usr/bin"
inventory=$(find "$R" -type f -perm /111 | sed "s|^$R/||")
[ "$inventory" = hex0-seed ] || { echo "plumbing-root: unexpected executables: $inventory" >&2; exit 1; }
echo "plumbing-root: initial executable inventory: hex0-seed only ($(find "$R" -type f | wc -l) files)"

# enter N CMD...: run CMD inside the root, tracing execve into $T/execveN.txt.
enter() {
  n=$1
  shift
  strace -f -qq --seccomp-bpf -e trace=execve -o "$T/execve$n.txt" \
    bwrap --unshare-user --bind "$REPO/$R" / --dev-bind /dev/null /dev/null --proc /proc \
      --chdir / --clearenv --setenv PATH /bin --setenv HOME / --setenv LC_ALL C "$@"
}
start=$(date +%s)
enter 1 /hex0-seed /000-seed.hex0 /seed-forth > "$T/entry1.log" 2>&1
chmod 755 "$R/seed-forth"
enter 2 /seed-forth < "$R/tools/seed-cc-start.fth" > "$T/entry2.log" 2>&1
enter 3 /build-out/seed-cc/seed-cc -static vendor/mescc-tools/Kaem/kaem.c \
  vendor/mescc-tools/Kaem/variable.c vendor/mescc-tools/Kaem/kaem_globals.c \
  vendor/stage0-posix/mescc-tools-extra/M2libc/bootstrappable.c \
  -o build-out/plumbing/bin/kaem > "$T/entry3.log" 2>&1
status=0
enter 4 /build-out/plumbing/bin/kaem --verbose --strict --file plumbing/chain.kaem > "$T/entry4.log" 2>&1 || status=$?
echo "plumbing-root: entry 4 exit $status after $(( $(date +%s) - start )) s"

# Summary.  strace -f splits an execve that another process interrupts into
# an "<unfinished ...>" line holding the path and a "resumed" line holding the
# result; join them by pid, then count each path executed.
cat "$T"/execve[1-4].txt | awk '
/execve\(/ && /<unfinished/ { match($0, /execve\("[^"]*"/); p[$1] = substr($0, RSTART + 8, RLENGTH - 9); next }
/<\.\.\. execve resumed>/ { path = p[$1]; delete p[$1]; r = $0; sub(/.*= /, "", r); print (r ~ /^0/ ? "ok " : "fail ") path; next }
/execve\(/ { match($0, /execve\("[^"]*"/); path = substr($0, RSTART + 8, RLENGTH - 9); r = $0; sub(/.*= /, "", r); print (r ~ /^0/ ? "ok " : "fail ") path }
' > "$T/execve-joined.txt"
sed -n 's/^ok //p' "$T/execve-joined.txt" | sort | uniq -c | sort -rn > "$T/execve-programs.txt"
sed -n 's/^fail //p' "$T/execve-joined.txt" | sort | uniq -c | sort -rn > "$T/execve-failed.txt"
ok=$(grep -c '^ok ' "$T/execve-joined.txt" || true)
hosts=$(grep -c '^ok /usr/bin/bwrap$' "$T/execve-joined.txt" || true)
echo "plumbing-root: $ok successful execve calls ($hosts of them the host's bwrap entering the root), $(wc -l < "$T/execve-programs.txt") distinct paths; $(grep -c '^fail ' "$T/execve-joined.txt" || true) failed lookups of absent programs"
tail -20 "$T/entry4.log"
exit $status
