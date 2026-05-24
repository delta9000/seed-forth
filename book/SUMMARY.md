# Summary

[Seed Forth](README.md)

# Before you begin

[Where this fits in the bootstrap ecosystem](where-this-fits.md)
[Prologue: Two thousand and forty bytes](00-prologue.md)

# Part I — Forth from the lib up

- [Stacks and words](01-stacks-and-words.md) — the data stack, dictionary lookup, stack-effect notation
- [Code emission and the HERE pointer](02-code-emission-and-here.md) — `c,`, `,4`, `,8`, the bump cursor every defining word reaches for
- [Logic from one primitive](03-logic-from-nand.md) — `and`, `or`, `not`, `xor` built from `nand`
- [The return stack: `over` and subtract](04-return-stack-over-subtract.md) — `>r`, `r>`, `r@`, and two's-complement subtraction
- [Talking to Linux: syscall6 wrappers](05-syscalls.md) — `open`, `read`, `write`, `close`, `die`
- [Character classification](06-character-classification.md) — `digit?`, `alpha?`, `space?` via the range-check trick
- [Comparisons from unsigned division](07-comparisons-from-division.md) — `=`, `<>`, `<`, `>`, `<=`, `>=`
- [Stack shufflers](08-stack-shufflers.md) — `nip`, `rot`, `2dup`, `2drop`
- [Memory updates and cell writers](09-memory-and-cell-writers.md) — `+!`, `-!`, `,4`, `,8`, the little-endian writers
- [Immediacy and constants](10-immediacy-and-constants.md) — IMMEDIATE flag, STATE, `constant`
- [Control-flow combinators](11-control-flow-combinators.md) — `if,`, `then,`, `begin,`, `while,`, `repeat,` from `branch`/`0branch`
- [`allot`, `create`, `variable`, `bytes-eq`](12-defining-words-and-bytes-eq.md) — the defining-word family closes; bytes-eq joins as a compiler primitive

# Part II — The seed VM

- [The ELF and the entry point](13-elf-and-entry.md) — the 120-byte preamble that boots the seed
- [Stack primitives in machine code](14-stack-primitives.md) — `dup`, `drop`, `swap`, `over`, `>r`, `r>`, `r@`, `@`, `!`
- [Arithmetic, logic, comparison](15-arithmetic-and-logic.md) — `+`, `nand`, `0=`, `/`, `*`
- [I/O: `emit`, `key`, `syscall6`](16-io-emit-key-syscall6.md) — three primitives, the only Linux contact in the seed
- [The dictionary](17-the-dictionary.md) — `find`, `'`, `execute`, header layout, linear-search lookup
- [The colon compiler](18-the-colon-compiler.md) — `:`, `;`, `[lit]`, `lit_code`, subroutine threading
- [Branches and inline cells](19-branches-and-inline-cells.md) — `branch`, `0branch`, the consumed-slot property
- [The number parser and REPL](20-number-parser-and-repl.md) — `read_word`, decimal parse, the interpret-vs-compile loop, the bridge to Part III

# Part III — A C compiler in Forth

- [Arena and I/O buffers](21-arena-and-io-buffers.md) — the compiler's deterministic memory model
- [The preprocessor](22-the-preprocessor.md) — flatten C source, expand integer macros
- [The lexer](23-the-lexer.md) — one token at a time in the `tok-*` globals
- [Types and symbols](24-types-and-symbols.md) — one-word types, parallel-column symbols, struct descriptors
- [ELF emission and codegen, part 1](25-elf-and-codegen-part-1.md) — write executable bytes: ELF prologue + instruction encoders
- [Codegen, part 2: calls and locals](26-codegen-part-2.md) — calls, libc shims, string literals, global-address fixups
- [Expressions, part 1: precedence climbing](27-expressions-part-1.md) — binary expressions through one repeated five-step fold
- [Expressions, part 2: assignment, postfix, struct access](28-expressions-part-2.md) — primary, unary, postfix, ternary, assignment with lvalue tracking
- [Declarations: types and globals](29-declarations-types-globals.md) — base types, pointers, arrays, structs, typedefs, file-scope globals
- [Statements: if, while, for, return](30-statements-if-while-for-return.md) — every C control structure through emit/remember/patch
- [Functions: parameters, locals, scope](31-functions-and-scope.md) — translation units, scopes, the entry stub at `0x400078`
- [End to end: main and the bootstrap chain](32-main-and-bootstrap-chain.md) — the Stage-A byte-identity proof closes the chain

# Appendices

- [A — The 32 seed primitives](A1-32-seed-primitives.md) — one-row table per primitive (name, opcode, stack effect, source location)
- [B — The memory map](A2-memory-map.md) — every address the seed and the compiler reach for
- [C — Reproducibility: the full hex0 → seed → M2-Planet chain](A3-reproducibility-chain.md) — pinned commits + reproducible-build recipe
- [D — Three worked exercises, one per Part](A4-worked-exercises.md) — extended walk-throughs that touch source
- [E — Further reading](A5-further-reading.md) — JONESFORTH, sectorforth, M2-Planet, Mes, stage0, plus surveys
- [F — The C subset](A6-c-subset.md) — exactly which C features the compiler handles (and which it deliberately doesn't)
- [G — Compiler exit codes](A7-error-codes.md) — every `die N` in the compiler, what triggers it, where to look

# Reference

- [Glossary](GLOSSARY.md) — quick definitions for every term in the book
- [Concept index and dependency graph](CONCEPTS.md) — rung map, capability ladder, topic→chapter quick reference, reading orders
