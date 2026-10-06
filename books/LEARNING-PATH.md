# Learning path

## Reader and purpose

The starting reader can perform ordinary integer arithmetic and follow a short
program one step at a time. No Forth, assembly, operating-system or compiler
knowledge is assumed. Programming experience is helpful but does not stand in
for knowledge of stack notation or addresses.

The first unit has a concrete outcome: explain how a small vocabulary can
transform values and write bytes, while keeping the data stack and memory
state straight. Later units will reuse those capabilities to explain the
library, its control-flow words and finally the machine code that implements
the seed.

## First-unit dependency graph

Read each arrow as “needed before,” not “executes before.”

```text
ordinary integer arithmetic
  -> S1: cell values, top-right stack notation, explicit literals
       -> S1: word contracts, left-to-right execution, composition
            -> S2: address/value distinction, byte/cell access
                 -> S2: cursor indirection and the c, invariant
            -> S3: bit patterns, nand and boolean masks
                 -> S3: modular negation and operand-ordered subtraction
```

S2 precedes S3 in the reading route because it gives a tangible use for the
stack model and a break from pure arithmetic. S3 needs S1, not an unmentioned
memory trick. This is a conceptual graph; the source begins with `here-addr`
and `c,` for library load-order reasons.

| Unit | Observable outcome | Assumed or taught first | Practice and feedback |
|---|---|---|---|
| [Start here](seed-forth/chapters/00-start-here.md) | Pick a route and tell a predicted state from an observed run | Ordinary arithmetic; no tool installation | Three route questions and recoverable starting point |
| [S1 Values and words](seed-forth/chapters/01-values-and-words.md) | Trace a defined word and diagnose operand-order or stack-depth errors | Cells and notation taught in S1 | S1 exercises, [feedback](seed-forth/practice/01-solutions.md) |
| [S2 Addresses and bytes](seed-forth/chapters/02-addresses-and-bytes.md) | Trace `c,` across the stack, memory and HERE cell | S1 stack operations; addresses and byte order taught before use | S2 exercises, [feedback](seed-forth/practice/02-solutions.md) |
| [S3 Bits and subtraction](seed-forth/chapters/03-bits-and-subtraction.md) | Derive `and`, `or` and subtraction; distinguish truth from a mask | S1 composition; binary and wraparound refreshed locally | S3 exercises, [feedback](seed-forth/practice/03-solutions.md) |
| [Return check](seed-forth/practice/return-check.md) | Select and apply the right contract after intervening material | S1–S3 | Mixed prompts with separate answer section |


## Second-unit dependency graph

```text
S1 + S3 -> S4: two stacks, balanced borrowing, reusable shuffles
S3 + S4 -> S5: comparisons and character classes, including space?
S2 + S3 + S4 -> S6: read-modify-write helpers and multi-byte writers
```

The XOR extension in S4 uses S3's bit operations; it is not a hidden new
prerequisite. The character-class combinations in S5 use `over`, so the
shuffle mechanism must precede them even though some simpler predicates do
not need it. S6's exact byte-width work builds on S2 rather than reopening
addresses without warning.

| Unit | Observable outcome | Practice and feedback |
|---|---|---|
| [S4 Return stack and shuffles](seed-forth/chapters/04-return-stack-and-shuffles.md) | Trace temporary borrowing, helper-call boundaries and reusable shuffles | S4 exercises, [feedback](seed-forth/practice/04-solutions.md) |
| [S5 Comparisons and characters](seed-forth/chapters/05-comparisons-and-characters.md) | Explain equality, bounded signed order and byte-range classification | S5 exercises, [feedback](seed-forth/practice/05-solutions.md) |
| [S6 Memory updates and writers](seed-forth/chapters/06-memory-updates-and-writers.md) | Trace a cell update and four/eight-byte emission with truncation limits | S6 exercises, [feedback](seed-forth/practice/06-solutions.md) |
| [Second return check](seed-forth/practice/return-check-2.md) | Select the right stack, comparison or memory contract without a chapter-specific cue | Four mixed prompts with separate answers |


## Library-completion dependency graph

```text
S2 + S3 + S4 + S5 -> S7: Linux I/O and raw error/progress contracts
S2 + S6 -> S8: local dictionary/ISA bridge and definition phases
S3 + S4 + S6 + S8 -> S9: immediate control flow and balanced early return
S2 + S4 + S5 + S6 + S8 + S9 -> S10: storage, deferred dispatch and byte sequences
```

S7 uses the sign-test contract from S5 to describe raw negative results and
S4's call-state distinction. S8 teaches the small dictionary and instruction
interfaces it needs locally; it does not require the later full byte audit.
S9 needs return-stack discipline before an early exit can be safe. S10 names
the increment/decrement helpers before its token and byte loops use them.

| Unit | Observable outcome | Practice and feedback |
|---|---|---|
| [S7 Linux I/O](seed-forth/chapters/07-linux-io-contracts.md) | Trace syscall arguments and distinguish a return value from complete requested work | S7 exercises, [feedback](seed-forth/practice/07-solutions.md) |
| [S8 Definition phases](seed-forth/chapters/08-defining-words-and-phases.md) | Explain a created word's layout and distinguish its three relevant times | S8 exercises, [feedback](seed-forth/practice/08-solutions.md) |
| [S9 Control-flow patching](seed-forth/chapters/09-control-flow-by-patching.md) | Trace emitted slots, fixups and runtime branch paths separately | S9 exercises, [feedback](seed-forth/practice/09-solutions.md) |
| [S10 Storage and byte sequences](seed-forth/chapters/10-storage-deferred-words-and-bytes.md) | Build a small library-level artifact while accounting for storage and binding lifetimes | S10 exercises, [feedback](seed-forth/practice/10-solutions.md) |
| [Third return check](seed-forth/practice/return-check-3.md) | Select the relevant phase, lifetime or progress contract without a chapter-specific cue | Four mixed questions with separate answers |

## Interfaces opened in stages

| Interface | Initial contract | Later explanation and remaining audit |
|---|---|---|
| `: name ... ;` | Define a word from the stated sequence, using the explicit literal syntax | S8 opens headers, immediacy and emitted calls; the full native compiler implementation is still deferred |
| A data stack | Words consume and produce the documented topmost cells | S4 separates data and return stacks; the full cached-top and instruction audit remains deferred |
| `@ ! c@ c!` | Access the stated valid memory location with the stated width | Address translation, mappings and machine instruction encodings |
| `here` / `latest` | Their distinct value/address contracts at this pinned seed | Startup, executable layout and the complete sysvar map |

These interfaces reduce prerequisites without hiding a proof obligation. The
first unit asks what follows if the contracts hold; later chapters open the
needed mechanisms in stages, and the full audit asks how every relevant
source instruction realizes them. Source links are available now for readers who want
that second question early, but exercises do not require solving it early.

## What the next units must earn

1. An x86-64 instruction-reading primer, then an invariant-led audit of the
   ELF, stack primitives, token reader, dictionary, compiler and REPL
2. A compiler-volume bridge that introduces C syntax, buffer ownership,
   representation changes and the chosen build profile before implementation
   detail

The [full coverage map](COVERAGE.md) allocates all original material beyond
this initial unit. A planned unit is not required reading that already exists.

## How to use practice

Try a prediction before opening feedback when that helps expose your current
model. If you cannot start, use the first hint or the worked example right
away. If the error is a missing convention, repair that convention before
adding a harder problem. If you can explain representative cases accurately,
skip redundant steps and try a changed boundary or the return check.

After feedback, use a changed input rather than immediately copying the same
answer. At a later session, return to a mixed problem without its solution
open. Those are opportunities to check independent performance and retention,
not claims that a fixed practice schedule guarantees either. Keep normal
navigation and reference aids available; this is not a test of memorizing file
names.
