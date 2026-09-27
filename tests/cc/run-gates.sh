#!/usr/bin/env bash
# run-gates.sh — run every registered C gate through run-gate.sh, then
# every die gate through run-die-gate.sh.
# Each gate entry: "<file> <expected-exit> [expected-stdout]".
set -uo pipefail
cd "$(dirname "$0")/../.."

# Registry.
# Existing G-gates: exits determined by reading source comments/math and
# empirically confirmed with run-gate.sh.
#
# G10c: sizeof(int)=4, sizeof(int*)=8, sizeof(int[7])=28, sizeof(struct Pair)=16,
#       sizeof(int)=4 → actual sum=96 (struct Pair padded to 16 bytes by cc).
#
# G13: switch with fallthrough; sum=2162 → exit 2162%256=114.
#
# G14d: bump() returns 101 then 102; 101+102+7+11=221.
#
# Excluded: M1.c — not a standalone gate; it #includes cc.h and reads
# tape_01/tape_02 at runtime; it is exercised by 05-stage-a instead.
gates=(
  # Existing gates (G and M series)
  "G0.c 42"
  "G1.c 10"
  "G2.c 41"
  "G3.c 42"
  "G4.c 42"
  "G5.c 60"
  "G6a.c 50"
  "G6b.c 7"
  "G7.c 7"
  "G8.c 30"
  "G9a.c 42"
  "G9b.c 42"
  "G10a.c 204"
  "G10b.c 42"
  "G10c.c 96"
  "G11.c 141"
  "G12.c 47"
  "G13.c 114"
  "G14a.c 95"
  "G14b.c 42"
  "G14c.c 8"
  "G14d.c 221"
  "M1a.c 127"
  "M1b.c 51"
  # New bug-fix gates (Tasks A–H); files created by later tasks.
  "A-locals18.c 100"
  "B-switch-continue.c 0"
  "C-struct-global.c 7"
  "D-charptr-store.c 9"
  "E-chained-subscript.c 91"
  "F-wide-const.c 7"
  "G-indented-define.c 42"
  "H-comment-directive.c 3"
  "I-cr-escape.c 13"
  # Correctness fixes found while building pnut (research notes).
  "J-extern-then-def.c 3"
  "K-static-local.c 3"
  "L-starpp-char.c 45"
  "N-string-index.c 98"
  "O-octal-escapes.c 179"
  # The C that pnut needs (tests/pnut/sf-pnut-check.sh).
  "P1-conditionals.c 63"
  "P2-fn-macros.c 30"
  "P3-casts.c 74"
  "P4-declarations.c 42"
  "P5-lvalue-ops.c 46"
  "P6-case-labels.c 31"
  "P7-array-sizes.c 42"
  "P8-libc-shims.c 42 ok"
)

# Die gates: programs the compiler must reject.  Each entry:
# "<file> <expected-exit> <expected last stderr line>" (run-die-gate.sh).
# One per capacity check in 020-116, one per malformed-directive and
# constant-expression check, plus the whole-program checks at the end of
# cc-parse-program (206, 207); the line is where cc-die found the reader
# (Appendix G).  Code 22 (output file won't open) and 62 (scope pop
# without a push, a parser bug) cannot be reached from a C program.
die_gates=(
  "die-10-arena-full.sh|10|cc: line 50: error 10"
  "die-20-input-too-big.sh|20|cc: line 1: error 20"
  "die-21-output-full.sh|21|cc: line 38819: error 21"
  "die-30-include-missing.c|30|cc: line 2: error 30"
  "die-31-include-deep.c|31|cc: line 11: error 31"
  "die-32-include-too-big.sh|32|cc: line 1: error 32"
  "die-33-include-path-long.sh|33|cc: line 1: error 33"
  "die-34-macro-table-full.sh|34|cc: line 1014: error 34"
  "die-35-macro-pool-full.sh|35|cc: line 328: error 35"
  "die-36-source-too-big.sh|36|cc: line 69: error 36"
  "die-37-macro-scratch-full.sh|37|cc: line 2: error 37"
  "die-38-if-too-deep.sh|38|cc: line 65: error 38"
  "die-39-if-unterminated.c|39|cc: line 7: error 39"
  "die-40-error-directive.c|40|cc: line 5: error 40"
  "die-41-else-without-if.c|41|cc: line 5: error 41"
  "die-42-ifdef-no-name.c|42|cc: line 2: error 42"
  "die-43-macro-scratch-deep.sh|43|cc: line 2: error 43"
  "die-44-macro-call-open.c|44|cc: line 6: error 44"
  "die-45-macro-args.c|45|cc: line 5: error 45"
  "die-46-macro-args-max.c|46|cc: line 4: error 46"
  "die-47-define-params.c|47|cc: line 3: error 47"
  "die-48-define-params-max.c|48|cc: line 2: error 48"
  "die-50-struct-fields.c|50|cc: line 19: error 50"
  "die-60-symbols-full.sh|60|cc: line 4066: error 60"
  "die-61-scopes-deep.c|61|cc: line 66: error 61"
  "die-80-globals-full.sh|80|cc: line 515: error 80"
  "die-81-global-refs-full.sh|81|cc: line 16387: error 81"
  "die-82-bss-full.c|82|cc: line 3: error 82"
  "die-113-inc-not-lvalue.c|113|cc: line 4: error 113"
  "die-124-const-div-zero.c|124|cc: line 2: error 124"
  "die-125-const-not-enum.c|125|cc: line 4: error 125"
  "die-126-const-bad.c|126|cc: line 4: error 126"
  "die-127-const-paren.c|127|cc: line 2: error 127"
  "die-128-const-colon.c|128|cc: line 2: error 128"
  "die-129-if-trailing.c|129|cc: line 2: error 129"
  "die-162-frame-full.c|162|cc: line 7: error 162"
  "die-171-labels-full.sh|171|cc: line 67: error 171"
  "die-206-fn-undefined.c|206|cc: line 8: error 206"
  "die-207-no-main.c|207|cc: line 5: error 207"
)

fail=0
for g in "${gates[@]}"; do
  if ! tests/cc/run-gate.sh $g; then fail=1; fi
done
for g in "${die_gates[@]}"; do
  IFS='|' read -r file code line <<< "$g"
  if ! tests/cc/run-die-gate.sh "$file" "$code" "$line"; then fail=1; fi
done
exit $fail
