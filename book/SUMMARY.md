# Summary

[Seed Forth](README.md)

# Before you begin

[Where this fits in the bootstrap ecosystem](where-this-fits.md)
[Prologue: Two thousand and forty bytes](00-prologue.md)

# Part I — Forth from the lib up

- [Stacks and words](01-stacks-and-words.md)
- [Code emission and the HERE pointer](02-code-emission-and-here.md)
- [Logic from one primitive](03-logic-from-nand.md)
- [The return stack: `over` and subtract](04-return-stack-over-subtract.md)
- [Talking to Linux: syscall6 wrappers](05-syscalls.md)
- [Character classification](06-character-classification.md)
- [Comparisons from unsigned division](07-comparisons-from-division.md)
- [Stack shufflers](08-stack-shufflers.md)
- [Memory updates and cell writers](09-memory-and-cell-writers.md)
- [Immediacy and constants](10-immediacy-and-constants.md)
- [Control-flow combinators](11-control-flow-combinators.md)
- [`allot`, `create`, `variable`, `bytes-eq`](12-defining-words-and-bytes-eq.md)

# Part II — The seed VM

- [The ELF and the entry point](13-elf-and-entry.md)
- [Stack primitives in machine code](14-stack-primitives.md)
- [Arithmetic, logic, comparison](15-arithmetic-and-logic.md)
- [I/O: `emit`, `key`, `syscall6`](16-io-emit-key-syscall6.md)
- [The dictionary](17-the-dictionary.md)
- [The colon compiler](18-the-colon-compiler.md)
- [Branches and inline cells](19-branches-and-inline-cells.md)
- [The number parser and REPL](20-number-parser-and-repl.md)

# Part III — A C compiler in Forth

- [Arena and I/O buffers](21-arena-and-io-buffers.md)
- [The preprocessor](22-the-preprocessor.md)
- [The lexer](23-the-lexer.md)
- [Types and symbols](24-types-and-symbols.md)
- [ELF emission and codegen, part 1](25-elf-and-codegen-part-1.md)
- [Codegen, part 2: calls and locals](26-codegen-part-2.md)
- [Expressions, part 1: precedence climbing](27-expressions-part-1.md)
- [Expressions, part 2: assignment, postfix, struct access](28-expressions-part-2.md)
- [Declarations: types and globals](29-declarations-types-globals.md)
- [Statements: if, while, for, return](30-statements-if-while-for-return.md)
- [Functions: parameters, locals, scope](31-functions-and-scope.md)
- [End to end: main and the bootstrap chain](32-main-and-bootstrap-chain.md)

# Appendices

- [A — The 32 seed primitives](A1-32-seed-primitives.md)
- [B — The memory map](A2-memory-map.md)
- [C — Reproducibility: the full hex0 → seed → M2-Planet chain](A3-reproducibility-chain.md)
- [D — Three worked exercises, one per Part](A4-worked-exercises.md)
- [E — Further reading](A5-further-reading.md)
- [F — The C subset](A6-c-subset.md)
- [G — Compiler exit codes](A7-error-codes.md)

# Reference

- [Glossary](GLOSSARY.md)
- [Concept index and dependency graph](CONCEPTS.md)
