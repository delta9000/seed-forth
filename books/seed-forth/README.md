# Seed and Forth

A small machine is easier to inspect when you know what question to ask of
each piece. This book begins with questions you can answer from visible state:
what is on the stack, which address is being written, and why does a sequence
of primitive operations produce subtraction?

## Unit one: values, memory, and bits

0. [Start here](chapters/00-start-here.md): choose a route and establish the
   evidence boundary
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

Each chapter links to its own hints and worked solutions. The
[return check](practice/return-check.md) mixes the three topics so that the
chapter title no longer chooses the method for you.

A [second return check](practice/return-check-2.md) mixes the newer mechanisms
with the first unit's contracts.

These are the first two drafted units of a longer book. It is not yet a complete
library course or the promised machine-code audit. The
[learning path](../LEARNING-PATH.md) and [coverage map](../COVERAGE.md) show the
remaining work. All implementation claims refer to the
[pinned edition](../EDITION.md).
