#!/usr/bin/env bash
# Die gates for 130-asm.fth: M1 inputs the assembler must reject, each with
# its own exit code (Appendix G, 230-249).  Every buffer and table has one
# gate that overflows it; 231 stands for the undefined-label family (the
# token is echoed to stderr before the exit).
set -uo pipefail
cd "$(dirname "$0")/../.."

[ -x seed-forth ] || ./build.sh >/dev/null

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail=0
# gate NAME CODE: run the assembler on $TMP/in.M1, expect exit CODE and no
# /tmp/asm-out.
gate() {
    rm -f /tmp/asm-out
    { cat 010-lib.fth 130-asm.fth; printf 'asm-main\n'; cat "$TMP/in.M1"; } \
        | ./seed-forth > /dev/null 2> "$TMP/err"
    rc=$?
    if [ "$rc" != "$2" ]; then
        echo "FAIL: $1 expected exit $2, got $rc"; fail=1
    elif [ -f /tmp/asm-out ]; then
        echo "FAIL: $1 died but still wrote /tmp/asm-out"; fail=1
    else
        echo "PASS: $1 -> $rc"
    fi
}

# 231: '&label' with no ':label' anywhere.
printf ':start\n&nowhere\n' > "$TMP/in.M1"
gate "231 undefined &label" 231

# 239: source fills the 4 MiB asm-src-buf (4 MiB of blanks).
head -c 4194304 /dev/zero | tr '\0' ' ' > "$TMP/in.M1"
gate "239 source too big" 239

# 240: macro expansion fills the 4 MiB asm-exp-buf: a 1,000-character
# body used 4,200 times.
{ printf 'DEFINE X '; head -c 1000 /dev/zero | tr '\0' '0'; printf '\n'
  awk 'BEGIN { for (i = 0; i < 4200; i++) print "X" }'; } > "$TMP/in.M1"
gate "240 expansion too big" 240

# 241: output fills the 1 MiB asm-out-buf: 1,000 bytes of hex, 1,050 times.
{ printf 'DEFINE Y '; head -c 2000 /dev/zero | tr '\0' '0'; printf '\n'
  awk 'BEGIN { for (i = 0; i < 1050; i++) print "Y" }'; } > "$TMP/in.M1"
gate "241 output too big" 241

# 242: more than 8,192 labels.
awk 'BEGIN { for (i = 0; i < 8193; i++) print ":L" i }' > "$TMP/in.M1"
gate "242 label table full" 242

# 243: more than 4,096 DEFINEs.
awk 'BEGIN { for (i = 0; i < 4097; i++) print "DEFINE D" i " 00" }' > "$TMP/in.M1"
gate "243 DEFINE table full" 243

exit $fail
