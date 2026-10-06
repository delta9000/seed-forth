# Decimal parsing and the interpreter loop: hints and solutions

Return to [Chapter 18](../chapters/18-decimal-parser-and-repl.md).
These answers are checked static derivations for the pinned Linux/x86-64
seed. They are not observations from executing the seed. Stack tops are
at the right; cells occupy eight bytes; U is `0xFFFFFFFFFFFFFFFF`.
Numeric tokens and accumulated values are decimal; addresses and explicit
byte strings are hexadecimal. Earlier data and the chapter's valid-storage
preconditions are retained throughout.

Use Hint 1 for orientation and Hint 2 for a concrete step. After consulting
a solution, close it and attempt its changed case. Matching the worked
answer with it visible is a different achievement from predicting a new
case independently.

## S18-01 — Keep digits and stack slots separate

**Hint 1.** `read_word` preserves 99 by putting it below the two new cells.
The parser advances RBP once near entry and reverses that movement in
either return tail.

**Hint 2.** At parser entry, `rbp=P-16`, `[P-16]=T`, and `[P-8]=99`.
After digit four, the middle digit zero still multiplies four by ten.
The loop branch follows DEC RCX, not ADD RAX,RDX.

**Worked solution.** Reading gives D=`[88,99,T,3]` with RDI=3. Entry
storage is `[P-16]=T`, `[P-8]=99`, `[P]=88`. The parser loads T into RSI
and changes RBP to P-8. Nonempty setup sets RAX=0 and RCX=3.

| Completed point | RAX | RSI | RCX | Relevant reason |
|---|---:|---|---:|---|
| Setup | 0 | T | 3 | Length was nonzero |
| Digit 4 | 4 | T+1 | 2 | `0*10+4` |
| Digit 0 | 40 | T+2 | 1 | `4*10+0` |
| Digit 7 | 407 | T+3 | 0 | `40*10+7` |

Each digit first passes both range checks. DEC RCX determines the ZF used
by the following JNZ. After the last decrement, RCX=0 and ZF=1, so that
branch falls through even though RAX is nonzero.

The success tail changes RBP from P-8 to P-16, stores 407 at `[P-16]`,
and loads U into RDI. Final D=`[88,99,407,U]`; 99 and 88 remain in their
original slots. The address input slot has become the value output slot,
and the cached length has become the cached flag. The helper replaces
two cells with two cells, so its entry and return RBP agree. Relative to
the state before `read_word`, there are still two extra cells until the
caller removes the flag.

**Wrong path to diagnose.** Returning `[88,99,U,407]` exchanges the roles
of the memory slot and cached top. Returning only 407 overlooks the
separate flag contract. Saying the cursor is T+2 on success overlooks the
INC that follows acceptance of the final byte.

**Changed case.** For `0407`, length four, the completed-iteration triples
`(RAX,RSI,RCX)` are `(0,T+1,3)`, `(4,T+2,2)`, `(40,T+3,1)`, and
`(407,T+4,0)`. Final D is still `[88,99,407,U]`. More input bytes require
more iterations, but the stack effect remains two cells replaced by two.
The leading zero is an accepted digit, not a base marker.

## S18-02 — Reject the whole token

**Hint 1.** Character conversion happens before INC RSI and DEC RCX.
A rejected byte is loaded but not counted as accepted.

**Hint 2.** ASCII `/` is `0x2F`; `:` is `0x3A`. Subtracting `0x30`
gives -1 and ten respectively. Empty input branches before RAX and RCX
are initialized for the loop.

**Worked solution.** For both four-byte nonempty tokens, digits one and
two leave RAX=12, RSI=T+2, and RCX=2. The third-byte paths differ:

| Input | Converted third byte | First taken failure branch | Cursor/count on failure | Returned pair |
|---|---:|---|---|---|
| `12/9` | -1, represented by U | JS at file `065F` | RSI=T+2, RCX=2 | `[0,0]` |
| `12:9` | 10 | JG at file `0665` | RSI=T+2, RCX=2 | `[0,0]` |
| Empty | No byte read | JZ at file `064F` | RSI=T; RCX not initialized on this path | `[0,0]` |

For the slash, SUB sets the sign flag and JS takes the failure branch;
CMP/JG are never reached. For the colon, SUB is nonnegative, so JS falls
through. CMP with nine establishes signed-greater and JG takes the same
failure tail. Neither rejection reaches the pointer increment or count
decrement for that byte. RAX still holds the accepted prefix twelve as a
scratch-register fact, but the tail stores an explicit zero as the value
result. The prefix is not returned.

For empty input, the address was loaded and its stack slot consumed,
then TEST saw RDI=0. No RAX=0 or RCX=0 initialization can be inferred:
the branch skips those instructions. The tail nevertheless returns two
known zeros and restores RBP to its parser-entry value. Earlier data is
preserved in every case.

MOVZX constrains the original byte to 0–255. Subtracting 48 produces the
signed range -48–207 without signed overflow. JS removes negatives;
among the remaining 0–207 candidates, signed JG against nine correctly
removes every value above nine. The parser does not interpret the eventual
64-bit accumulator as signed to validate its magnitude.

There is no unread `/9` or `:9` suffix caused by parser failure. The caller
already obtained a whole token from `read_word`; the parser only inspected
that token buffer. Its partial memory scan cannot reverse input reads.
`[lit]`, the actual caller, then reports the token and exits with status 2.

**Wrong path to diagnose.** A solution returning `[12,0]` follows the
scratch accumulator instead of the explicit failure store. A solution
reporting RCX=1 advances past the failing byte even though control skipped
DEC. A solution reporting an unread suffix confuses RSI with stream state.

**Changed case.** Supply two bytes `31 FF` (ASCII `1`, then byte `0xFF`).
After the first digit: RAX=1, RSI=T+1, RCX=1. MOVZX loads 255 from the
second byte, not -1. SUB gives 207; JS falls through and JG rejects it.
The returned pair is `[0,0]`. This changed case tests zero-extension at
the high-byte boundary rather than another punctuation spelling.

## S18-03 — Separate acceptance from exactness

**Hint 1.** Check two independent facts: do all the supplied bytes belong
to the digit grammar, and what low 64-bit value does the recurrence keep?

**Hint 2.** `18446744073709551615=2^64-1`; adding one wraps to zero.
The branch back to the digit loop consults the count, not the ADD carry.

**Worked solution.** Every nonempty token in the question consists solely
of accepted digits. Their results, omitting an unchanged older prefix,
are:

| Input | Returned value | Returned flag |
|---|---:|---|
| `0` | 0 | U |
| `18446744073709551615` | 18446744073709551615, the U bit pattern | U |
| `18446744073709551616` | 0 | U |
| Empty | 0 | 0 |

For the third row, the nineteen-digit prefix is 1844674407370955161.
LEA times five gives 9223372036854775805; doubling gives
18446744073709551610; adding six produces mathematical `2^64`, whose
low 64 bits are zero. The digit-six check has already succeeded. INC/DEC
leave RSI=T+20 and RCX=0, then the normal success tail returns zero with
U. No branch checks carry or overflow.

A caller testing the value instead of the flag would classify both the
valid small zero and the wrapped zero as failures. Conversely, the first
U in the maximum-value result is numeric data; the second U is its
success flag. Identical bit patterns do not give the two slots the same
job. Syntax acceptance and exact representation of an unbounded integer
are different claims.

The model recurrence is `(10*n+digit) modulo 2^64`. A successful flag
means the token was nonempty and every byte passed the digit checks. It
supplies no evidence that arithmetic never wrapped. The numeric boundary
calculation is derived here, not measured by running `[lit]`.

**Wrong path to diagnose.** `[0,0]` for `2^64` invents an overflow rejection.
Saying the final ADD's ZF chooses the success tail overlooks subsequent
INC/DEC and the count-controlled loop branch. Saying the maximum value
returns “two flags” ignores positional stack meaning.

**Changed case.** `18446744073709551623` is `2^64+7`, so it returns
`[7,U]`. Its prefix before the last digit is 1844674407370955162;
times ten wraps from `2^64+4` to four, then digit three produces seven.
All digits still pass. By contrast, `-1` fails on its first byte and
returns `[0,0]`; it is not a spelling for the maximum unsigned value.

## S18-04 — Dispatch one name at two times

**Hint 1.** A successful lookup leaves an xt in RDI and a header address
in LAST_FOUND. Only the latter points at the flags field's containing
record.

**Hint 2.** The `+` header is `0x4001AC`, xt=`0x4001B7`, flags=0.
The mode test distinguishes zero from nonzero, not zero from exactly one.
Semicolon's immediate bit bypasses that test.

**Worked solution.** In the interpret reset, reading `+` gives
D=`[99,7,3,T,1]`, then lookup leaves `[99,7,3,0x4001B7]` and stores
`0x4001AC` in LAST_FOUND. Loading its flag byte at header+8 produces
zero. The immediate branch is not taken. STATE=0 makes the next branch
select execution.

CALL `execute_code` saves `0x4006EA` on R. Execute consumes the xt and
tail-jumps to `plus_code` with D=`[99,7,3]`. Addition returns with
D=`[99,10]`; HERE remains `0x401021` and STATE remains zero. Its return
goes to the saved 06EA address, then the final jump reaches the next read.

In the compile reset, reading/lookup instead transform C=`[99]` into
`[99,T,1]`, then `[99,0x4001B7]`. Header and flags are identical. STATE=2
is nonzero, so the REPL calls `compile_call`. At HERE=`0x40101B`, the
five-byte instruction ends at `0x401020`; displacement to `0x4001B7` is
-3689, encoded `97 F1 FF FF`. Emission is `E8 97 F1 FF FF`. The helper
consumes the xt, restores C=`[99]`, and advances HERE to `0x401020`.
STATE remains two. No runtime addition has happened.

Reading `;` then produces its xt=`0x40054A` and
LAST_FOUND=`0x40053F`. The flags byte is one; JNZ at 06CF reaches
execution without the REPL's load/test of STATE. Execute removes the xt;
semicolon writes C3 at `0x401020`, moves HERE to `0x401021`, and stores
STATE=0. C remains `[99]`. Its own body does not need a prior STATE test
to perform these writes. The final C3 of `semicolon_code` returns from
the current invocation; the stored C3 belongs to the future compiled word.

A hypothetical flags byte `02` has bit zero clear, so a nonzero STATE
selects compilation. Byte `03` has bit zero set, so it selects execution
without consulting STATE. These hypothetical bytes test the mask's
meaning; they do not claim the initial seed has such flagged entries.

**Wrong path to diagnose.** `[99,10]` as the compile result adds values
that are not present on C. Loading flags from xt+8 confuses code and
header coordinates. Testing whether the whole flags byte is nonzero
would misclassify `02`.

**Changed case.** With immediate `[lit] 3`, C=`[99]`, STATE=2, and
HERE=`0x40100E`, the REPL still executes the found word before consulting
STATE. `[lit]` consumes its following token, parses it, and consults STATE
inside its own body. Nonzero two causes thirteen bytes of literal emission,
ending at `0x40101B`, with C=`[99]` and STATE still two. A word can execute
now in order to emit a different word's future runtime behavior.

## S18-05 — Explain continuation and termination

**Hint 1.** Use separate columns for stack, HERE, and STATE. A reported
miss performs no definition rollback and does not reset the mode.

**Hint 2.** After `find` misses, 99 is under the cached zero. Reporting
loads the stdout descriptor into RDI. The reload after reporting, not
register preservation inside reporting, restores 99.

**Worked solution.** Let `rbp=P`, `rdi=99` before starting. Colon consumes
the name `half`, writes its fourteen-byte header at `0x401000`, publishes
that header through LATEST, moves HERE to `0x40100E`, and sets STATE=1.
C returns to `[99]`. Immediate `[lit] 3` emits thirteen bytes, ending at
HERE=`0x40101B`, again with C=`[99]` and STATE=1.

The miss's physical steps are:

| Point | RBP | RDI | Significant live storage/result |
|---|---|---|---|
| Before reading `wobble` | P | 99 | C=`[99]` |
| After reading | P-16 | 6 | `[P-16]=T`, `[P-8]=99` |
| After missed lookup | P-8 | 0 | `[P-8]=99` |
| Report routine | P-8 | Clobbered for fd 1 | Requests `wobble?\n` on stdout |
| Reload at 06B6 | P-8 | 99 | Gets the saved earlier top |
| Advance at 06BA | P | 99 | C=`[99]` restored |

Neither cleanup instruction changes HERE or STATE. The next iteration
receives the reader's zero-length EOF result and jumps to `bye_code`,
which invokes `exit(0)`. HERE is still `0x40101B`, STATE still one, and
LATEST still identifies `half` at the point this exit route is taken.
The definition's earlier bytes were neither undone nor completed. No
semicolon ran, so the final return byte was not supplied. The process
ending normally does not certify a complete definition.

For `[lit] 12x4 bye` in interpret mode, the first token is found and
executed. `[lit]` reads all of `12x4`, the parser returns `[0,0]`, and
`[lit]` jumps to `fatal_token`. That helper requests `12x4?\n` and invokes
`exit(2)`. Control never returns to look up `bye`; the unexamined suffix
inside the failed token has not become fresh input.

For bare `12x4 bye`, the outer loop finds no matching dictionary entry
for `12x4`. It requests the same report, restores the older stack, and
continues. It then finds ordinary `bye`; STATE=0 selects execution, and
`bye` invokes `exit(0)`. The report spelling alone therefore does not
identify which exit/continuation path was taken. The token's caller does.

These are all static control-flow and output-request predictions. A
complete stdout write, an observed process status, and a real execution
trace have not been measured in this manuscript pass. Neither source
inspection nor the arithmetic checks turn them into executed observations.

**Wrong path to diagnose.** Restoring RDI before calling `report_token`
would let that call clobber the restored 99. Saying a miss cancels STATE
invents a store absent from the loop. Saying exit zero appends RET invents
a call to semicolon absent from the EOF branch.

**Changed case.** Insert `;` before EOF in
`: half [lit] 3 wobble ;`. The miss still reports and skips `wobble`.
The next token's immediate bit executes semicolon, appending C3 at
`0x40101B`, moving HERE to `0x40101C`, and clearing STATE. EOF still
invokes `exit(0)`. This time a terminating return was supplied, but the
unknown word's intended behavior is still absent. Completing the body
shape does not recover a skipped operation.
