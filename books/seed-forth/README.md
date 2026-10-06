# Seed and Forth

A small machine is easier to inspect when you know what question to ask of
each piece. This book begins with questions you can answer from visible state:
what is on the stack, which address is being written, and why does a sequence
of primitive operations produce subtraction?

## First learning unit

0. [Start here](chapters/00-start-here.md): choose a route and establish the
   evidence boundary
1. [Values and words](chapters/01-values-and-words.md): predict what a short
   Forth program does
2. [Addresses and bytes](chapters/02-addresses-and-bytes.md): explain a byte
   writer without confusing its cursor with the address of its cursor
3. [Bits and subtraction](chapters/03-bits-and-subtraction.md): derive useful
   operations from `nand` and addition

Each chapter links to its own hints and worked solutions. The
[return check](practice/return-check.md) mixes the three topics so that the
chapter title no longer chooses the method for you.

This is the first drafted unit of a longer book. It is not yet a complete
library course or the promised machine-code audit. The
[learning path](../LEARNING-PATH.md) and [coverage map](../COVERAGE.md) show the
remaining work. All implementation claims refer to the
[pinned edition](../EDITION.md).
