#!/usr/bin/env bash
# stage0-check.sh — cross-check the Forth route against the canonical
# stage0-posix route to M2-Planet (diverse double-compiling), amd64 only.
#
# WHAT THIS TRUSTS
#   - vendor/stage0-posix at its pin (Release_1.9.1, 45d90f5) with its nested
#     submodules bootstrap-seeds, AMD64, M2-Planet (bd2fe4b = Release_1.13.1),
#     M2libc, mescc-tools, mescc-tools-extra and M2-Mesoplanet checked out at
#     the commits stage0-posix records (checked in stage 0).  Its chain starts
#     from bootstrap-seeds' 229-byte hex0-seed and 229-byte kaem-optional-seed
#     and checks its own outputs against stage0-posix's amd64.answers.
#   - The same hex0-seed assembles seed-forth, so both routes share that one
#     trust root; after it, the two compiler lineages are independent
#     (stage0: hand-written hex/M0 -> cc_amd64 -> M2 -> M2-Planet;
#      ours: 000-seed.hex0 -> seed-forth -> Forth C compiler -> cc-out-v1).
#   - stage0's M1, hex2 and blood-elf (built in stage 1) link BOTH routes'
#     outputs in stages 3-5, so this check tests compiler lineage, not
#     assembler/linker independence.
#   - The host kernel and bash; cp/sed/cat/mkdir/rm/mv/unshare/mount only move
#     and filter files (sed is build-m2planet-monolith.sh's #include filter
#     and STAGE0_COMPAT patch).  cmp, diff, wc and sha256sum only report.
#   No host C compiler is used anywhere in this script.
#
# WHAT THIS PROVES (fails loudly otherwise)
#   1. stage0-posix's AMD64 kaem chain runs from the seeds with an empty
#      environment and reproduces its published hashes; its M2-Planet
#      (bd2fe4b) is the canonical binary 7cf19de2... from amd64.answers.
#   2. seed-forth builds cc-out-v1 (default) and cc-out-v1-compat
#      (STAGE0_COMPAT=1) from vendor/M2-Planet (0a67a68).
#   3. Like with like: M2-Planet 0a67a68 is rebuilt by stage0's own Phase-15
#      recipe (AMD64/mescc-tools-full-kaem.kaem) with vendor/M2-Planet and its
#      M2libc substituted for stage0's pinned copies:
#        x1 = built by stage0's artifact/M2 (cc_amd64-built), as stage0 does;
#        z1 = built by stage0's bin/M2-Planet;  x1 == z1 required;
#        x2 = built by x1;  x3 = built by x2;  x2 == x3 (fixed point).
#   4. DDC: y1 = built by cc-out-v1 (default), y2 = built by y1.
#      y2 == x2 byte for byte: the Forth-rooted and the stage0-rooted chains
#      reach the same M2-Planet binary.  No STAGE0_COMPAT needed.
#   5. STAGE0_COMPAT shortcut: y1c = built by cc-out-v1-compat; y1c == x2,
#      and cc-out-v1-compat's self-host .M1 == x2's (the 02d98f86... output),
#      while default cc-out-v1's self-host .M1 differs (it matches GCC-built
#      M2-Planet instead; see stage-a-check.sh).
#   6. Root cause: `(8 & 12) && (0 == 0)` is 1 under the Forth compiler
#      (ISO C: && is logical) and 0 in an M2-Planet-compiled program
#      (M2-Planet compiles && as bitwise and_rax,rbx).
#
# Env overrides:
#   BUILDROOT    default /tmp/seed-bootstrap; work goes to $BUILDROOT/stage0-check,
#                wiped at the start of every run
#   PRIVATE_TMP  auto (default) | 0.  seed-forth's compiler always writes
#                /tmp/cc-out; with `unshare -rm` each run gets a private /tmp.
#
# Exit status: 0 PASS, 77 SKIP (a stage0-posix nested submodule is not
# checked out), anything else FAIL.
#
# Prerequisite (network, once):
#   git -C vendor/stage0-posix submodule update --init \
#       M2-Planet M2libc mescc-tools mescc-tools-extra M2-Mesoplanet
#   (if git.savannah.nongnu.org is unreachable, first run
#    git -C vendor/stage0-posix config submodule.mescc-tools.url \
#        https://github.com/oriansj/mescc-tools.git)

set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD

BUILDROOT=${BUILDROOT:-/tmp/seed-bootstrap}
PRIVATE_TMP=${PRIVATE_TMP:-auto}
S0SRC=vendor/stage0-posix
M2=$ROOT/vendor/M2-Planet
L=$M2/M2libc

step() { printf '\n=== STAGE %s: %s ===\n' "$1" "$2"; }
fail() { printf 'stage0-check: FAIL (stage %s): %s\n' "$1" "$2" >&2; exit 1; }
ok()   { printf '  %s\n' "$*"; }
h()    { sha256sum < "$1" | cut -c1-16; }
same() { # same <stage> <what> <a> <b>
    cmp -s "$3" "$4" || fail "$1" "$2: $(basename "$3") ($(h "$3")) != $(basename "$4") ($(h "$4"))"
    ok "$2: $(basename "$3") == $(basename "$4")  sha256 $(h "$3")...  $(wc -c < "$3") bytes"
}

mkdir -p "$BUILDROOT"
BUILDROOT=$(cd "$BUILDROOT" && pwd)
W=$BUILDROOT/stage0-check
rm -rf "$W"
mkdir -p "$W/tmp"
t0=$SECONDS

# ---------------------------------------------------------------------------
step 0 "prereqs: stage0-posix nested submodules at their recorded commits"
# ---------------------------------------------------------------------------
[ -f "$M2/cc.c" ] && [ -f "$L/bootstrappable.c" ] \
    || fail 0 "vendor/M2-Planet not initialized (git submodule update --init --recursive)"
for sm in bootstrap-seeds AMD64 M2-Planet M2libc mescc-tools mescc-tools-extra M2-Mesoplanet; do
    line=$(git -C "$S0SRC" submodule status "$sm" 2>/dev/null) || fail 0 "cannot query $S0SRC/$sm"
    case "$line" in
        -*) echo "stage0-check: SKIP: $S0SRC/$sm is not checked out; see 'Prerequisite' at the top of $0"
            exit 77 ;;
        +*) fail 0 "$S0SRC/$sm is not at stage0-posix's recorded commit: $line" ;;
        U*) fail 0 "$S0SRC/$sm has merge conflicts" ;;
    esac
    ok "$(echo "$line" | awk '{print substr($1,1,12), $2, $3}')"
done
ok "vendor/M2-Planet $(git -C "$M2" rev-parse --short=12 HEAD), its M2libc $(git -C "$L" rev-parse --short=12 HEAD)"

# ---------------------------------------------------------------------------
step 1 "stage0-posix AMD64 chain from hex0-seed + kaem-optional-seed"
# ---------------------------------------------------------------------------
cp -a "$S0SRC" "$W/stage0-posix"
rm -f "$W"/stage0-posix/AMD64/bin/* "$W"/stage0-posix/AMD64/artifact/[!R]*
t=$SECONDS
( cd "$W/stage0-posix" && env -i PATH=/nonexistent \
    ./bootstrap-seeds/POSIX/AMD64/kaem-optional-seed ) > "$W/stage0-chain.log" 2>&1 \
    || { tail -20 "$W/stage0-chain.log" >&2; fail 1 "stage0-posix chain failed (log: $W/stage0-chain.log)"; }
S0=$W/stage0-posix/AMD64
# The chain ran its own sha256sum -c amd64.answers; re-check with the host's.
( cd "$W/stage0-posix" && sha256sum -c --quiet amd64.answers ) \
    || fail 1 "stage0 binaries do not match amd64.answers"
ok "chain OK in $((SECONDS-t))s, all $(wc -l < "$W/stage0-posix/amd64.answers") binaries match amd64.answers (log: $W/stage0-chain.log)"
ok "canonical M2-Planet (bd2fe4b): AMD64/bin/M2-Planet sha256 $(h "$S0/bin/M2-Planet")..."
ok "cc_amd64-built M2 (bd2fe4b):   AMD64/artifact/M2     sha256 $(h "$S0/artifact/M2")..."

# ---------------------------------------------------------------------------
step 2 "Forth route: seed-forth -> cc-out-v1 (default and STAGE0_COMPAT=1)"
# ---------------------------------------------------------------------------
./build.sh >/dev/null || fail 2 "build.sh failed"
use_private=0
if [ "$PRIVATE_TMP" != 0 ] && unshare -rm sh -c 'mount --bind "$1" /tmp' _ "$W/tmp" 2>/dev/null; then
    use_private=1; ok "private /tmp per seed-forth run (unshare -rm)"
else
    ok "unshare -rm unavailable: using the shared /tmp/cc-out"
fi
# forth_cc <STAGE0_COMPAT> <dest>: run tests/cc/build-m2planet-monolith.sh
forth_cc() {
    rm -rf "$W/tmp"; mkdir -p "$W/tmp"
    if [ "$use_private" = 1 ]; then
        STAGE0_COMPAT=$1 unshare -rm sh -c 'mount --bind "$1" /tmp && exec ./tests/cc/build-m2planet-monolith.sh' \
            _ "$W/tmp" >/dev/null || fail 2 "monolith build (STAGE0_COMPAT=$1) failed"
        mv "$W/tmp/cc-out" "$2"
    else
        STAGE0_COMPAT=$1 ./tests/cc/build-m2planet-monolith.sh >/dev/null \
            || fail 2 "monolith build (STAGE0_COMPAT=$1) failed"
        mv /tmp/cc-out "$2"
    fi
    chmod +x "$2"
    ok "$(basename "$2"): $(wc -c < "$2") bytes, sha256 $(h "$2")..."
}
forth_cc 0 "$W/cc-out-v1"
forth_cc 1 "$W/cc-out-v1-compat"

# ---------------------------------------------------------------------------
step 3 "stage0 route rebuilds M2-Planet 0a67a68 (stage0's Phase-15 recipe)"
# ---------------------------------------------------------------------------
# phase15 <compiler> <name>: AMD64/mescc-tools-full-kaem.kaem "Phase-15 Build
# M2-Planet from M2-Planet", with ../M2-Planet and ../M2libc replaced by
# vendor/M2-Planet and vendor/M2-Planet/M2libc.
phase15() {
    local cc=$1 o=$W/$2
    "$cc" --architecture amd64 \
        -f "$L/sys/types.h" -f "$L/stddef.h" -f "$L/sys/utsname.h" \
        -f "$L/amd64/linux/unistd.c" -f "$L/amd64/linux/fcntl.c" -f "$L/fcntl.c" \
        -f "$L/ctype.c" -f "$L/stdlib.c" -f "$L/stdarg.h" -f "$L/stdio.h" \
        -f "$L/stdio.c" -f "$L/bootstrappable.c" \
        -f "$M2/cc.h" -f "$M2/cc_globals.c" -f "$M2/cc_reader.c" -f "$M2/cc_strings.c" \
        -f "$M2/cc_types.c" -f "$M2/cc_emit.c" -f "$M2/cc_core.c" -f "$M2/cc_macro.c" \
        -f "$M2/cc.c" --debug -o "$o.M1" >/dev/null || fail 3 "$2: compile by $cc failed"
    "$S0/bin/blood-elf" --little-endian --64 -f "$o.M1" -o "$o-footer.M1" >/dev/null
    "$S0/bin/M1" --architecture amd64 --little-endian \
        -f "$L/amd64/amd64_defs.M1" -f "$L/amd64/libc-full.M1" \
        -f "$o.M1" -f "$o-footer.M1" -o "$o.hex2"
    "$S0/bin/hex2" --architecture amd64 --little-endian --base-address 0x00600000 \
        -f "$L/amd64/ELF-amd64-debug.hex2" -f "$o.hex2" -o "$o"
    chmod +x "$o"
}
phase15 "$S0/artifact/M2"     x1
phase15 "$S0/bin/M2-Planet"   z1
same 3 "stage0's two bd2fe4b compilers agree" "$W/x1" "$W/z1"
phase15 "$W/x1" x2
phase15 "$W/x2" x3
same 3 "fixed point" "$W/x2" "$W/x3"

# ---------------------------------------------------------------------------
step 4 "DDC: Forth-rooted chain reaches the stage0-rooted binary"
# ---------------------------------------------------------------------------
phase15 "$W/cc-out-v1" y1
ok "y1 (built by cc-out-v1): sha256 $(h "$W/y1")...  (!= x1: a different compiler built it)"
phase15 "$W/y1" y2
same 4 "DDC" "$W/y2" "$W/x2"

# ---------------------------------------------------------------------------
step 5 "STAGE0_COMPAT=1 reaches the same binary one generation earlier"
# ---------------------------------------------------------------------------
phase15 "$W/cc-out-v1-compat" y1c
same 5 "STAGE0_COMPAT" "$W/y1c" "$W/x2"
# Self-host .M1 on stage-a-check.sh's input list (the REPRODUCIBLE.md hashes).
selfhost() {
    (cd "$M2" && "$1" --architecture amd64 --expand-includes \
        -f M2libc/bootstrappable.c -f cc_reader.c -f cc_strings.c -f cc_types.c \
        -f cc_emit.c -f cc_core.c -f cc_macro.c -f cc.c -f cc.h -f cc_globals.c \
        -f gcc_req.h -o "$2") >/dev/null || fail 5 "self-host by $1 failed"
}
selfhost "$W/x2"                "$W/self-x2-amd64.M1"
selfhost "$W/cc-out-v1-compat"  "$W/self-v1-compat-amd64.M1"
selfhost "$W/cc-out-v1"         "$W/self-v1-amd64.M1"
same 5 "self-host .M1" "$W/self-v1-compat-amd64.M1" "$W/self-x2-amd64.M1"
if cmp -s "$W/self-v1-amd64.M1" "$W/self-x2-amd64.M1"; then
    fail 5 "default cc-out-v1 unexpectedly matches x2; the documented difference is gone"
fi
d=$(diff "$W/self-v1-amd64.M1" "$W/self-x2-amd64.M1" | grep -c '^[<>]' || true)
other=$(diff "$W/self-v1-amd64.M1" "$W/self-x2-amd64.M1" | grep '^[<>]' \
        | grep -Ecv '^(< (add|sub)_r(ax|sp),BYTE |> mov_r14, %|> (add|sub)_r(ax|sp),r14|>  # )' || true)
[ "$other" = 0 ] || fail 5 "default-vs-x2 diff has $other lines outside the add/sub-immediate pattern"
ok "default cc-out-v1 self-host differs from x2 in $d changed lines, all BYTE-immediate add/sub vs mov_r14 + reg form"

# ---------------------------------------------------------------------------
step 6 "root cause: && is logical in C, bitwise in M2-Planet"
# ---------------------------------------------------------------------------
cat > "$W/andand.c" <<'EOF'
/* write_sub_immediate's guard with --architecture amd64 and reg == REGISTER_ZERO */
int main()
{
	int Architecture = 8;   /* AMD64 */
	int reg = 0;            /* REGISTER_ZERO */
	if((Architecture & 12) && (reg == 0)) return 1;
	return 0;
}
EOF
# (a) the Forth C compiler compiles it directly to an ELF
cat 010-lib.fth [0-9][0-9][0-9]-cc-*.fth "$W/andand.c" > "$W/andand.in"
rm -rf "$W/tmp"; mkdir -p "$W/tmp"
if [ "$use_private" = 1 ]; then
    unshare -rm sh -c 'mount --bind "$1" /tmp && exec "$2"' _ "$W/tmp" "$ROOT/seed-forth" \
        < "$W/andand.in" >/dev/null || true
    mv "$W/tmp/cc-out" "$W/andand-forth"
else
    ./seed-forth < "$W/andand.in" >/dev/null || true
    mv /tmp/cc-out "$W/andand-forth"
fi
chmod +x "$W/andand-forth"
rc_forth=0; "$W/andand-forth" || rc_forth=$?
# (b) M2-Planet (x2) compiles it; stage0's M1 + hex2 link it
"$W/x2" --architecture amd64 -f "$W/andand.c" -o "$W/andand.M1" >/dev/null
"$S0/bin/M1" --architecture amd64 --little-endian -f "$L/amd64/amd64_defs.M1" \
    -f "$L/amd64/libc-core.M1" -f "$W/andand.M1" -o "$W/andand.hex2"
"$S0/bin/hex2" --architecture amd64 --little-endian --base-address 0x00600000 \
    -f "$L/amd64/ELF-amd64.hex2" -f "$W/andand.hex2" -o "$W/andand-m2"
chmod +x "$W/andand-m2"
rc_m2=0; "$W/andand-m2" || rc_m2=$?
[ "$rc_forth" = 1 ] || fail 6 "Forth-compiled guard returned $rc_forth, expected 1 (ISO C &&)"
[ "$rc_m2" = 0 ]    || fail 6 "M2-Planet-compiled guard returned $rc_m2, expected 0 (bitwise &&)"
ok "Forth C compiler: (8 & 12) && (0 == 0) -> 1   M2-Planet: -> 0  (8 & 1 == 0; emitted and_rax,rbx)"

echo
echo "stage0-check: PASS ($((SECONDS-t0))s)"
