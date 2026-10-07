# 0. Why inspect a seed?

A program has one value, 7, waiting to be used. It performs two operations:
copy that value, then add the two values now available. Before reading any
machine code, predict the result. Is it 7, 14, or 49?

The intermediate state settles the question. Copying produces two sevens;
adding consumes both and leaves 14. In the language of this book, the two
operations are named `dup` and `+`. A **stack** holds their values in order,
with the next value to use at the top. Our drawings put that top at the right:

```text
Starting stack       [7]
After dup            [7, 7]
After +              [14]
```

This is a prediction from the operations' contracts, not output captured
from a running program. It already gives us a useful inspection method:
write the state before an operation, explain what changes, and check the
state afterward. If the answer were 49, we would need a multiplication
operation somewhere. A plausible-looking name or a confident explanation
could not supply the missing step.

Now ask a harder version of the same question. Which machine instructions
make the copy? Where is each seven stored? How does execution reach the
addition and then return? Seed Forth is small enough for this volume to
follow those questions from a language-level contract to the bytes that
implement it.

## Small enough to ask about every part

The starting object is the annotated
[`000-seed.hex0`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0)
in `delta9000/seed-forth`, pinned to revision
`bbcc1732152af2d884737272eed870d2410ffe8e`. Its hexadecimal byte pairs
describe a **1,772-byte executable** for Linux on x86-64. The comments and
annotations are reading material; they are not additional executable bytes.
The executable begins with file headers and startup instructions, then
provides 32 named primitive operations and a few supporting routines.

“Primitive” means that this seed supplies the operation directly in machine
code. It does not mean that the operation is indivisible inside the
processor, or that 32 is a universal minimum. Above this chosen starting
vocabulary,
[`010-lib.fth`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/010-lib.fth)
defines more operations in Forth itself. Those definitions include
subtraction, useful stack rearrangements, byte writers, named storage, and
conditional and looping control flow.

The small size makes a particular task practical: keep an account of every
file region while relating each one to a purpose. The
[byte audit ledger](../AUDIT.md) supplies that account. It prevents a
discussion of the interesting instructions from quietly omitting the
headers, input handling, or failure paths. Accounting for a byte is the
beginning of an explanation, however, not a certificate that the byte is
right for every possible use.

The machine also depends on things outside those 1,772 bytes. Linux loads
the executable and provides input, output, memory, and process exit. The
processor supplies x86-64 instruction behavior. The seed assumes usable
memory and correctly formed calls. Its smallness brings these dependencies
into view; it does not remove them.

## One mechanism can lead to another

Consider a second, slightly larger question. A byte writer stores a value
at a cursor and advances the cursor by one byte. Where should its next call
write? At the following address, provided the first call updated the cursor
rather than some unrelated memory cell.

There are two locations to distinguish: the place to receive the byte, and
the place holding the cursor's current value. Chapter 2 makes this concrete
using the library word `c,`. Its name ends with a comma. It writes one byte,
then updates the stored cursor. Confusing the cursor with the address of its
storage cell would change what memory is overwritten. The distinction is
small enough to draw and important enough to keep using throughout the book.

Later, the same writer helps put instruction bytes into memory. A sequence
can therefore do more than calculate a value: it can construct another
sequence that will calculate a value later. This requires careful separation
of two times. Writing the byte for a return instruction does not return
from the writer; executing that byte later does.

That is the connection behind the library's control-flow words. They emit
calls and leave spaces for destinations, then fill those spaces when the
destinations become known. There is no need to accept that whole mechanism
on this page. First learn what a byte store changes. Then learn how a call
finds its destination. The later explanation joins those already visible
pieces.

This order is deliberate. The source files must arrange definitions so that
their dependencies already exist when loaded. A reader has a different
dependency order. We begin with values and operations, add memory and
ownership, then open the underlying instructions. The
[learning path](../../LEARNING-PATH.md) records where each interface is
introduced and where its implementation is examined.

## What this volume asks you to finish

The boundary of *Seed and Forth* is the seed and its first library. Its
library chapters develop the contracts needed to follow all the definitions
in `010-lib.fth`. Its machine-code chapters inspect the executable headers,
startup, physical stacks, primitive bodies, dictionary, token reader,
definition compiler, branches, decimal parser, and interpreter loop.

The [closing capstone](19-audit-synthesis-and-capstone.md) connects a small
Forth definition across these layers: describe its input and output, account for its generated bytes,
follow its control flow, and identify the storage and call assumptions that
make the trace valid. Explaining one layer while losing a value or a return
destination in another is an unfinished account.

You need ordinary arithmetic and the ability to follow a short sequence of
steps. Forth, assembly, addresses, and compiler construction are introduced
before the main exercises require them. If you already know a mechanism,
use the chapter's route check or independent problem to decide where to
spend your attention. The [compact reference](../REFERENCE.md) keeps the
edition's contracts close at hand; remembering a file name is not the point
of a stack exercise.

This is also a source-reading volume, not a fresh installation tutorial.
Paper traces require no Linux machine. Executing this seed requires the
stated Linux/x86-64 environment and its loading assumptions. The pinned
[`build.sh`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/build.sh)
is the repository's build entry: it invokes a hex0 assembler, normally the
vendored stage0-posix seed, to translate the annotated source. Linking that
script does not mean its setup or this volume's examples were exercised
while preparing these pages. The [edition record](../../EDITION.md) and
[validation record](../../VALIDATION.md) separate the available evidence.

## Authorship is part of the record

The original project's
[prologue](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/book/00-prologue.md)
discloses that most of its code was written by AI. The seed source credits
an ensemble of Claude, Gemini, Codex, DeepSeek, Qwen, Kimi, Gemma, and
MiniMax under human architectural direction, and identifies the license
as MIT. Those are public provenance statements from the source, preserved
here rather than replaced by an invented account of a programmer's
experience.

That provenance neither establishes correctness nor makes inspection
pointless. A human-written comment and a model-written comment both need
to match the instructions they describe. The original work's interest in
human-readable explanation and reproducible artifacts remains relevant,
but each kind of evidence answers a different question:

- **Source inspection:** do these bytes and definitions support this stated
  mechanism under the named assumptions?
- **Execution:** what did this exact program do with this input in this
  recorded environment?
- **Artifact equality:** did the selected outputs of these specified builds
  match under the stated comparison?
- **Semantic correctness:** does the implementation satisfy the intended
  behavior over the domain being claimed?
- **Security:** what harmful behavior is possible under a stated threat
  model, including the components and inputs outside the inspected code?

A byte-for-byte match is a precise observation about selected artifacts.
It does not, by itself, answer the last two questions. Likewise, a correct
hand trace is not an execution report, and a small executable is not a
safe interpreter for arbitrary input. Several seed operations omit checks
for stack depth, address validity, or space exhaustion. Naming those limits
is part of understanding the mechanism.

## Where the longer route goes

The planned compiler volume takes the next representational step: from
source-language text through compiler data structures to generated code.
The planned toolchain volume follows selected build stages, their inputs,
and the comparisons made between their outputs. A later kernel volume
needs its own account of loading, entry, initialization, and observable
system behavior. These are separate teaching and verification tasks, not
extra conclusions hidden inside an explanation of `dup`.

The current direct-GCC work has its own source-pinned reported results,
summarized in the edition record. This volume does not establish a proved
direct-GCC-to-Linux chain, repeat those builds, or import a result from a
different lineage as evidence for this one. Its useful contribution is
more local: expose how the starting language reads, stores, compiles, and
runs its own definitions.

Begin with [Start here](00-start-here.md) to choose a route. Keep the first
question small enough to answer: after this operation, what changed, and
why? There will be time to open the next layer once that answer has a
concrete state behind it.
