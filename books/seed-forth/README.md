# Seed and Forth

A small machine is easier to inspect when you know what question to ask of
each piece. This book begins with questions you can answer from visible state:
what is on the stack, which address is being written, and why does a sequence
of primitive operations produce subtraction?

The paper route is complete as a first draft: nineteen teaching chapters,
ninety-five exercises with separate feedback, six mixed return checks and a
[compact reference](REFERENCE.md). The new examples have not been executed,
and the route still needs fresh-reader and presentation checks.

## Before the first unit

- [Start here](chapters/00-start-here.md): choose a route and establish the
  evidence boundary
- [Why inspect a seed?](chapters/00-why-inspect-a-seed.md): identify the
  question this small system can answer, and the claims it cannot establish

## Unit one: values, memory, and bits

1. [Values and words](chapters/01-values-and-words.md): predict what a short
   Forth program does
2. [Addresses and bytes](chapters/02-addresses-and-bytes.md): explain a byte
   writer without confusing its cursor with the address of its cursor
3. [Bits and subtraction](chapters/03-bits-and-subtraction.md): derive useful
   operations from `nand` and addition

## Unit two: growing the library

4. [Return stack and shuffles](chapters/04-return-stack-and-shuffles.md):
   borrow temporary storage without losing a return destination
5. [Comparisons and characters](chapters/05-comparisons-and-characters.md):
   test values while respecting width, signedness and the selected byte ranges
6. [Memory updates and writers](chapters/06-memory-updates-and-writers.md):
   update a cell and emit precisely the intended low-order bytes

## Unit three: I/O, compilation, and persistent data

7. [Linux I/O contracts](chapters/07-linux-io-contracts.md): follow one raw
   system call and account for partial progress and errors
8. [Defining words and phases](chapters/08-defining-words-and-phases.md):
   separate making a defining word, creating a word, and executing the result
9. [Control flow by patching](chapters/09-control-flow-by-patching.md):
   build forward and backward branches while keeping two times distinct
10. [Storage, deferred words, and bytes](chapters/10-storage-deferred-words-and-bytes.md):
    give data a lifetime, bind behavior through a cell, and compare byte sequences

## Unit four: opening the machine code

11. [Executable and entry](chapters/11-executable-and-entry.md): connect every
    header/startup byte to the loaded process and its initial state
12. [Physical stacks and memory](chapters/12-physical-stacks-and-memory.md):
    relate the logical stack to cached registers, memory and return addresses
13. [Arithmetic instruction bytes](chapters/13-arithmetic-in-instruction-bytes.md):
    audit the arithmetic contracts down to register widths and instruction bytes

The [byte audit ledger](AUDIT.md) accounts for all 1,772 source bytes and
assigns every region to its audited chapter. The
[fourth return check](practice/return-check-4.md) connects mapping, physical
storage, register-width mistakes and arithmetic information loss.

## Unit five: I/O, names, and the native compiler

14. [Physical I/O and exit](chapters/14-physical-io-and-exit.md): audit the
    handoff between cached Forth state and Linux registers, including failure cases
15. [Dictionary and token input](chapters/15-dictionary-and-token-input.md):
    reconstruct all headers and follow lookup, borrowed input and error handling
16. [The native colon compiler](chapters/16-native-colon-compiler.md): trace
    definition construction, emitted calls and the two halves of a literal

The [fifth return check](practice/return-check-5.md) revisits stale input,
early-bound calls, compiler-stack preservation and token-boundary failures.

## Unit six: closing the seed audit

17. [Inline branch operands](chapters/17-inline-branch-operands.md): follow
    target cells and return-address ownership through both branch paths
18. [Decimal parser and REPL](chapters/18-decimal-parser-and-repl.md): trace
    number conversion, phase selection and the outer interpreter loop
19. [Audit synthesis and capstone](chapters/19-audit-synthesis-and-capstone.md):
    derive a complete new entry from input token to predicted machine bytes

The [sixth return check](practice/return-check-6.md) combines branch ownership,
numeric-token rules, dictionary layout and the limits of an evidence claim.
The [reference](REFERENCE.md) collects all thirty-two primitive contracts,
address conventions, library navigation and recovery routes.

## Practice and scope

Each chapter links to its own hints and worked solutions. The
[return check](practice/return-check.md) mixes the three topics so that the
chapter title no longer chooses the method for you.

A [second return check](practice/return-check-2.md) mixes the newer mechanisms
with the first unit's contracts.

The [third return check](practice/return-check-3.md) mixes I/O progress,
compiled identity, patch locations, and borrowed-buffer lifetime.

The library-level arc, complete machine-code audit and integrated capstone
are drafted. Executable practice, a tested fresh-reader setup and reader
validation remain outstanding. The
[learning path](../LEARNING-PATH.md) and [coverage map](../COVERAGE.md) show the
remaining work. All implementation claims refer to the
[pinned edition](../EDITION.md).
