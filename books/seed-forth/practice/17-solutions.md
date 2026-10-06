# Inline branch operands: hints and solutions

Return to [Chapter 17](../chapters/17-inline-branch-operands.md).
These are checked static derivations for the pinned Linux/x86-64 seed,
not executed observations. Stack tops are at the right; cells occupy
eight bytes and use little-endian memory order. Hexadecimal numbers carry
`0x`, except within byte strings and explicitly labeled file offsets.
Each changed case is a fresh paper reset.

Try the first hint before the second. After comparing your trace with the
solution, close it and attempt the changed case independently. Focus on
the first different transition rather than copying the final answer.

## S17-01 — Keep three addresses separate

**Hint 1.** The CALL's destination is the primitive's entry, not the
address stored in the inline cell. Label A, S, and T before calculating.

**Hint 2.** The origin for the four-byte distance is `0x402005`.
The primitive's entry is `0x400611`. RET consumes the item most recently
pushed on R.

**Worked solution.** The call site has A=`0x402000`, S=`0x402005`,
and T=`0x401080`. The call's displacement is:

```text
0x400611 - 0x402005 = -0x19F4 = -6644 decimal
32-bit encoding: 0xFFFFE60C
CALL bytes:      E8 0C E6 FF FF
inline bytes:    80 10 40 00 00 00 00 00
```

The five call bytes occupy virtual range `[0x402000,0x402005)`;
the eight target bytes occupy `[0x402005,0x40200D)`. This unconditional
branch does not select the following address `0x40200D`.

| Completed action | RAX | RSP | Live R |
|---|---|---|---|
| Before CALL | Irrelevant | V | `Rbase` |
| CALL | Irrelevant | V-8 | `Rbase,0x402005` |
| POP RAX | `0x402005` | V | `Rbase` |
| MOV RAX,[RAX] | `0x401080` | V | `Rbase` |
| PUSH RAX | `0x401080` | V-8 | `Rbase,0x401080` |
| RET | `0x401080` | V | `Rbase`; resume at `0x401080` |

D stays `[55,7]`; RDI, RBP, and data-stack memory are unchanged.
The eight-byte cell at S still contains T. Its address disappeared from
the live R at POP, and T disappeared from the live R at RET. T remaining
in RAX is harmless scratch state, not a leaked return-stack cell.

**Wrong path to diagnose.** Encoding `T-S` into the CALL would make
CALL target `0x401080` directly, bypassing the primitive. Leaving T on
the post-RET R instead confuses the state before RET with the state after.

**Changed case.** Keep A and the primitive unchanged, but patch T to
`0x402080`, now forward of the branch site. CALL stays
`E8 0C E6 FF FF`; only the cell changes to `80 20 40 00 00 00 00 00`.
R returns to `Rbase` and execution resumes at `0x402080`. Changing the
program destination does not require changing the call to the primitive.

## S17-02 — Consume the original flag

**Hint 1.** The first instruction preserves f before the old next-deeper
value replaces it in RDI. Keep scratch registers separate from logical D.

**Hint 2.** By TEST, RDI is seven and RBP is P+8 for every f. TEST
must therefore use RDX if its decision is to depend on the original flag.

**Worked solution.** Each reset uses A=`0x401000`, S=`0x401005`,
T=`0x401080`. Start with R=`Rbase`, RSP=V, D=`[99,7,f]`:

| Completed action | RDX | RDI | RBP | RAX | Live R |
|---|---|---|---|---|---|
| CALL | Irrelevant | f | P | Irrelevant | `Rbase,S` |
| MOV RDX,RDI | f | f | P | Irrelevant | `Rbase,S` |
| MOV RDI,[RBP] | f | 7 | P | Irrelevant | `Rbase,S` |
| ADD RBP,8 | f | 7 | P+8 | Irrelevant | `Rbase,S` |
| POP RAX | f | 7 | P+8 | S | `Rbase` |
| TEST; choose path | f | 7 | P+8 | Q | `Rbase` |
| PUSH RAX | f | 7 | P+8 | Q | `Rbase,Q` |
| RET | f | 7 | P+8 | Q | `Rbase` |

RSP is V-8 after CALL, V after POP, V-8 after PUSH, and V after RET.
The load/pointer pair has completed the data removal before TEST.
`[P+8]=99` is now the next-deeper live cell; no bytes have been erased.
The three selections are:

| Original f | ZF after TEST | JNZ | Q | Final D |
|---|---:|---|---|---|
| 0 | 1 | Not taken | T=`0x401080` | `[99,7]` |
| 2 | 0 | Taken | S+8=`0x40100D` | `[99,7]` |
| `0x8000000000000000` | 0 | Taken | S+8=`0x40100D` | `[99,7]` |

The high-bit-only value is nonzero even though its signed interpretation
is negative. TEST does not normalize it or require a canonical flag.
On zero, MOV loads T and JMP skips ADD; on either nonzero value, JNZ
skips that load and JMP, reaching the ADD with RAX still equal to S.

Replacing TEST RDX,RDX by TEST RDI,RDI tests seven on all three resets.
ZF would always be zero, so every reset would select S+8. The zero case
would incorrectly enter the body. Neither data cleanup nor return-stack
balance detects this wrong choice: both can remain correct while control
flow is wrong.

**Wrong path to diagnose.** Saying the flag survives on D because RDX
still holds it confuses scratch storage with the cached-top invariant.
D's top is seven after cleanup; RDX is not a second Forth top.

**Changed case.** Use `[99,0,2]`: initially `[P]=0` and RDI=2.
The real code saves two, restores zero, and still chooses S+8, leaving
`[99,0]`. The defective test of RDI instead chooses T. This changes the
older data value while holding the actual flag fixed, exposing which
value the decision improperly depends on.

## S17-03 — Recover the two origins

**Hint 1.** A relative jump counts from the first byte after itself.
List the skipped instructions with their lengths.

**Hint 2.** JNZ ends at file offset `0639`; JMP ends at `063E`.
Changing `75` to `74` reverses the tested zero condition without changing
its destination or instruction length.

**Worked solution.** JNZ occupies `[0x637,0x639)`. Its destination is
`0x63E`, so the displacement is `0x63E-0x639=5`. The skipped sequence
is a three-byte MOV and a two-byte JMP. JMP occupies `[0x63C,0x63E)`;
its destination is `0x642`, so its displacement is `0x642-0x63E=4`,
the length of ADD RAX,8. The image base cancels from these subtractions.

For edit (a), `74 05` is JZ to the same ADD:

| f | New JZ action | Selected destination |
|---|---|---|
| Zero | Take jump to ADD with RAX=S | S+8 |
| Any nonzero | Continue to load, then JMP | T |

This reverses the conditional's meaning. It does not change the
unconditional primitive or restore the flag: the earlier RDI reload and
RBP advance still occur on both paths.

For edit (b), the question stipulates control continuing into the ADD
after the load, without shifting any byte locations. With zero, MOV first
makes RAX=T, then ADD makes it T+8. RET selects T+8, not T. With nonzero,
JNZ already reaches ADD with RAX=S, so RET still selects S+8. On the
chapter's model, the zero selection becomes `0x401088` instead of
`0x401080`. Nothing establishes that this new address is a valid intended
instruction boundary. Both paths still consume one flag and restore R.

Actually deleting bytes from an image would additionally shift later
locations and require a fresh layout audit. That is different from the
stated paper control-flow counterfactual.

**Wrong path to diagnose.** Computing `0x63E-0x637=7` uses the JNZ
opcode's start instead of its end. Encoding seven would reach `0x640`,
inside ADD's encoding, not its beginning.

**Changed case.** Move this whole primitive twenty hexadecimal bytes
later in an independent paper layout, preserving its internal instruction
lengths. JNZ now occupies `[0x657,0x659)` and targets `0x65E`; JMP
occupies `[0x65C,0x65E)` and targets `0x662`. Their bytes remain `75 05`
and `EB 04`. Calls from elsewhere would need their own recalculated
displacements. This local calculation alone does not validate a relocated
seed or update any dictionary execution token.

## S17-04 — Distinguish untested from valid

**Hint 1.** Ask which path actually reads the inline cell. A cell can
contain the wrong target without affecting the other path's calculation.

**Hint 2.** S is 5005 decimal. The eight-byte patch must encode 5040,
not 5005, 5013, or a difference between them.

**Worked solution.** A=5000, S=5005, S+8=5013, all decimal. For flag
two, TEST finds nonzero; the primitive never loads `[S]`. It selects 5013
and consumes two. For flag zero, it loads the unpatched cell's contents
zero and selects address zero, consuming that flag too. Address zero is
outside the stated valid-destination contract; no particular subsequent
fault or output is established by this trace.

Repair the cell beginning at 5005 with absolute destination 5040:

```text
5040 decimal = 0x13B0
little-endian eight bytes: B0 13 00 00 00 00 00 00
```

That patch changes neither the five-byte CALL nor the fallthrough
address. Now zero selects 5040 and nonzero selects 5013, assuming both
are valid instruction boundaries with suitable continuation contracts.
Inspecting the patch and tracing both choices addresses this specific
bug. A finite set of passing cases still does not validate every possible
program, stack, or memory arrangement.

A bare interpreted `0branch` receives a native return address into the
interpreter's instructions. No target cell has been promised there.
Treating those bytes as an address, or skipping eight of them, violates
the call-site contract even if the data stack supplies a flag. Stack
operands cannot make the missing inline payload appear.

**Wrong path to diagnose.** A correct nonzero outcome is not evidence
that a zero placeholder has been patched. That path's calculation is
independent of the placeholder's contents.

**Changed case.** Suppose the patched cell holds its own address, 5005,
encoded as `8D 13 00 00 00 00 00 00`. Nonzero still selects 5013. Zero
selects 5005, entering the target data rather than the intended code at
5040. A nonzero stored target is therefore not sufficient evidence of a
correct patch either. Its role and instruction boundary matter.

## S17-05 — Preserve ownership across repetition

**Hint 1.** Use the countdown loop's already-derived addresses. DUP
supplies the flag while retaining the current count for subtraction.

**Hint 2.** The conditional at 1005 selects 1018 or 1049. The backward
branch at 1036 always selects 1000. Each primitive preserves the complete
R it had before its own CALL, including a borrowed value.

**Worked solution.** The stipulated owner already has `saved` parked
before entering this countdown body. Define
`Rbase=[…,ret(owner),saved]`. This is a paper use of the loop body with
that borrowed temporary; no additional call frame is inserted between
this base and the first loop instruction. All following addresses are
decimal:

| Branch visit | D on entry to primitive | Selected Q | D after RET | R after RET |
|---|---|---:|---|---|
| First conditional, A=1005 | `[99,2,2]` | 1018 | `[99,2]` | `Rbase` |
| First backward branch, A=1036 | `[99,1]` | 1000 | `[99,1]` | `Rbase` |
| Second conditional, A=1005 | `[99,1,1]` | 1018 | `[99,1]` | `Rbase` |
| Second backward branch, A=1036 | `[99,0]` | 1000 | `[99,0]` | `Rbase` |
| Final conditional, A=1005 | `[99,0,0]` | 1049 | `[99,0]` | `Rbase` |

Between each nonzero conditional and backward branch, the body pushes
one and subtracts. Each conditional temporarily pushes S=1010 through
CALL, removes it with POP, selects Q, pushes Q, then consumes Q with RET.
Each backward branch does the same with S=1041 and Q=1000. No iteration
leaves either address on R.

But `saved` remains. The unmodified final RET at 1049 would consume it
as an instruction destination, violating the owner's return obligation.
The primitive's RET at the preceding conditional and the owner's final
RET are distinct events.

A corrected owner can place `r> drop` on its exit path before its own
RET, updating and repatching the generated layout accordingly. R> recovers
`saved` onto D, giving `[99,0,saved]`, while preserving and then consuming
its own temporary call destination. DROP restores `[99,0]`. Now R is
`[…,ret(owner)]`; the owner's RET uses the correct return destination.
This proposal adds code, so the old final-RET address 1049 would no longer
be its final-RET address. At 1049 the exit can instead begin that cleanup.

**Wrong path to diagnose.** “The branches restore R, so the final RET
is safe” omits what was already in R. Restoring a borrowed temporary
preserves ownership; it does not discharge the obligation to remove it.

**Changed case.** Start the same body with D=`[99,0]`. The first DUP
produces `[99,0,0]`; the conditional selects 1049 immediately, leaving
`[99,0]` and the same `Rbase`. There are no decrement passes or backward
branches, but the owner still owes exactly the same cleanup. A
zero-iteration loop does not remove a temporary borrowed before it began.
