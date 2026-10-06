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

## Interfaces opened later

| Interface usable now | Promise the first unit permits | Mechanism deliberately deferred |
|---|---|---|
| `: name ... ;` | Define a word from the stated sequence, using the explicit literal syntax | Dictionary headers, immediate words, compiling calls and inline literals |
| A data stack | Words consume and produce the documented topmost cells | Cached top-of-stack register and stack-memory layout |
| `@ ! c@ c!` | Access the stated valid memory location with the stated width | Address translation, mappings and machine instruction encodings |
| `here` / `latest` | Their distinct value/address contracts at this pinned seed | Startup, executable layout and the complete sysvar map |

These interfaces reduce prerequisites without hiding a proof obligation. The
first unit asks what follows if the contracts hold; the later audit asks how
the source realizes them. Source links are available now for readers who want
that second question early, but exercises do not require solving it early.

## What the next units must earn

1. Return-stack discipline, shufflers, comparisons and I/O contracts, with
   unsigned/signed limits and a clear error boundary
2. Byte/cell writers, dictionary/definition phases, immediacy and control-flow
   patching, followed by a library-level capstone
3. An x86-64 instruction-reading primer, then an invariant-led audit of the
   ELF, stack primitives, token reader, dictionary, compiler and REPL
4. A compiler-volume bridge that introduces C syntax, buffer ownership,
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
