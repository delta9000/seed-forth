# 17. Inline branch operands

[Previous: The native colon compiler](16-native-colon-compiler.md) · [Practice help](../practice/17-solutions.md) · [Next: Decimal parser and REPL](18-decimal-parser-and-repl.md)

A loop returns to its beginning many times, but its return stack must not
get deeper on every trip. The seed implements that backward edge with a
CALL and a RET. Where did the extra return address go?

[Chapter 9](09-control-flow-by-patching.md) established the emitted layouts.
Now we open their two runtime primitives: six bytes for `branch` and 28
for `0branch`. By the end, you should be able to account for all 34 bytes,
follow either destination through the physical stacks, and distinguish a
balanced branch from a word that still owes its caller cleanup.

## Bring the contracts

Use [Chapter 12's](12-physical-stacks-and-memory.md) cached data top and
native return stack, [Chapter 13's](13-arithmetic-in-instruction-bytes.md)
whole-cell zero test, and [Chapter 16's](16-native-colon-compiler.md)
inline literal. Check: a five-byte CALL starts at A. What return address
does it save? After POP removes that address, PUSH installs another, and
RET executes, how many of those two addresses remain on the live return
stack? The answers are A+5 and none. If uncertain, recover the literal
trace first. Otherwise, try S17-02 and S17-03 before the worked examples.

**Evidence boundary.** We inspect `000-seed.hex0` at
[revision bbcc1732152af2d884737272eed870d2410ffe8e](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0).
Both body listings were checked against the source bytes and bounded GNU
objdump 2.44 disassembly of the source-decoded image. The traces below are
manual derivations, not seed executions. No build or timing measurement
supports these explanations.

Cells are eight bytes, memory is little-endian, and logical stack tops
are at the right. D is the data stack: `rdi` caches its top and `rbp`
points to the next-deeper cell. R uses native `rsp`. Assume sufficient
operands and stack space, intact code and return destinations, readable
inline cells, and valid executable destinations. Paper addresses identify
model locations, not commands to execute.

Each instruction row gives a **half-open hexadecimal file-offset range**:
include its start, exclude its end. Add `0x400000` for the mapped virtual
address. S17 owns exactly these bodies:

| Body | File range | Instructions | Bytes |
|---|---|---:|---:|
| `branch_code` | `[0x611,0x617)` | 4 | 6 |
| `zbranch_code` | `[0x628,0x644)` | 11 | 28 |

The intervening dictionary headers belong to
[Chapter 15](15-dictionary-and-token-input.md). Their bytes are not counted
again here.

## One call site contains two different destinations

A complete branch site has this contract:

```text
At A:       E8 + four-byte relative displacement    CALL primitive
At S=A+5:   eight-byte absolute address T           inline target cell
At S+8:     next instruction                       fallthrough
```

The five-byte CALL reaches `branch_code` at `0x400611` or `zbranch_code`
at `0x400628`. Its relative distance is measured from S. Separately, the
cell at S holds the absolute destination T chosen by the compiling word.
The target cell is neither part of CALL's displacement nor a data-stack
operand. Its full thirteen-byte layout is the contract established by
[the library's branch combinators](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/010-lib.fth#L299-L358).

CALL saves S on R. The primitive obtains S with POP, then selects an
address Q: always T for `branch`; T for zero or S+8 for nonzero in
`0branch`. PUSH and RET transfer control to Q. “Fallthrough” here means
continuing after the inline data; the processor does not execute through
those eight bytes to get there.

The near CALL/RET stack effects follow Intel's
[CALL entry](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-2a-manual.pdf#page=224)
and [RET entry](https://cdrdv2-public.intel.com/868141/253667-089-sdm-vol-2b.pdf#page=568).
We use their architectural effects, without inferring a return-prediction
benefit or a particular speed from this instruction sequence.

## Four instructions: replace a return destination

The complete [`branch_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L607-L611)
contains no native JMP instruction:

```text
offset range  bytes             decoded instruction
[0611,0612) 58                  pop rax
[0612,0615) 48 8B 00            mov rax, qword [rax]
[0615,0616) 50                  push rax
[0616,0617) C3                  ret
```

`58` and `50` select POP and PUSH of the 64-bit `rax` register in this
mode. POP loads the cell at `rsp`, then advances `rsp` by eight; PUSH
reserves eight bytes and writes the register there. `C3` is the near
return without an extra stack-cleanup immediate.

In `48 8B 00`, REX.W selects an eight-byte load. ModR/M `00` splits as
`00 | 000 | 000`: memory at RAX, destination RAX, no displacement. The
old RAX supplies the address before the load replaces it with the cell's
contents. Reading an address through itself does not add that address to
the destination. The result is T, not S+T.

Use a paper call at `A=0x401000`, slot `S=0x401005`, containing
`T=0x401080`. Let `rsp=V` before CALL, and let `Rbase` include the
surrounding word's return destination and any properly owned temporaries.
D starts `[99,7]` and remains unchanged throughout:

| Completed action | `rax` | `rsp` | Live R, top right |
|---|---|---|---|
| Before CALL | Irrelevant | V | `Rbase` |
| CALL reaches primitive | Irrelevant | V-8 | `Rbase, S` |
| POP at `0611` | S | V | `Rbase` |
| Load at `0612` | T = Q | V | `Rbase` |
| PUSH at `0615` | Q | V-8 | `Rbase, Q` |
| RET at `0616` | Q | V | `Rbase`; execution resumes at Q |

**After RET, neither S nor Q remains on the live R.** Q is consumed as
the instruction destination. It can still be present in scratch RAX or
stale memory outside the live stack; those are different facts.

The inline cell at S also remains intact. It still contains T, so another
visit can read it again. Consuming the slot's temporary stack address is
not erasing the memory cell. This distinction is why a branch can be
reused on every loop iteration.

## Eleven instructions: consume the flag before choosing

The complete [`zbranch_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L618-L631)
first restores the data-stack representation, then makes its choice:

```text
offset range  bytes             decoded instruction
[0628,062B) 48 89 FA            mov rdx, rdi
[062B,062F) 48 8B 7D 00         mov rdi, qword [rbp]
[062F,0633) 48 83 C5 08         add rbp, 8
[0633,0634) 58                  pop rax
[0634,0637) 48 85 D2            test rdx, rdx
[0637,0639) 75 05               jnz 0x40063E
[0639,063C) 48 8B 00            mov rax, qword [rax]
[063C,063E) EB 04               jmp 0x400642
[063E,0642) 48 83 C0 08         add rax, 8
[0642,0643) 50                  push rax
[0643,0644) C3                  ret
```

Start with `D=[99,7,f]`, `rdi=f`, `rbp=P`, `[P]=7`, and `[P+8]=99`.
The first MOV preserves the **original flag** in RDX. Its ModR/M byte
`FA = 11 | 111 | 010` selects register source RDI and destination RDX.
The next MOV loads seven into RDI; its `7D 00` addressing is the familiar
RBP base with a zero displacement. ADD then advances RBP to P+8. Only
now is the physical removal complete: D is `[99,7]`, with 99 below the
cached seven. No data-stack memory is erased or written.

The flag still exists in scratch RDX, but it is no longer a Forth stack
item. Testing RDI now would test seven instead of f. If f was the only
logical value, the same reload would restore the saved dummy and the
pointer would reach the empty-stack position from Chapter 12. The body
requires a flag; it does not check for underflow.

### Test the saved value, not the pointer arithmetic

`48 85 D2` is a full-width TEST. `D2 = 11 | 010 | 010` names RDX
in both operand fields. TEST computes a bitwise AND for processor flags
without replacing RDX. A value AND itself is zero exactly when every bit
is zero, so ZF=1 exactly when f=0. The immediately following JNZ takes
its jump when ZF=0. Objdump calls the same encoding JNE; both names refer
to this condition. See Intel's
[TEST entry](https://cdrdv2-public.intel.com/868141/253667-089-sdm-vol-2b.pdf#page=715)
and [Jcc entry](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-2a-manual.pdf#page=585).

Order matters. ADD RBP changes processor flags for its pointer result,
just as Chapter 13's arithmetic cleanup did. TEST comes afterward and
sets the condition the branch actually needs. There is no flag-changing
instruction between TEST and JNZ.

With f=0, JNZ is not taken. The load replaces S in RAX with `[S]=T`.
The unconditional JMP then skips the fallthrough adjustment, so T is
pushed unchanged. With any nonzero f, JNZ skips both that load and JMP,
reaching ADD RAX,8 while RAX still holds S. That ADD selects S+8.
Its later status flags do not affect a second decision: PUSH and RET
follow directly.

Thus 2, `0x100`, `0x8000000000000000`, and `0xFFFFFFFFFFFFFFFF`
all select S+8. This is neither “positive” nor “equal to canonical true.”
Both paths consumed exactly one flag before the decision.

### Where the short displacements start

The two embedded machine jumps use signed one-byte **relative** distances,
unlike the eight-byte **absolute** inline target:

| Instruction | Origin after instruction | Displacement | Resulting file offset |
|---|---:|---:|---:|
| JNZ at `0637` | `0639` | `05` = +5 | `063E` |
| JMP at `063C` | `063E` | `04` = +4 | `0642` |

JNZ skips the three-byte load plus the two-byte JMP. JMP skips the
four-byte ADD. Adding the image base to both origins and destinations
gives the displayed virtual targets. Do not measure either displacement
from its opcode byte. These transfer rules are specified by the
[Jcc entry](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-2a-manual.pdf#page=588)
and [JMP entry](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-2a-manual.pdf#page=590).

Finish the physical trace with the same A, S, T, and V used above:

| Point | Data state | `rax` | Live R |
|---|---|---|---|
| Before CALL | `[99,7,f]`, `rbp=P` | Irrelevant | `Rbase`, `rsp=V` |
| Entry | Unchanged | Irrelevant | `Rbase,S`, `rsp=V-8` |
| Save flag; reload; advance | `[99,7]`, `rbp=P+8`, `rdx=f` | Irrelevant | `Rbase,S` |
| POP S | Same | S | `Rbase`, `rsp=V` |
| TEST and path selection complete | Same | Q=T if zero; Q=S+8 otherwise | `Rbase` |
| PUSH Q | Same | Q | `Rbase,Q`, `rsp=V-8` |
| RET | Same | Q | `Rbase`, `rsp=V`; resume at Q |

## Reconnect the compiled layouts

Chapter 9 already derived the following independent layouts using decimal
paper addresses. Here the new result is their physical implementation,
not another compilation walkthrough:

| Existing example | Conditional site and slot | Zero destination | Nonzero destination |
|---|---|---:|---:|
| `maybe-add` | A=1000, S=1005 | 1031, final RET | 1013, push one then add |
| `choose-byte` | A=1000, S=1005 | 1039, false arm | 1013, true arm |
| `countdown` | A=1005, S=1010 | 1049, loop exit | 1018, decrement body |

`choose-byte`'s true arm later calls unconditional `branch` at 1026;
its cell at 1031 contains 1052, the common final RET. That branch selects
1052 without changing D. The earlier conditional already consumed the
flag, so the second branch needs no second flag.

`countdown`'s backward site is A=1036, S=1041, `[S]=1000`. The load
selects 1000 exactly as it would select a larger address. No comparison
asks whether the target is forward or backward. Both targets are
absolute cells, whereas the calls reaching the primitives use rel32.

For each valid branch visit, R begins as `Rbase` and finishes as that
same `Rbase`. Repeat this reasoning for any finite number of completed
visits: each visit adds and removes its own temporary cells, so those
branches contribute no accumulated return-stack depth. Other instructions
in the loop must still obey their contracts. This is stack accounting,
not a termination or whole-program safety argument.

### A balanced branch cannot clean up its owner

Suppose `Rbase=[…,ret(owner),saved]` because the surrounding word used
`>r`. A branch preserves that complete base, including `saved`. An
`exit,` compiles a RET in the surrounding word; it would consume `saved`
as a destination if the word had not first retrieved it with `r>`.
Chapter 9's `saved-or-zero` supplies cleanup on both paths, consistent
with the [library's early-return contract](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/010-lib.fth#L366-L372).
Branch balance and owner cleanup are separate obligations.

## Two ways a plausible demonstration can miss the contract

An unfinished `if,` slot initially contains zero. A nonzero flag can
appear to work: this path adds eight to S and never loads `[S]`. It says
nothing about whether the other destination is valid. On zero, the
primitive loads zero and attempts to return there, outside the example's
valid-destination contract. Do not invent a particular diagnostic.
Checking the patched cell, both instruction boundaries, and both paths
is stronger evidence than observing only the nonzero outcome; finite
examples still do not establish arbitrary programs are safe.

A bare interpreted `branch` or `0branch` has a different problem. Its
caller supplies an ordinary return address into interpreter instructions,
not a promised eight-byte target cell. `branch` would treat those
instructions as an address; nonzero `0branch` would skip eight bytes of
them. Neither is a valid use merely because a CALL occurred. An ordinary
compiled call without the payload has the same defect. The primitive's
stack effect alone omits this essential call-site requirement.

## Practice

All edits below are paper counterfactuals. Do not patch or execute the
seed. [Graduated hints, checked solutions, and changed cases](../practice/17-solutions.md)
are separate from the attempts.

### S17-01 — Keep three addresses separate

A valid unconditional branch starts at `0x402000`; its cell contains
`0x401080`. Derive the five CALL bytes, eight cell bytes, and all R states
from before CALL through after RET, using `rsp=V` and D=`[55,7]`.
Which address identifies the slot, which reaches the primitive, and which
is consumed by RET? What remains in memory?

### S17-02 — Consume the original flag

Reset `rdi=f`, `rbp=P`, `[P]=7`, `[P+8]=99`, and the chapter's
A/S/T. Trace zero, two, and `0x8000000000000000` through `0branch`.
Include RDX, RDI, RBP, ZF at TEST, selected Q, and post-RET R. Diagnose
replacing TEST RDX,RDX with TEST RDI,RDI after the existing cleanup.

### S17-03 — Recover the two origins

Derive both short displacements from instruction lengths. On separate
paper resets, diagnose (a) `75 05` becoming `74 05`, and (b) omitting
execution of the JMP at `063C` so the zero path also executes ADD RAX,8.
Which destination does each flag choose, and does either defect restore
a consumed data flag?

### S17-04 — Distinguish untested from valid

At A=5000 decimal, a `0branch` slot remains zero; the intended patched
destination is 5040 and the continuation at 5013 is valid. Predict the
selections for flags 2 and 0. Give the repair's slot address and eight
bytes. Explain why the first successful-looking path cannot validate the
second, and why interpreting `0branch` does not supply a substitute slot.

### S17-05 — Preserve ownership across repetition

Use Chapter 9's `countdown` body layout from D=`[99,2]`. Stipulate an
owner that has already parked `saved`, with R=`[…,ret(owner),saved]`
before the first loop instruction; insert no additional call frame.
Trace each conditional and backward branch's Q and post-RET R through
the zero test. Before the final RET, what must happen to `saved`?
Compare removing it with `r> drop` and leaving it untouched. Separate
the branch invariant from the complete word's return precondition.

## Stop, check, and continue

The audit covers 15 instruction rows and **34 bytes**, with no headers
or generated call-site bytes added to that total. The static decoder used
binary input, x86-64 mode, Intel syntax, base `0x400000`, and exact virtual
bounds `[0x400611,0x400617)` and `[0x400628,0x400644)`.

For a later return check, keep S, T, and S+8 on paper, close the worked
trace, and explain which becomes Q for each flag. Then draw the row
**after** RET. If you leave Q on R, revisit that one transition before
adding another layer. These checked derivations are not evidence of a
reader's independent performance or a running-system test.

Next, [Decimal parser and REPL](18-decimal-parser-and-repl.md) connects
token results, dictionary lookup, and compiler dispatch in the remaining
seed bodies.
