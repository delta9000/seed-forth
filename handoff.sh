#!/usr/bin/env bash
# handoff.sh — hand the Forth route over to stage0-posix's own AMD64 recipe
# at the point where M2-Planet exists, and check the result against
# stage0-posix's published amd64.answers.
#
# Platform: x86-64 (amd64) Linux only.  About 75 s (30 s of it bootstrap.sh).
#
# stage0-posix (vendor/stage0-posix, Release_1.9.1 = 45d90f5) builds its
# AMD64/bin set in three kaem scripts.  AMD64/mescc-tools-mini-kaem.kaem
# Phases 1-5 go hex0 -> hex1 -> hex2-0 -> catm -> M0 -> cc_amd64 -> M2
# (M2-Planet bd2fe4b, compiled by cc_amd64); Phases 6-11 use M2 (with catm,
# M0 and hex2-0) to build blood-elf-0, M1-0, hex2-1, bin/M1, bin/hex2 and
# bin/kaem; AMD64/kaem.run then builds M2-Mesoplanet, blood-elf, get_machine,
# M2-Planet and mescc-tools-extra and runs `sha256sum -c amd64.answers`.
# This script replaces Phases 0-5 with the Forth route and runs the rest of
# stage0-posix's recipe unchanged.
#
# WHAT THIS TRUSTS (everything that touches a byte of the outputs):
#   - everything bootstrap.sh trusts (its header lists it): the 229-byte
#     hex0-seed from vendor/stage0-posix/bootstrap-seeds, this repository's
#     sources, the vendored M2-Planet/mescc-tools sources, the Linux kernel,
#     bash and cat;
#   - SOURCE files of vendor/stage0-posix and its nested submodules at the
#     commits stage0-posix records (checked in stage 0): the AMD64 kaem
#     scripts, M2libc, M2-Planet bd2fe4b, mescc-tools 5adfbf3,
#     mescc-tools-extra, M2-Mesoplanet.  bootstrap-seeds is not even copied
#     into the work tree: of stage0-posix's seeds only hex0-seed runs (via
#     bootstrap.sh), and none of kaem-0, hex0, hex1, hex2-0, catm, M0,
#     cc_amd64 or stage0's own M2 is built or run;
#   - host bash runs Phases 6-11 of mescc-tools-mini-kaem.kaem (the file
#     says it "can also be run by kaem or any other shell"), selected from
#     the Phase-6 banner on by a bash loop; two 2-line bash scripts stand in
#     for M0 (-> the Forth-route M1) and hex2-0 (-> the Forth-route hex2);
#     cat builds Phase 5's M2-0.c, cp copies the stage0-posix sources, and
#     mkdir/rm/chmod/printf manage files.
#   - Not in provenance, used only to check and report: sha256sum, cmp, wc,
#     grep, sed, awk, cut, tr, git (reads submodule commits).
#   No host C compiler, assembler or linker runs.
#
# WHAT THIS PROVES (fails loudly otherwise)
#   1. bootstrap.sh (GCC-free) produces cc-out-v2, cc-out-v3, M1 and hex2.
#   2. Route A.  The Forth-route stand-ins for stage0's Phases 0-5:
#        artifact/catm  = mescc-tools-extra/catm.c compiled by cc-out-v3;
#        artifact/M0    -> the Forth-route M1;  artifact/hex2-0 -> hex2;
#        artifact/M2    = Phase 5's own input, M2-0.c (M2-Planet bd2fe4b +
#                         M2libc's bootstrap.c), compiled by cc-out-v3 in
#                         --bootstrap-mode instead of by cc_amd64.
#      stage0-posix's Phases 6-11 and kaem.run then run unchanged, under
#      `env -i`, and all 19 AMD64/bin binaries match amd64.answers (checked
#      by the recipe's own sha256sum -c and again by the host's).
#   3. Route B.  The plainest substitution: artifact/M2 = cc-out-v2 as is
#      (M2-Planet 0a67a68, not stage0's bd2fe4b).  The recipe builds every
#      binary; the ones compiled directly by artifact/M2 differ from
#      amd64.answers (0a67a68 generates different code), the ones built by
#      the recipe's own bin/M2-Planet (bd2fe4b source) already match.
#      One more generation: artifact/M2 = route B's bin/M2-Planet; the
#      recipe now matches all 19, and every binary equals route A's.
#   4. Optional, with LIVE_BOOTSTRAP=<a live-bootstrap checkout>: the first
#      thing live-bootstrap's seed/seed.kaem does after stage0-posix, i.e.
#      build seed/configurator.c and seed/script-generator.c with
#      M2-Mesoplanet and `sha256sum -c` them against live-bootstrap's own
#      *.amd64.checksums, done with route A's AMD64/bin.
#
# Output: $BUILDROOT/A/stage0-posix/AMD64/bin (route A's bin set),
# SHA256SUMS in $BUILDROOT; $BUILDROOT is wiped at the start of every run.
# Exit 77 (and a SKIP line) when stage0-posix's nested submodules are not
# checked out; 1 on any failure.
#
# Env overrides:
#   BUILDROOT       default ./build-out/handoff
#   BOOTSTRAP_OUT   reuse an existing bootstrap.sh output directory instead of
#                   running bootstrap.sh; its SHA256SUMS must verify (that
#                   catches corruption, not staleness: rebuild if in doubt)
#   ROUTE_B         1 (default) | 0: skip stage 3 (route B, ~30 s)
#   LIVE_BOOTSTRAP  path to a live-bootstrap checkout (stage 4; optional)
#
# Prerequisite (network, once):
#   git -C vendor/stage0-posix submodule update --init \
#       M2-Planet M2libc mescc-tools mescc-tools-extra M2-Mesoplanet
#   (if git.savannah.nongnu.org is unreachable, first run
#    git -C vendor/stage0-posix config submodule.mescc-tools.url \
#        https://github.com/oriansj/mescc-tools.git)

set -euo pipefail
cd "$(dirname "$0")"
ROOT=$PWD
BUILDROOT=${BUILDROOT:-$ROOT/build-out/handoff}
S0SRC=$ROOT/vendor/stage0-posix

T0=$SECONDS
step() { printf '\n=== %s: %s  [t=%ds]\n' "$1" "$2" $((SECONDS - T0)); }
fail() { printf 'handoff: FAIL: %s\n' "$1" >&2; exit 1; }
ok()   { printf '  ok: %s\n' "$1"; }
h()    { sha256sum < "$1" | cut -c1-16; }

# ---------------------------------------------------------------------------
step 0 "prerequisites"
# ---------------------------------------------------------------------------
case "${OSTYPE:-}/${HOSTTYPE:-}" in
    linux*/x86_64) ;;
    *) fail "amd64 Linux only (this host: OSTYPE=${OSTYPE:-?} HOSTTYPE=${HOSTTYPE:-?})" ;;
esac
[ -f "$S0SRC/amd64.answers" ] || fail "vendor/stage0-posix not initialized (git submodule update --init --recursive)"
for sm in AMD64 M2-Planet M2libc mescc-tools mescc-tools-extra M2-Mesoplanet; do
    line=$(git -C "$S0SRC" submodule status "$sm" 2>/dev/null) || fail "cannot query vendor/stage0-posix/$sm"
    case "$line" in
        -*) echo "handoff: SKIP: vendor/stage0-posix/$sm is not checked out; see 'Prerequisite' at the top of $0"
            exit 77 ;;
        +*) fail "vendor/stage0-posix/$sm is not at stage0-posix's recorded commit: $line" ;;
        U*) fail "vendor/stage0-posix/$sm has merge conflicts" ;;
    esac
    ok "stage0-posix/$(echo "$line" | awk '{print $2, substr($1,1,7), $3}')"
done
ok "stage0-posix $(git -C "$S0SRC" rev-parse --short=7 HEAD)"

mkdir -p "$BUILDROOT"
BUILDROOT=$(cd "$BUILDROOT" && pwd)
rm -rf "$BUILDROOT"/{A,B1,B2,bootstrap,live-bootstrap,SHA256SUMS}

# ---------------------------------------------------------------------------
step 1 "the Forth route: bootstrap.sh (GCC-free)"
# ---------------------------------------------------------------------------
if [ -n "${BOOTSTRAP_OUT:-}" ]; then
    O=$(cd "$BOOTSTRAP_OUT" && pwd)
    (cd "$O" && sha256sum -c --quiet SHA256SUMS) || fail "$O/SHA256SUMS does not verify"
    ok "reusing $O (SHA256SUMS verified)"
else
    BUILDROOT=$BUILDROOT/bootstrap ./bootstrap.sh > "$BUILDROOT/bootstrap.log" 2>&1 \
        || { tail -20 "$BUILDROOT/bootstrap.log" >&2; fail "bootstrap.sh failed (log: $BUILDROOT/bootstrap.log)"; }
    O=$BUILDROOT/bootstrap/out
    ok "bootstrap.sh PASS (log: $BUILDROOT/bootstrap.log)"
fi
for f in cc-out-v2 cc-out-v3 M1 hex2; do
    [ -x "$O/$f" ] || fail "$O/$f missing"
    ok "$f  sha256 $(h "$O/$f")..."
done

# new_tree <dir>: a fresh copy of the stage0-posix SOURCES the AMD64 recipe
# reads (no bootstrap-seeds, no binaries).
new_tree() {
    local T=$1/stage0-posix f
    mkdir -p "$T"
    for f in AMD64 M2libc M2-Planet M2-Mesoplanet mescc-tools mescc-tools-extra \
             amd64.answers after.kaem; do
        cp -a "$S0SRC/$f" "$T/"
    done
    for f in "$T"/AMD64/bin/* "$T"/AMD64/artifact/*; do
        case "${f##*/}" in
            README|placeholder) rm -f "$f" ;;
            *) fail "vendor/stage0-posix is not clean: ${f#"$T"/} (was stage0's chain run inside vendor/?)" ;;
        esac
    done
}

# standins <tree>: catm, M0, hex2-0 for Phases 6-8 (M2 is set per route).
standins() {
    local T=$1/stage0-posix L=$1/stage0-posix/M2libc A=$1/stage0-posix/AMD64/artifact
    "$O/cc-out-v3" --architecture amd64 \
        -f "$L/sys/types.h" -f "$L/stddef.h" -f "$L/sys/utsname.h" \
        -f "$L/amd64/linux/unistd.c" -f "$L/amd64/linux/fcntl.c" -f "$L/fcntl.c" \
        -f "$L/ctype.c" -f "$L/stdlib.c" -f "$L/stdarg.h" -f "$L/stdio.h" \
        -f "$L/stdio.c" -f "$L/bootstrappable.c" -f "$T/mescc-tools-extra/catm.c" \
        -o "$A/catm-forth.M1" || fail "cc-out-v3 failed on catm.c"
    "$O/M1" --architecture amd64 --little-endian -f "$L/amd64/amd64_defs.M1" \
        -f "$L/amd64/libc-full.M1" -f "$A/catm-forth.M1" -o "$A/catm-forth.hex2"
    "$O/hex2" --architecture amd64 --little-endian --base-address 0x00600000 \
        -f "$L/amd64/ELF-amd64.hex2" -f "$A/catm-forth.hex2" -o "$A/catm"
    printf '#!%s\n# stand-in for stage0 M0: the Forth-route M1\nexec %q --architecture amd64 --little-endian -f "$1" -o "$2"\n' \
        "$BASH" "$O/M1" > "$A/M0"
    printf '#!%s\n# stand-in for stage0 hex2-0: the Forth-route hex2\nexec %q --architecture amd64 --little-endian --base-address 0x00600000 -f "$1" -o "$2"\n' \
        "$BASH" "$O/hex2" > "$A/hex2-0"
    chmod 755 "$A/catm" "$A/M0" "$A/hex2-0"
}

# recipe <dir>: stage0-posix's Phases 6-11 (mini-kaem, from the Phase-6
# banner on, run by bash) and then kaem.run with the bin/kaem Phase 11
# built, exactly as kaem.amd64 runs it.  Returns kaem.run's exit status
# (non-zero when its own `sha256sum -c amd64.answers` fails).
recipe() {
    local T=$1/stage0-posix line on=0 rc=0
    while IFS= read -r line || [ -n "$line" ]; do
        [[ $line == *'Phase-6 Build blood-elf-0'* ]] && on=1
        [ "$on" = 1 ] && printf '%s\n' "$line"
    done < "$T/AMD64/mescc-tools-mini-kaem.kaem" > "$1/phases-6-11.kaem"
    [ -s "$1/phases-6-11.kaem" ] || fail "no Phase-6 banner in mescc-tools-mini-kaem.kaem"
    (cd "$T" && env -i PATH=/nonexistent "$BASH" -e "$1/phases-6-11.kaem") > "$1/phases-6-11.log" 2>&1 \
        || { tail -20 "$1/phases-6-11.log" >&2; fail "Phases 6-11 failed in $1 (log: $1/phases-6-11.log)"; }
    (cd "$T" && env -i PATH=/nonexistent ./AMD64/bin/kaem --verbose --strict --file ./AMD64/kaem.run) \
        > "$1/kaem.run.log" 2>&1 || rc=$?
    local n
    n=$(awk '{print $2}' "$T/amd64.answers" | while read -r f; do [ -f "$T/$f" ] || echo "$f"; done)
    [ -z "$n" ] || { tail -20 "$1/kaem.run.log" >&2; fail "kaem.run built no $n (log: $1/kaem.run.log)"; }
    return "$rc"
}

# answers <dir>: print the host's sha256sum -c against amd64.answers and set
# MATCH to the number of matching binaries.
answers() {
    local T=$1/stage0-posix
    (cd "$T" && sha256sum -c amd64.answers 2>/dev/null || true) > "$1/answers.txt"
    MATCH=$(grep -c ': OK$' "$1/answers.txt" || true)
}

# ---------------------------------------------------------------------------
step 2 "route A: Forth-route stand-ins for stage0 Phases 0-5, then stage0's recipe"
# ---------------------------------------------------------------------------
W=$BUILDROOT/A; T=$W/stage0-posix; A=$T/AMD64/artifact
new_tree "$W"
standins "$W"
ok "artifact/catm (catm.c by cc-out-v3), artifact/M0 -> M1, artifact/hex2-0 -> hex2"
# Phase 5's input, as mescc-tools-mini-kaem.kaem's catm builds it.
(cd "$T" && cat ./M2libc/amd64/linux/bootstrap.c ./M2-Planet/cc.h ./M2libc/bootstrappable.c \
    ./M2-Planet/cc_globals.c ./M2-Planet/cc_reader.c ./M2-Planet/cc_strings.c \
    ./M2-Planet/cc_types.c ./M2-Planet/cc_emit.c ./M2-Planet/cc_core.c \
    ./M2-Planet/cc_macro.c ./M2-Planet/cc.c) > "$A/M2-0.c"
"$O/cc-out-v3" --architecture amd64 --bootstrap-mode -f "$A/M2-0.c" -o "$A/M2-0.M1" \
    || fail "cc-out-v3 failed on M2-0.c"
"$O/M1" --architecture amd64 --little-endian -f "$T/M2libc/amd64/amd64_defs.M1" \
    -f "$T/M2libc/amd64/libc-core.M1" -f "$A/M2-0.M1" -o "$A/M2-0.hex2"
"$O/hex2" --architecture amd64 --little-endian --base-address 0x00600000 \
    -f "$T/M2libc/amd64/ELF-amd64.hex2" -f "$A/M2-0.hex2" -o "$A/M2"
chmod 755 "$A/M2"
ok "artifact/M2 (M2-Planet bd2fe4b, M2-0.c compiled by cc-out-v3): $(wc -c < "$A/M2") bytes, sha256 $(h "$A/M2")..."
t=$SECONDS
recipe "$W" || { tail -30 "$W/kaem.run.log" >&2; fail "route A: kaem.run failed (its sha256sum -c amd64.answers?) (log: $W/kaem.run.log)"; }
answers "$W"
[ "$MATCH" = "$(wc -l < "$T/amd64.answers")" ] || { cat "$W/answers.txt" >&2; fail "route A: only $MATCH binaries match amd64.answers"; }
ok "stage0's Phases 6-11 + kaem.run: ${MATCH}/$(wc -l < "$T/amd64.answers") match amd64.answers ($((SECONDS - t))s; recipe's own sha256sum -c passed too)"
ok "bin/M2-Planet sha256 $(sha256sum < "$T/AMD64/bin/M2-Planet" | cut -d' ' -f1)"
(cd "$T" && sha256sum $(awk '{print $2}' amd64.answers)) > "$BUILDROOT/SHA256SUMS"

# ---------------------------------------------------------------------------
step 3 "route B: artifact/M2 = cc-out-v2 (M2-Planet 0a67a68) as is"
# ---------------------------------------------------------------------------
if [ "${ROUTE_B:-1}" = 0 ]; then
    ok "skipped (ROUTE_B=0)"
else
    W=$BUILDROOT/B1; T=$W/stage0-posix
    new_tree "$W"; standins "$W"
    cp "$O/cc-out-v2" "$T/AMD64/artifact/M2"
    rc=0; recipe "$W" || rc=$?
    answers "$W"
    ok "kaem.run exit $rc (its sha256sum -c); ${MATCH}/$(wc -l < "$T/amd64.answers") match amd64.answers"
    ok "  match:  $(grep ': OK$' "$W/answers.txt" | sed 's|^AMD64/bin/||; s|: OK$||' | tr '\n' ' ')"
    ok "  differ: $(grep -v ': OK$' "$W/answers.txt" | sed 's|^AMD64/bin/||; s|: .*$||' | tr '\n' ' ')"
    ok "bin/M2-Planet (bd2fe4b source, built by 0a67a68) sha256 $(sha256sum < "$T/AMD64/bin/M2-Planet" | cut -d' ' -f1)"

    step 3b "route B, one generation later: artifact/M2 = route B's bin/M2-Planet"
    W=$BUILDROOT/B2; T=$W/stage0-posix
    new_tree "$W"; standins "$W"
    cp "$BUILDROOT/B1/stage0-posix/AMD64/bin/M2-Planet" "$T/AMD64/artifact/M2"
    recipe "$W" || { tail -30 "$W/kaem.run.log" >&2; fail "route B2: kaem.run failed (log: $W/kaem.run.log)"; }
    answers "$W"
    [ "$MATCH" = "$(wc -l < "$T/amd64.answers")" ] || { cat "$W/answers.txt" >&2; fail "route B2: only $MATCH binaries match amd64.answers"; }
    for f in $(awk '{print $2}' "$T/amd64.answers"); do
        cmp -s "$T/$f" "$BUILDROOT/A/stage0-posix/$f" || fail "route B2 $f != route A $f"
    done
    ok "${MATCH}/$(wc -l < "$T/amd64.answers") match amd64.answers, byte-identical to route A"
fi

# ---------------------------------------------------------------------------
step 4 "live-bootstrap's first step (optional: LIVE_BOOTSTRAP)"
# ---------------------------------------------------------------------------
if [ -z "${LIVE_BOOTSTRAP:-}" ]; then
    ok "skipped (set LIVE_BOOTSTRAP=<live-bootstrap checkout> to run it)"
else
    LB=$(cd "$LIVE_BOOTSTRAP" && pwd)
    T=$BUILDROOT/A/stage0-posix
    W=$BUILDROOT/live-bootstrap; mkdir -p "$W/tmp"
    ok "live-bootstrap $(git -C "$LB" rev-parse --short=7 HEAD 2>/dev/null || echo '?'), its seed/stage0-posix pin: $(git -C "$LB" ls-tree HEAD seed/stage0-posix 2>/dev/null | awk '{print substr($3,1,7)}')"
    for p in configurator script-generator; do
        cp "$LB/seed/$p.c" "$LB/seed/$p.amd64.checksums" "$W/"
        # as seed/seed.kaem: M2-Mesoplanet --architecture ${ARCH} -f $p.c -o $p
        (cd "$W" && env -i PATH="$T/AMD64/bin" M2LIBC_PATH="$T/M2libc" TMPDIR="$W/tmp" \
            M2-Mesoplanet --architecture amd64 -f "$p.c" -o "$p") > "$W/$p.log" 2>&1 \
            || fail "M2-Mesoplanet failed on $p.c (log: $W/$p.log)"
        (cd "$W" && "$T/AMD64/bin/sha256sum" -c "$p.amd64.checksums") | sed 's/^/    /' \
            || fail "$p does not match live-bootstrap's $p.amd64.checksums"
    done
    ok "live-bootstrap's seed binaries built with route A's tools match its amd64 checksums"
fi

step 5 "done"
echo "  AMD64/bin set: $BUILDROOT/A/stage0-posix/AMD64/bin  (SHA256SUMS: $BUILDROOT/SHA256SUMS)"
echo
echo "handoff: PASS in $((SECONDS - T0))s — the Forth route, standing in for stage0-posix's"
echo "hex1 -> hex2 -> M0 -> cc_amd64 -> M2 phases, yields all $(wc -l < "$S0SRC/amd64.answers") amd64.answers binaries byte for byte"
