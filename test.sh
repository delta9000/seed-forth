#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

pass() { echo "  PASS: $*"; }
fail() { echo "  FAIL: $*"; exit 1; }

# ----- Literate book consistency -----
# Every code block in book/*.md tagged with file=<source> must appear in
# the corresponding source file, in non-decreasing order.  Catches drift
# between the tutorial and the canonical .fth/.hex0 sources.
if [ -d book ] && [ -x tools/tangle.sh ]; then
    if tools/tangle.sh verify >/dev/null; then
        pass "book: tangle verify (every quoted block found in source)"
    else
        tools/tangle.sh verify || true
        fail "book: tangle verify"
    fi
fi

# Strip Forth comments (\ line-comments and ( ... ) stack-comments) and blank
# lines before feeding source to seed-forth (the tokenizer splits on whitespace).
strip_forth() { sed -e 's/\\.*$//' -e 's/([^)]*)//g' | grep -v '^[[:space:]]*$'; }

# ----- Seed primitives -----

# T1: builds and exits 0
./seed-forth </dev/null && pass "exits 0" || fail "exit status"

# T9a: REPL exits cleanly on EOF (no input)
./seed-forth </dev/null && pass "repl: EOF exit" || fail "repl exit status"

# T9b: REPL executes 'bye' from input
echo "bye" | ./seed-forth && pass "repl: bye" || fail "repl: bye status"

# T9c: unknown word produces "?\n"
out=$(echo "wibble" | ./seed-forth)
[ "$out" = $'?' ] && pass "repl: unknown -> ?" || fail "unknown got: '$out'"

# T10: minimal colon-def: define `greet` to call `bye`; calling it exits cleanly
out=$(printf ': greet bye ;\ngreet\nemit\n' | timeout 3 ./seed-forth)
[ -z "$out" ] && pass "colon: define+invoke" || fail "colon got: '$out'"

# T13a: [lit] in interpret mode pushes a decimal value.
out=$(echo "[lit] 65 emit" | timeout 3 ./seed-forth)
[ "$out" = "A" ] && pass "[lit] interpret -> A" || fail "[lit] interpret got: '$out'"

# T13b: [lit] in compile mode compiles 'lit + cell' into a colon def.
out=$(printf ': greet [lit] 72 emit [lit] 105 emit ;\ngreet\n' | timeout 3 ./seed-forth)
[ "$out" = "Hi" ] && pass "[lit] compile -> Hi" || fail "[lit] compile got: '$out'"

# T13c: [lit] handles large values (sysvar address); emit prints low byte.
out=$(echo "[lit] 4337704 emit" | timeout 3 ./seed-forth)
[ "$out" = "(" ] && pass "[lit] large value (low byte of 0x413028)" || fail "[lit] large got: '$out'"

# T-div: divide primitive
out=$(echo "[lit] 4096 [lit] 16 / [lit] 48 + emit" | timeout 3 ./seed-forth)
[ "$out" = "0" ] && pass "div: 4096/16=256, low byte+'0' = '0'" || fail "div got: '$out'"
out=$(echo "[lit] 17 [lit] 5 / [lit] 48 + emit" | timeout 3 ./seed-forth)
[ "$out" = "3" ] && pass "div: 17/5=3" || fail "div 17/5 got: '$out'"

# T14: syscall6 - write byte to stdout via raw Linux write syscall.
out=$(printf ': t [lit] 65 [lit] 4268032 c! [lit] 1 [lit] 4268032 [lit] 1 [lit] 0 [lit] 0 [lit] 0 [lit] 1 syscall6 drop bye ;\nt\n' | timeout 3 ./seed-forth)
[ "$out" = "A" ] && pass "syscall6: write 'A'" || fail "syscall6 got: '$out'"

# ----- 010-lib.fth -----

# T-classify: digit?/alpha?/space? return -1/0
out=$(cat 010-lib.fth <(printf '[lit] 53 digit? [lit] 90 + [lit] 89 + emit\n[lit] 65 digit? [lit] 90 + [lit] 89 + emit\n[lit] 65 alpha? [lit] 90 + [lit] 89 + emit\n[lit] 32 space? [lit] 90 + [lit] 89 + emit\nbye\n') | strip_forth | timeout 5 ./seed-forth | od -An -tx1 | tr -d ' \n')
[ "$out" = "b2b3b2b2" ] && pass "lib: digit?/alpha?/space? classifiers" || fail "classify got: '$out'"

# T-fileio: open+write+close round-trip
rm -f /tmp/forth-fwio-test
cat > /tmp/test-fileio.fth <<'TFEOF'
: path  ( -- pathaddr )
  here
  [lit] 47 c, [lit] 116 c, [lit] 109 c, [lit] 112 c,
  [lit] 47 c, [lit] 102 c, [lit] 111 c, [lit] 114 c,
  [lit] 116 c, [lit] 104 c, [lit] 45 c, [lit] 102 c,
  [lit] 119 c, [lit] 105 c, [lit] 111 c, [lit] 45 c,
  [lit] 116 c, [lit] 101 c, [lit] 115 c, [lit] 116 c,
  [lit] 0 c, ;

: payload  ( -- bufaddr )
  here
  [lit] 79 c, [lit] 75 c, [lit] 10 c, ;        \ "OK\n"

: go
  path payload swap                            ( bufaddr pathaddr )
  [lit] 577 [lit] 420 open                     ( bufaddr fd )
  swap [lit] 3 write drop                      ( fd )
  close drop  bye ;
go
TFEOF
cat 010-lib.fth /tmp/test-fileio.fth | strip_forth | timeout 5 ./seed-forth
[ "$(cat /tmp/forth-fwio-test 2>/dev/null)" = "OK" ] && pass "lib: open/write/close round-trip writes correct bytes" || fail "fileio got: '$(cat /tmp/forth-fwio-test 2>/dev/null)'"

# T-lib: 010-lib.fth comparison, stack, arith, control-flow, defining words
out=$(cat 010-lib.fth test-010-lib.fth | strip_forth | timeout 5 ./seed-forth)
ec=$?
[ "$ec" = "0" ] && pass "010-lib.fth: all comparisons/arith/control/defining words" || fail "010-lib.fth got exit code $ec"

# ----- cc-*.fth layer -----

# T-cc-arena: cc-alloc, bytes-eq
out=$(cat 010-lib.fth 020-cc-arena.fth test-020-cc-arena.fth | strip_forth | timeout 5 ./seed-forth)
ec=$?
[ "$ec" = "0" ] && pass "cc-arena: alloc/align/bytes-eq" || fail "cc-arena got exit code $ec"

# T-cc-io: source-buffer reader, output-buffer emitter, patch, 8LE
out=$(cat 010-lib.fth 020-cc-arena.fth 030-cc-io.fth test-030-cc-io.fth | strip_forth | timeout 5 ./seed-forth)
ec=$?
[ "$ec" = "0" ] && pass "cc-io: peek/next/eof, emit/patch" || fail "cc-io got exit code $ec"

# T-cc-lex: tokenizer
out=$(cat 010-lib.fth 020-cc-arena.fth 030-cc-io.fth 040-cc-prep.fth 050-cc-lex.fth test-050-cc-lex.fth | strip_forth | timeout 5 ./seed-forth)
ec=$?
[ "$ec" = "0" ] && pass "cc-lex: tokens (kw/id/punct/num/str/chr/comment/escape)" || fail "cc-lex got exit code $ec"

# T-cc-types: ty-make, ty-base, ty-ptr, ty-size
out=$(cat 010-lib.fth 020-cc-arena.fth 030-cc-io.fth 040-cc-prep.fth 050-cc-lex.fth 060-cc-types.fth test-060-cc-types.fth | strip_forth | timeout 5 ./seed-forth)
ec=$?
[ "$ec" = "0" ] && pass "cc-types: make/base/ptr/size" || fail "cc-types got exit code $ec"

# T-cc-sym: symbol table
out=$(cat 010-lib.fth 020-cc-arena.fth 030-cc-io.fth 040-cc-prep.fth 050-cc-lex.fth 060-cc-types.fth 070-cc-sym.fth test-070-cc-sym.fth | strip_forth | timeout 5 ./seed-forth)
ec=$?
[ "$ec" = "0" ] && pass "cc-sym: add/find/kind/val/scope" || fail "cc-sym got exit code $ec"
