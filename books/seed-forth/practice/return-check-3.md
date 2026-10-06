# Return check after the library capstone

These tasks mix [I/O](../chapters/07-linux-io-contracts.md),
[definition phases](../chapters/08-defining-words-and-phases.md),
[control-flow patching](../chapters/09-control-flow-by-patching.md), and
[stored data and deferred words](../chapters/10-storage-deferred-words-and-bytes.md).
They are paper derivations under the same pinned profile. Keep reference
contracts available; try the reasoning before opening the answers when useful.

## R3-01 The call stays put while its result changes

Suppose a deferred word named `hook` is defined, then a normal word `use-hook`
is compiled to call it. `hook` is bound to a word that pushes 5. Later it is
rebound to a word that pushes 6. Assuming valid execution tokens and the
ordinary one-cell result contracts, what do the two calls to `use-hook`
produce? Which stored item changes, and which previously compiled call target
does not need to change? Explain why executing `hook` before any binding is
not covered by the successful-call contract.

## R3-02 A successful call did not finish the request

A program intends to write three bytes beginning at a valid buffer address
5000 to descriptor 1. Its first raw `write` returns 1. What buffer address and
count should a continuation use to request the remaining bytes? Does success
of that first call establish delivery of all three? What must a completion
procedure do if a later nonempty request returns zero instead of progress?
No Forth loop implementation is required; give a state transition and a
termination/error policy.

## R3-03 Patch storage and jump destination

In a hypothetical valid code region, an `if,` begins emitting at address
2000. It emits a five-byte CALL and an eight-byte target slot. The conditional
body is one compiled literal, `[lit] 7`, which occupies thirteen bytes.
`then,` is reached immediately afterward.

Where is the slot? What value is written into it? Does `then,` itself append
another instruction? Trace the two runtime cases starting with `[99, 0]`
and `[99, U]`, where U is the all-ones cell. These are two separate runs of
the generated conditional, not the compile-time stack.

## R3-04 A borrowed buffer changes before its consumer runs

Assume `token` and `bytes,` are loaded and HERE names a valid disjoint payload
region. Consider this top-level input as a source-reading exercise:

```forth
token hello bytes,
```

`token` returns the TIB address and length of `hello`. Before `bytes,` can run,
the outer interpreter reads the next word's name into that same TIB. What
five-byte prefix does `bytes,` therefore copy under the inspected reader
contract? Why does the already-defined `s,` word avoid that particular gap
between token production and consumption?

## Hints

- R3-01: Separate the address of the deferred word's code from the execution
  token stored in its dispatch cell
- R3-02: The syscall reports the number of bytes written by that call, not
  the caller's intended total
- R3-03: Track the emitted cursor and the retained fixup address in different
  columns. The runtime flag is not a compile-time fixup
- R3-04: A pointer and a length do not preserve the bytes they refer to;
  compare the input-reading steps in the two routes

## Answers and changed checks

### R3-01 answer

The first call leaves 5 and the second leaves 6, with any older logical data
stack prefix preserved. `is` changes the execution token in `hook`'s dispatch
cell. `use-hook` continues to call the same deferred-word code; that code reads
the current token and executes it each time. The added indirection is what
makes rebinding visible to already compiled callers.

The initial dispatch cell is zero. Zero has not been established as a valid
call target. The implementation does not turn an unbound call into a safe
placeholder result, so the successful trace's precondition is missing.
For a changed check, compare an ordinary call compiled directly to the old
5-producing word: changing a separately named dispatch cell would not retarget
that direct call.

### R3-02 answer

Advance to address 5001 and reduce the count to 2. The first call establishes
one byte of progress, not three. A continuation needs a separate contract for
errors, interruption, zero progress and the destination's behavior. One
defensible bounded policy stops and reports failure on zero progress for a
nonempty request, rather than spinning forever. Another policy needs an
explicit waiting/retry condition; unconditional repetition is not an answer.

For a changed check, let the first result be 2. The next request begins at
5002 with count 1. A negative raw result is an error case, not a huge positive
amount to add to the buffer address.

### R3-03 answer

The slot begins at 2005. The cursor after `if,` is 2013; after the thirteen-byte
literal it is 2026. `then,` writes 2026 into the existing eight-byte slot at
2005 and appends no bytes.

At runtime, `0branch` consumes the flag in either case. From `[99,0]` it jumps
to 2026 and leaves `[99]`, skipping the literal. From `[99,U]` it resumes after
the slot at 2013; the literal pushes 7, giving `[99,7]`, and execution reaches
2026 normally. The inline slot is skipped or used, never executed as code or
left behind as a return-stack value after the branch completes.

For a changed check, make the body a single five-byte ordinary call. The
patch value becomes 2018, but the slot address stays 2005. Body size changes
the destination; it does not relocate the already emitted slot.

### R3-04 answer

The outer reader has overwritten the start of the TIB with the token
`bytes,`. The retained length is still five, so the copied prefix is `bytes`,
not `hello`. Neither retaining the address nor retaining the length granted
ownership of a stable snapshot.

`s,` calls `token` and then `bytes,` as operations already compiled into one
word. After `token` reads the payload token, no outer-loop name lookup occurs
between that producer and consumer. The bytes are copied into the stated
owned payload region while the borrowed buffer still contains them. Other
overlap, capacity and valid-input preconditions still apply.

For a changed check, give `s,` the next token `world`: the intended five-byte
copy is `world`. Explain why adding more stack shuffles to the top-level
sequence would not freeze its original TIB contents.

## Use the result

If one answer surprised you, name which lifetime or phase you merged:
compiled target versus dispatch cell, requested work versus one syscall,
compile-time slot versus runtime flag, or borrowed address versus owned bytes.
Then trace a changed example with those states shown separately. A correct
immediate answer is useful evidence about that attempt, not proof of retained
knowledge or automatic transfer to the later compiler volume.
