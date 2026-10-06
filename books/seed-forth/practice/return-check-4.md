# Return check after the first machine-code audit

These tasks connect [the executable layout](../chapters/11-executable-and-entry.md),
[physical stack storage](../chapters/12-physical-stacks-and-memory.md), and
[arithmetic instructions](../chapters/13-arithmetic-in-instruction-bytes.md).
They are derived-state questions, not commands to run a modified seed.
Use the source and instruction reference when needed; close the worked
answers for an independent attempt.

## R4-01 Moving one address is not relocating the system

The pinned image maps file offset zero at virtual address `0x400000`, and its
entry address is `0x400078`. In a paper counterfactual, someone changes only
the segment's virtual address to `0x500000`. Where would file offset `0x78`
be mapped under that altered mapping? Does the unchanged entry field select
that location? Even if the entry field were corrected, why would that alone
not establish a working relocated seed?

## R4-02 A discarded slot still has bytes

After two valid literal pushes, the logical data stack is `[7,3]`.
`rdi=3`, `rbp=0x410FF0`, the cell at `0x410FF0` holds 7, and the saved startup
dummy at `0x410FF8` holds zero. Trace `dup +`, observing state after each
primitive returns. Give the final logical stack, `rdi`, `rbp`, and the cell
at `0x410FE8`. Does the continued presence of bytes in that lower-addressed
slot make them a third logical stack item?

## R4-03 Choose a test that exposes the missing instruction

The actual `0=` sequence uses TEST, SETE into `dil`, zero-extension from `dil`
into `rdi`, and NEG. Why does input 256 expose an omitted zero-extension?
Separately, if the REX byte were omitted only from SETE, why is input zero a
useful counterexample? Do not assume that every broken encoding fails on
every input.

## R4-04 An inverse calculation loses information

Let `H=2^63`. Start with the unsigned cell value `H+1`, multiply by two with
the seed's `*`, then divide the result by two with its unsigned `/`. What
comes back? Why does agreement of signed and unsigned **low halves** for
multiplication not justify undoing every multiplication with division?

## Hints

- R4-01: Separate the mapping formula, the entry field, and absolute values
  embedded in instructions and dictionary links
- R4-02: `dup` subtracts eight from `rbp` and stores the old cached top;
  `+` consumes that saved operand and adds eight back
- R4-03: SETE writes one byte. Without REX, the same legacy byte-register
  field names `bh`, not `dil`
- R4-04: Calculate the full product first, then discard the multiple of
  `2^64` before applying division

## Answers and changed checks

### R4-01 answer

The byte would be mapped at `0x500078`. The unchanged entry address
`0x400078` is different and does not point into the specified relocated load
region. Adjusting the entry would still leave other absolute addresses in
the seed unchanged, including dictionary links, fixed system-variable
accesses and startup values. A working relocation needs an account of every
address dependency and loader requirement, not one successful addition.

For a changed check, keep the original mapping and locate file offset
`0x699`. Its mapped address is `0x400699`, the REPL destination selected by
the startup jump. File offsets and virtual addresses remain distinct units.

### R4-02 answer

After `dup`, `rbp=0x410FE8`; the cell there contains 3; `rdi` remains 3.
The logical stack is `[7,3,3]`. After `+`, `rdi=6` and `rbp=0x410FF0`, so
the logical stack is `[7,6]`. The cell at `0x410FE8` still contains 3.
It lies outside the current deeper-stack region; moving the pointer did not
erase its bytes, but it is no longer a live logical item.

For a changed check, apply `drop` now. It loads 7 into `rdi`, advances `rbp`
to `0x410FF8`, and leaves logical stack `[7]`. The zero stored at that address
is the saved dummy, not an extra logical zero beneath seven.

### R4-03 answer

For input 256, TEST finds a nonzero cell, and SETE writes zero into `dil`.
The higher bits of `rdi` still contain the `0x100` pattern. The real MOVZX
reduces the whole register to zero, then NEG leaves zero. Without MOVZX,
NEG would produce `2^64-256`, a nonzero, noncanonical false result.

Without SETE's REX prefix, the write goes to `bh`. With input zero, `dil`
stays zero instead of becoming one. The following actual MOVZX and NEG then
produce zero, although `0=` should return all ones. A nonzero case whose
low byte already happens to be zero can conceal that particular error.

For a changed check, use input one when omitting MOVZX but retaining the
correct SETE destination. SETE clears the only set byte, so the result can
happen to be correct. That one case cannot validate omission of the clear.

### R4-04 answer

The full product is `2^64+2`. Keeping its low 64 bits yields 2; unsigned
division by two yields 1. The original `H+1` is not recovered. The discarded
high bit carried information that no later division can reconstruct from
the low cell alone.

For a changed check, start with seven: multiplication gives fourteen and
division returns seven because no high-order information was discarded.
State the range needed for that reasoning instead of generalizing from the
small successful example.

## What to revisit

A mapping error needs an offset/address distinction. A stack-depth error
needs the live-region invariant. A predicate error needs the width of each
register write. An arithmetic reversal error needs the full result and the
truncation step. Use the relevant chapter, then make a changed attempt.
These checks assess particular explanations under stated conditions; they
do not certify execution, security or general machine-code expertise.
