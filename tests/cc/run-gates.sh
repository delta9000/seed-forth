#!/usr/bin/env bash
# run-gates.sh — run every registered C gate through run-gate.sh.
# Each entry: "<file> <expected-exit> [expected-stdout]".
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
)

fail=0
for g in "${gates[@]}"; do
  if ! tests/cc/run-gate.sh $g; then fail=1; fi
done
exit $fail
