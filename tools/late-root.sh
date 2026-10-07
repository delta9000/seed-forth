#!/bin/bash
# late-root.sh -- run gcc-direct/late-tools.sh inside a finished plumbing root.
#
# Run from the repository root, after tools/plumbing-root.sh (needs bwrap,
# strace, and the plumbing/late.SOURCES archives in build-out/distfiles):
#   tools/late-root.sh [CHAIN-ROOT] [ROOT]
#       (defaults build-out/plumbing-root and build-out/late-root)
#
# CHAIN-ROOT is a root in which tools/plumbing-root.sh ran the whole chain
# from hex0-seed to the GCC 4.0.4 fixed point.  The host copies it to ROOT
# (CHAIN-ROOT is left as it was), adds late-tools.sh, plumbing/late.SOURCES,
# patches/ladder and the pinned archives, checks that every executable file
# in ROOT is one the chain wrote, then enters ROOT through bwrap under
# `strace -f -e trace=execve` and runs late-tools.sh with the chain's bash
# (with CHECK=1, then gcc-direct/late-check.sh: every package's make check).
# Inside, /bin and /usr/bin are the plumbing bin directory, so `#!/bin/sh`,
# system() and config.guess's /usr/bin/uname all reach programs the chain
# built.  The trace goes to ROOT.trace/.
set -eu
export LC_ALL=C
cd "$(dirname "$0")/.."
REPO=$PWD
C=${1:-build-out/plumbing-root}
R=${2:-build-out/late-root}
T=$R.trace
JOBS=${JOBS:-8}
command -v bwrap >/dev/null || { echo "late-root: bwrap is required" >&2; exit 1; }
command -v strace >/dev/null || { echo "late-root: strace is required" >&2; exit 1; }
[ -x "$C/build-out/chain/stage-d/prefix/bin/gcc" ] || { echo "late-root: no stage-D GCC in $C" >&2; exit 1; }

# The chain root's executables, before anything is added.
chain_exes=$(cd "$C" && find . -type f -perm /111 | sort)
rm -rf "$R" "$T"
mkdir -p "$T"
cp -a "$C" "$R"
rm -rf "$R/build-out/late"
mkdir -p "$R/build-out/distfiles" "$R/patches/ladder"
cp gcc-direct/late-tools.sh gcc-direct/late-check.sh "$R/gcc-direct/"
cp plumbing/late.SOURCES "$R/plumbing/late.SOURCES"
cp -R patches/ladder/. "$R/patches/ladder/"
chmod -R a-x+X "$R/gcc-direct/late-tools.sh" "$R/gcc-direct/late-check.sh" "$R/plumbing/late.SOURCES" "$R/patches/ladder"
grep -v '^#' plumbing/late.SOURCES | while read -r name _ _; do
  f=$(readlink -f "build-out/distfiles/$name")
  ln "$f" "$R/build-out/distfiles/$name" 2>/dev/null || cp "$f" "$R/build-out/distfiles/$name"
  chmod a-x "$R/build-out/distfiles/$name"
done
added=$(cd "$R" && find . -type f -perm /111 | sort | comm -13 <(echo "$chain_exes") -)
[ -z "$added" ] || { echo "late-root: unexpected new executables: $added" >&2; exit 1; }
echo "late-root: $(echo "$chain_exes" | wc -l) executables, all written by the chain run in $C"

# enter TRACE CMD...: run CMD inside the root (bwrap's minimal /dev, a new
# /proc), tracing execve into $T/TRACE.
enter() {
  local trace=$1
  shift
  strace -f -qq --seccomp-bpf -e trace=execve -o "$T/$trace" \
    bwrap --unshare-user --bind "$REPO/$R" / --dev /dev --proc /proc \
      --chdir / --clearenv --setenv PATH /bin --setenv HOME / --setenv LC_ALL C "$@"
}
start=$(date +%s)
status=0
enter execve.txt /bin/bash gcc-direct/late-tools.sh -j "$JOBS" > "$T/late.log" 2>&1 || status=$?
echo "late-root: exit $status after $(( $(date +%s) - start )) s"
# With CHECK=1, each package's own test suite, run by the late tools.  As
# after ladder/stage10.sh, /bin/sh is bash 5.2 here: the suites' #!/bin/sh
# scripts use unalias, <(...) and echo -e, which the chain's bash 2.05b lacks.
if [ "$status" = 0 ] && [ "${CHECK:-0}" = 1 ]; then
  EXTRA="--ro-bind $REPO/$R/build-out/late/usr/bin/bash /build-out/plumbing/bin/sh"
  enter check-execve.txt /bin/bash gcc-direct/late-check.sh -j "$JOBS" > "$T/check.log" 2>&1 || true
  cat "$R/build-out/late/check.txt"
fi

# Summary, as in tools/plumbing-root.sh: join split execve lines by pid.
awk '
/execve\(/ && /<unfinished/ { match($0, /execve\("[^"]*"/); p[$1] = substr($0, RSTART + 8, RLENGTH - 9); next }
/<\.\.\. execve resumed>/ { path = p[$1]; delete p[$1]; r = $0; sub(/.*= /, "", r); print (r ~ /^0/ ? "ok " : "fail ") path; next }
/execve\(/ { match($0, /execve\("[^"]*"/); path = substr($0, RSTART + 8, RLENGTH - 9); r = $0; sub(/.*= /, "", r); print (r ~ /^0/ ? "ok " : "fail ") path }
' "$T/execve.txt" > "$T/execve-joined.txt"
sed -n 's/^ok //p' "$T/execve-joined.txt" | sort | uniq -c | sort -rn > "$T/execve-programs.txt"
sed -n 's/^fail //p' "$T/execve-joined.txt" | sort | uniq -c | sort -rn > "$T/execve-failed.txt"
ok=$(grep -c '^ok ' "$T/execve-joined.txt" || true)
hosts=$(grep -c '^ok /usr/bin/bwrap$' "$T/execve-joined.txt" || true)
echo "late-root: $ok successful execve calls ($hosts of them the host's bwrap entering the root), $(wc -l < "$T/execve-programs.txt") distinct paths; $(grep -c '^fail ' "$T/execve-joined.txt" || true) failed lookups of absent programs"
tail -5 "$T/late.log"
exit $status
