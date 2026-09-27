#!/usr/bin/env bash
# handoff.sh — hand the Forth route over to stage0-posix's own AMD64 and x86
# recipes at the point where M2-Planet exists, and check the results against
# stage0-posix's published amd64.answers and x86.answers.
#
# Platform: an x86-64 (amd64) Linux host.  The x86 hand-off also needs the
# kernel's IA-32 emulation (CONFIG_IA32_EMULATION, on in stock distribution
# kernels), because stage0's x86 recipe runs 32-bit i386 binaries; stage 0
# tests it and skips x86 (exit 77 at the end) when it is missing.  About
# 75 s for amd64 (30 s of it bootstrap.sh); x86 adds ~3.5 min on the
# reference VM, almost all of it kernel time inside stage0's own i386
# binaries (stage0's own x86 chain is as slow there).
#
# stage0-posix (vendor/stage0-posix, Release_1.9.1 = 45d90f5) builds its
# AMD64/bin set in three kaem scripts.  AMD64/mescc-tools-mini-kaem.kaem
# Phases 1-5 go hex0 -> hex1 -> hex2-0 -> catm -> M0 -> cc_amd64 -> M2
# (M2-Planet bd2fe4b, compiled by cc_amd64); Phases 6-11 use M2 (with catm,
# M0 and hex2-0) to build blood-elf-0, M1-0, hex2-1, bin/M1, bin/hex2 and
# bin/kaem; AMD64/kaem.run then builds M2-Mesoplanet, blood-elf, get_machine,
# M2-Planet and mescc-tools-extra and runs `sha256sum -c amd64.answers`.
# This script replaces Phases 0-5 with the Forth route and runs the rest of
# stage0-posix's recipe unchanged.  x86/ has the same three scripts (cc_x86
# in place of cc_amd64, base address 0x08048000); the x86 stand-ins are
# 32-bit ELFs made by the same amd64 Forth-route tools with --architecture
# x86 (M2-Planet, M1 and hex2 all cross-target), so stage0's x86 recipe runs
# from Phase 6 exactly as it would after its own Phases 0-5.
#
# WHAT THIS TRUSTS (everything that touches a byte of the outputs):
#   - everything bootstrap.sh trusts (its header lists it): the 229-byte
#     hex0-seed from vendor/stage0-posix/bootstrap-seeds, this repository's
#     sources, the vendored M2-Planet/mescc-tools sources, the Linux kernel,
#     bash and cat;
#   - SOURCE files of vendor/stage0-posix and its nested submodules at the
#     commits stage0-posix records (checked in stage 0): the AMD64 and x86
#     kaem scripts, M2libc, M2-Planet bd2fe4b, mescc-tools 5adfbf3,
#     mescc-tools-extra, M2-Mesoplanet.  bootstrap-seeds is not even copied
#     into the work tree: of stage0-posix's seeds only the AMD64 hex0-seed
#     runs (via bootstrap.sh), and none of kaem-0, hex0, hex1, hex2-0, catm,
#     M0, cc_amd64/cc_x86 or stage0's own M2 is built or run;
#   - host bash runs Phases 6-11 of mescc-tools-mini-kaem.kaem (the file
#     says it "can also be run by kaem or any other shell"), selected from
#     the Phase-6 banner on by a bash loop; two 2-line bash scripts stand in
#     for M0 (-> the Forth-route M1) and hex2-0 (-> the Forth-route hex2);
#     cat builds Phase 5's M2-0.c, cp copies the stage0-posix sources, and
#     mkdir/rm/chmod/printf manage files.
#   - Not in provenance, used only to check and report: sha256sum, cmp, wc,
#     grep, sed, awk, cut, tr, git (reads submodule commits).
#   No host C compiler, assembler or linker runs.
#   The x86 route has no x86 seed of its own: the amd64 seed-forth and
#   compiler produce everything, so it still needs an amd64 kernel.
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
#   2x. Route A for x86 (ARCHES contains x86): the same stand-ins, built as
#      i386 ELFs (catm, M2 = M2-0.c with M2libc/x86/linux/bootstrap.c,
#      compiled by cc-out-v3 --architecture x86 --bootstrap-mode; M0/hex2-0
#      -> M1/hex2 with --architecture x86); stage0-posix's x86 Phases 6-11
#      and x86/kaem.run then run unchanged, and all 19 x86/bin binaries
#      match x86.answers.
#   4. Optional, with LIVE_BOOTSTRAP=<a live-bootstrap checkout>: the first
#      thing live-bootstrap's seed/seed.kaem does after stage0-posix, i.e.
#      build seed/configurator.c and seed/script-generator.c with
#      M2-Mesoplanet and `sha256sum -c` them against live-bootstrap's own
#      *.<arch>.checksums, done with route A's bin set for each arch.
#
# Output: $BUILDROOT/A/stage0-posix/AMD64/bin and
# $BUILDROOT/A-x86/stage0-posix/x86/bin (route A's bin sets), SHA256SUMS
# (amd64) and SHA256SUMS.x86 in $BUILDROOT; the run's outputs in $BUILDROOT
# are wiped at its start.  Exit 77 (and a SKIP line) when stage0-posix's
# nested submodules are not checked out, or after amd64 PASSes when x86 was
# asked for but cannot run (no vendor/stage0-posix/x86, no IA-32
# emulation); 1 on any failure.
#
# Env overrides:
#   BUILDROOT       default ./build-out/handoff
#   BOOTSTRAP_OUT   reuse an existing bootstrap.sh output directory instead of
#                   running bootstrap.sh; its SHA256SUMS must verify (that
#                   catches corruption, not staleness: rebuild if in doubt)
#   ARCHES          "amd64 x86" (default) | amd64 | x86
#   ROUTE_B         1 (default) | 0: skip stage 3 (route B, amd64 only, ~30 s)
#   LIVE_BOOTSTRAP  path to a live-bootstrap checkout (stage 4; optional)
#
# Prerequisite (network, once):
#   git -C vendor/stage0-posix submodule update --init \
#       M2-Planet M2libc mescc-tools mescc-tools-extra M2-Mesoplanet x86
#   (if git.savannah.nongnu.org is unreachable, first run
#    git -C vendor/stage0-posix config submodule.mescc-tools.url \
#        https://github.com/oriansj/mescc-tools.git)

set -euo pipefail
cd "$(dirname "$0")"
ROOT=$PWD
BUILDROOT=${BUILDROOT:-$ROOT/build-out/handoff}
ARCHES=${ARCHES:-amd64 x86}
S0SRC=$ROOT/vendor/stage0-posix

T0=$SECONDS
step() { printf '\n=== %s: %s  [t=%ds]\n' "$1" "$2" $((SECONDS - T0)); }
fail() { printf 'handoff: FAIL: %s\n' "$1" >&2; exit 1; }
ok()   { printf '  ok: %s\n' "$1"; }
h()    { sha256sum < "$1" | cut -c1-16; }

# arch_vars <arch>: stage0-posix's directory, answers file, M2libc directory
# and hex2 base address for <arch>.
arch_vars() {
    case $1 in
        amd64) DIR=AMD64 ANS=amd64.answers MA=amd64 BASE=0x00600000 ;;
        x86)   DIR=x86   ANS=x86.answers   MA=x86   BASE=0x08048000 ;;
        *) fail "unknown arch '$1' in ARCHES (amd64 and x86 are wired up)" ;;
    esac
}

# ---------------------------------------------------------------------------
step 0 "prerequisites"
# ---------------------------------------------------------------------------
case "${OSTYPE:-}/${HOSTTYPE:-}" in
    linux*/x86_64) ;;
    *) fail "amd64 Linux only (this host: OSTYPE=${OSTYPE:-?} HOSTTYPE=${HOSTTYPE:-?})" ;;
esac
[ -f "$S0SRC/amd64.answers" ] || fail "vendor/stage0-posix not initialized (git submodule update --init --recursive)"
for sm in M2-Planet M2libc mescc-tools mescc-tools-extra M2-Mesoplanet; do
    line=$(git -C "$S0SRC" submodule status "$sm" 2>/dev/null) || fail "cannot query vendor/stage0-posix/$sm"
    case "$line" in
        -*) echo "handoff: SKIP: vendor/stage0-posix/$sm is not checked out; see 'Prerequisite' at the top of $0"
            exit 77 ;;
        +*) fail "vendor/stage0-posix/$sm is not at stage0-posix's recorded commit: $line" ;;
        U*) fail "vendor/stage0-posix/$sm has merge conflicts" ;;
    esac
    ok "stage0-posix/$(echo "$line" | awk '{print $2, substr($1,1,7), $3}')"
done
RUN_ARCHES="" SKIPPED=""
for a in $ARCHES; do
    arch_vars "$a"
    line=$(git -C "$S0SRC" submodule status "$DIR" 2>/dev/null) || fail "cannot query vendor/stage0-posix/$DIR"
    case "$line" in
        -*) if [ "$a" = amd64 ]; then
                echo "handoff: SKIP: vendor/stage0-posix/$DIR is not checked out; see 'Prerequisite' at the top of $0"
                exit 77
            fi
            SKIPPED="$SKIPPED $a(vendor/stage0-posix/$DIR not checked out)"
            ok "stage0-posix/$DIR not checked out: $a skipped"; continue ;;
        +*) fail "vendor/stage0-posix/$DIR is not at stage0-posix's recorded commit: $line" ;;
        U*) fail "vendor/stage0-posix/$DIR has merge conflicts" ;;
    esac
    ok "stage0-posix/$(echo "$line" | awk '{print $2, substr($1,1,7), $3}')"
    RUN_ARCHES="$RUN_ARCHES $a"
done
ok "stage0-posix $(git -C "$S0SRC" rev-parse --short=7 HEAD); arches:$RUN_ARCHES"

mkdir -p "$BUILDROOT"
BUILDROOT=$(cd "$BUILDROOT" && pwd)
rm -rf "${BUILDROOT:?}"/{A,A-x86,B1,B2,bootstrap,live-bootstrap,SHA256SUMS,SHA256SUMS.x86}

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

# new_tree <dir> <arch>: a fresh copy of the stage0-posix SOURCES the <arch>
# recipe reads (no bootstrap-seeds, no binaries).
new_tree() {
    local T=$1/stage0-posix f
    arch_vars "$2"
    mkdir -p "$T"
    for f in "$DIR" M2libc M2-Planet M2-Mesoplanet mescc-tools mescc-tools-extra \
             "$ANS" after.kaem; do
        cp -a "$S0SRC/$f" "$T/"
    done
    for f in "$T/$DIR"/bin/* "$T/$DIR"/artifact/*; do
        case "${f##*/}" in
            README|placeholder) rm -f "$f" ;;
            *) fail "vendor/stage0-posix is not clean: ${f#"$T"/} (was stage0's chain run inside vendor/?)" ;;
        esac
    done
}

# fasm <arch> <tree> <prog.M1> <libc-core|libc-full> <dest>: the Forth-route
# M1 + hex2 (amd64 binaries, cross-targeting <arch>) link <prog.M1> against
# the tree's M2libc/<arch> into an <arch> ELF.
fasm() {
    local L=$2/M2libc; arch_vars "$1"
    "$O/M1" --architecture "$MA" --little-endian -f "$L/$MA/${MA}_defs.M1" \
        -f "$L/$MA/$4.M1" -f "$3" -o "$5.hex2" || fail "M1 ($1) failed on $3"
    "$O/hex2" --architecture "$MA" --little-endian --base-address "$BASE" \
        -f "$L/$MA/ELF-$MA.hex2" -f "$5.hex2" -o "$5" || fail "hex2 ($1) failed on $3"
    chmod 755 "$5"
}

# standins <dir> <arch>: catm, M0, hex2-0 for Phases 6-8 (M2 is set per route).
standins() {
    local T=$1/stage0-posix L=$1/stage0-posix/M2libc A
    arch_vars "$2"; A=$T/$DIR/artifact
    "$O/cc-out-v3" --architecture "$MA" \
        -f "$L/sys/types.h" -f "$L/stddef.h" -f "$L/sys/utsname.h" \
        -f "$L/$MA/linux/unistd.c" -f "$L/$MA/linux/fcntl.c" -f "$L/fcntl.c" \
        -f "$L/ctype.c" -f "$L/stdlib.c" -f "$L/stdarg.h" -f "$L/stdio.h" \
        -f "$L/stdio.c" -f "$L/bootstrappable.c" -f "$T/mescc-tools-extra/catm.c" \
        -o "$A/catm-forth.M1" || fail "cc-out-v3 failed on catm.c ($2)"
    fasm "$2" "$T" "$A/catm-forth.M1" libc-full "$A/catm"
    printf '#!%s\n# stand-in for stage0 M0: the Forth-route M1\nexec %q --architecture %s --little-endian -f "$1" -o "$2"\n' \
        "$BASH" "$O/M1" "$MA" > "$A/M0"
    printf '#!%s\n# stand-in for stage0 hex2-0: the Forth-route hex2\nexec %q --architecture %s --little-endian --base-address %s -f "$1" -o "$2"\n' \
        "$BASH" "$O/hex2" "$MA" "$BASE" > "$A/hex2-0"
    chmod 755 "$A/M0" "$A/hex2-0"
}

# recipe <dir> <arch>: stage0-posix's Phases 6-11 (mini-kaem, from the
# Phase-6 banner on, run by bash) and then kaem.run with the bin/kaem Phase
# 11 built, exactly as kaem.<arch> runs it.  Returns kaem.run's exit status
# (non-zero when its own `sha256sum -c <arch>.answers` fails).
recipe() {
    local T=$1/stage0-posix line on=0 rc=0
    arch_vars "$2"
    while IFS= read -r line || [ -n "$line" ]; do
        [[ $line == *'Phase-6 Build blood-elf-0'* ]] && on=1
        [ "$on" = 1 ] && printf '%s\n' "$line"
    done < "$T/$DIR/mescc-tools-mini-kaem.kaem" > "$1/phases-6-11.kaem"
    [ -s "$1/phases-6-11.kaem" ] || fail "no Phase-6 banner in $DIR/mescc-tools-mini-kaem.kaem"
    (cd "$T" && env -i PATH=/nonexistent "$BASH" -e "$1/phases-6-11.kaem") > "$1/phases-6-11.log" 2>&1 \
        || { tail -20 "$1/phases-6-11.log" >&2; fail "Phases 6-11 failed in $1 (log: $1/phases-6-11.log)"; }
    (cd "$T" && env -i PATH=/nonexistent "./$DIR/bin/kaem" --verbose --strict --file "./$DIR/kaem.run") \
        > "$1/kaem.run.log" 2>&1 || rc=$?
    local n
    n=$(awk '{print $2}' "$T/$ANS" | while read -r f; do [ -f "$T/$f" ] || echo "$f"; done)
    [ -z "$n" ] || { tail -20 "$1/kaem.run.log" >&2; fail "kaem.run built no $n (log: $1/kaem.run.log)"; }
    return "$rc"
}

# answers <dir> <arch>: the host's sha256sum -c against <arch>.answers; sets
# MATCH to the number of matching binaries and NANS to the number listed.
answers() {
    local T=$1/stage0-posix
    arch_vars "$2"
    (cd "$T" && sha256sum -c "$ANS" 2>/dev/null || true) > "$1/answers.txt"
    MATCH=$(grep -c ': OK$' "$1/answers.txt" || true)
    NANS=$(wc -l < "$T/$ANS")
}

# route_a <arch> <dir>: Forth-route stand-ins for Phases 0-5, then the recipe.
route_a() {
    local a=$1 W=$2 T=$2/stage0-posix A t
    new_tree "$W" "$a"; arch_vars "$a"; A=$T/$DIR/artifact
    standins "$W" "$a"
    ok "artifact/catm (catm.c by cc-out-v3, $MA ELF), artifact/M0 -> M1, artifact/hex2-0 -> hex2 (--architecture $MA)"
    # Phase 5's input, as mescc-tools-mini-kaem.kaem's catm builds it.
    (cd "$T" && cat "./M2libc/$MA/linux/bootstrap.c" ./M2-Planet/cc.h ./M2libc/bootstrappable.c \
        ./M2-Planet/cc_globals.c ./M2-Planet/cc_reader.c ./M2-Planet/cc_strings.c \
        ./M2-Planet/cc_types.c ./M2-Planet/cc_emit.c ./M2-Planet/cc_core.c \
        ./M2-Planet/cc_macro.c ./M2-Planet/cc.c) > "$A/M2-0.c"
    "$O/cc-out-v3" --architecture "$MA" --bootstrap-mode -f "$A/M2-0.c" -o "$A/M2-0.M1" \
        || fail "cc-out-v3 failed on M2-0.c ($a)"
    fasm "$a" "$T" "$A/M2-0.M1" libc-core "$A/M2"
    ok "artifact/M2 (M2-Planet bd2fe4b, M2-0.c compiled by cc-out-v3 --architecture $MA): $(wc -c < "$A/M2") bytes, sha256 $(h "$A/M2")..."
    t=$SECONDS
    recipe "$W" "$a" || { tail -30 "$W/kaem.run.log" >&2; fail "route A ($a): kaem.run failed (its sha256sum -c $ANS?) (log: $W/kaem.run.log)"; }
    answers "$W" "$a"
    [ "$MATCH" = "$NANS" ] || { cat "$W/answers.txt" >&2; fail "route A ($a): only $MATCH binaries match $ANS"; }
    ok "stage0's $DIR Phases 6-11 + kaem.run: $MATCH/$NANS match $ANS ($((SECONDS - t))s; recipe's own sha256sum -c passed too)"
    ok "$DIR/bin/M2-Planet sha256 $(sha256sum < "$T/$DIR/bin/M2-Planet" | cut -d' ' -f1)"
}

# ---------------------------------------------------------------------------
step 2 "route A: Forth-route stand-ins for stage0 Phases 0-5, then stage0's recipe"
# ---------------------------------------------------------------------------
PASSED=""
for a in $RUN_ARCHES; do
    if [ "$a" = amd64 ]; then
        echo "  --- amd64"
        route_a amd64 "$BUILDROOT/A"
        (cd "$BUILDROOT/A/stage0-posix" && sha256sum $(awk '{print $2}' amd64.answers)) > "$BUILDROOT/SHA256SUMS"
    else
        echo "  --- x86 (i386 binaries on this amd64 kernel)"
        # The recipe runs i386 ELFs: check that the kernel can (IA-32
        # emulation) by running the Forth-built i386 catm once.
        P=$BUILDROOT/A-x86/probe
        new_tree "$P" x86
        standins "$P" x86
        if ! "$P/stage0-posix/x86/artifact/catm" "$P/empty" 2>/dev/null || [ ! -f "$P/empty" ]; then
            SKIPPED="$SKIPPED x86(this kernel cannot run i386 ELFs: no IA-32 emulation)"
            ok "x86 skipped: this kernel cannot run i386 ELFs (IA-32 emulation missing or disabled)"
            continue
        fi
        rm -rf "${P:?}"
        ok "this kernel runs i386 ELFs (IA-32 emulation)"
        route_a x86 "$BUILDROOT/A-x86"
        (cd "$BUILDROOT/A-x86/stage0-posix" && sha256sum $(awk '{print $2}' x86.answers)) > "$BUILDROOT/SHA256SUMS.x86"
    fi
    PASSED="$PASSED $a"
done

# ---------------------------------------------------------------------------
step 3 "route B (amd64): artifact/M2 = cc-out-v2 (M2-Planet 0a67a68) as is"
# ---------------------------------------------------------------------------
if [ "${ROUTE_B:-1}" = 0 ]; then
    ok "skipped (ROUTE_B=0)"
elif [[ " $PASSED " != *' amd64 '* ]]; then
    ok "skipped (amd64 not in ARCHES)"
else
    W=$BUILDROOT/B1; T=$W/stage0-posix
    new_tree "$W" amd64; standins "$W" amd64
    cp "$O/cc-out-v2" "$T/AMD64/artifact/M2"
    rc=0; recipe "$W" amd64 || rc=$?
    answers "$W" amd64
    ok "kaem.run exit $rc (its sha256sum -c); $MATCH/$NANS match amd64.answers"
    ok "  match:  $(grep ': OK$' "$W/answers.txt" | sed 's|^AMD64/bin/||; s|: OK$||' | tr '\n' ' ')"
    ok "  differ: $(grep -v ': OK$' "$W/answers.txt" | sed 's|^AMD64/bin/||; s|: .*$||' | tr '\n' ' ')"
    ok "bin/M2-Planet (bd2fe4b source, built by 0a67a68) sha256 $(sha256sum < "$T/AMD64/bin/M2-Planet" | cut -d' ' -f1)"

    step 3b "route B, one generation later: artifact/M2 = route B's bin/M2-Planet"
    W=$BUILDROOT/B2; T=$W/stage0-posix
    new_tree "$W" amd64; standins "$W" amd64
    cp "$BUILDROOT/B1/stage0-posix/AMD64/bin/M2-Planet" "$T/AMD64/artifact/M2"
    recipe "$W" amd64 || { tail -30 "$W/kaem.run.log" >&2; fail "route B2: kaem.run failed (log: $W/kaem.run.log)"; }
    answers "$W" amd64
    [ "$MATCH" = "$NANS" ] || { cat "$W/answers.txt" >&2; fail "route B2: only $MATCH binaries match amd64.answers"; }
    for f in $(awk '{print $2}' "$T/amd64.answers"); do
        cmp -s "$T/$f" "$BUILDROOT/A/stage0-posix/$f" || fail "route B2 $f != route A $f"
    done
    ok "$MATCH/$NANS match amd64.answers, byte-identical to route A"
fi

# ---------------------------------------------------------------------------
step 4 "live-bootstrap's first step (optional: LIVE_BOOTSTRAP)"
# ---------------------------------------------------------------------------
if [ -z "${LIVE_BOOTSTRAP:-}" ]; then
    ok "skipped (set LIVE_BOOTSTRAP=<live-bootstrap checkout> to run it)"
else
    LB=$(cd "$LIVE_BOOTSTRAP" && pwd)
    ok "live-bootstrap $(git -C "$LB" rev-parse --short=7 HEAD 2>/dev/null || echo '?'), its seed/stage0-posix pin: $(git -C "$LB" ls-tree HEAD seed/stage0-posix 2>/dev/null | awk '{print substr($3,1,7)}')"
    for a in $PASSED; do
        arch_vars "$a"
        if [ "$a" = amd64 ]; then T=$BUILDROOT/A/stage0-posix; else T=$BUILDROOT/A-x86/stage0-posix; fi
        W=$BUILDROOT/live-bootstrap/$a; mkdir -p "$W/tmp"
        for p in configurator script-generator; do
            [ -f "$LB/seed/$p.$a.checksums" ] || fail "no $LB/seed/$p.$a.checksums"
            cp "$LB/seed/$p.c" "$LB/seed/$p.$a.checksums" "$W/"
            # as seed/seed.kaem: M2-Mesoplanet --architecture ${ARCH} -f $p.c -o $p
            (cd "$W" && env -i PATH="$T/$DIR/bin" M2LIBC_PATH="$T/M2libc" TMPDIR="$W/tmp" \
                M2-Mesoplanet --architecture "$MA" -f "$p.c" -o "$p") > "$W/$p.log" 2>&1 \
                || fail "M2-Mesoplanet ($a) failed on $p.c (log: $W/$p.log)"
            (cd "$W" && "$T/$DIR/bin/sha256sum" -c "$p.$a.checksums") | sed 's/^/    /' \
                || fail "$p does not match live-bootstrap's $p.$a.checksums"
        done
        ok "live-bootstrap's seed binaries built with route A's $DIR tools match its $a checksums"
    done
fi

step 5 "done"
for a in $PASSED; do
    if [ "$a" = amd64 ]; then
        echo "  AMD64/bin set: $BUILDROOT/A/stage0-posix/AMD64/bin  (SHA256SUMS: $BUILDROOT/SHA256SUMS)"
    else
        echo "  x86/bin set:   $BUILDROOT/A-x86/stage0-posix/x86/bin  (SHA256SUMS: $BUILDROOT/SHA256SUMS.x86)"
    fi
done
echo
if [ -n "$SKIPPED" ]; then
    echo "handoff: SKIP:$SKIPPED; route A passed for:$PASSED"
    exit 77
fi
for a in $PASSED; do
    arch_vars "$a"
    echo "handoff: $a: all $(wc -l < "$S0SRC/$ANS") $ANS binaries match, byte for byte"
done
echo "handoff: PASS in $((SECONDS - T0))s — the Forth route, standing in for stage0-posix's"
echo "hex1 -> hex2 -> M0 -> cc_<arch> -> M2 phases, feeds stage0's own recipe for:$PASSED"
