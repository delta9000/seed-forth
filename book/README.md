# Forth From a 2040-Byte Seed

A tutorial book that teaches Forth by reading — and extending — the source
of this repository.

## Who this is for

You write code already.  You know what a stack is, what `malloc` does, and
roughly what an ELF executable is.  You have never written Forth (or you
tried once, found the `: ;` syntax baffling, and bounced off).

This book uses the seed-forth codebase as its single worked example.
Every word it teaches you is a word that actually appears in
`000-seed.hex0`, `010-lib.fth`, or one of the compiler layers.  No toy
"hello-world Forth" — by Chapter 10 you will have read, understood, and
modified an honest single-pass native compiler that fits in 2040 bytes.

## What you will be able to do at the end

- Read `000-seed.hex0` and explain, byte-for-byte, why each x86-64
  instruction is there.
- Write your own immediate words that emit machine code.
- Follow `100-cc-expr.fth` and add a new operator to the C compiler.
- Rebuild the whole bootstrap and verify the byte-identical M1 output
  against M2-Planet.

## How the book is organised

**Part I — Forth from the seed up.**  Teaches you Forth using only
`000-seed.hex0` and `010-lib.fth`.  Every chapter ends pointing at real
file:line locations you can `grep` or open.

**Part II — A C compiler in Forth.**  Walks the nine compiler layers
(`020-cc-arena.fth` through `120-cc-main.fth`) in load order, treating
each as a worked example of a Forth idiom you have already met.

**Appendices.**  Reference card for the 32 seed primitives, the memory
map, the bootstrap chain, and exercises.

## Table of contents

### Part I — Forth from the seed up

| # | Chapter | Source under discussion |
|---|---|---|
| 1 | [Stacks and words](01-stacks-and-words.md) | `010-lib.fth` lines 26–37, 125–135 |
| 2 | The seed vocabulary | `000-seed.hex0` primitives at 0x0D2..0x5FD |
| 3 | The dictionary | `000-seed.hex0` `find_code` + header layout |
| 4 | What `:` and `;` actually do | `000-seed.hex0` `colon_code`, `semicolon_code` |
| 5 | Numbers, literals, and `[lit]` | `000-seed.hex0` `parse_decimal_code`; why every constant in 010-lib is preceded by `[lit]` |
| 6 | The return stack | `>r r> r@`; `over` and `,4` reread in this light |
| 7 | Logic from `nand` alone | `010-lib.fth` lines 26–29, 71–119 |
| 8 | Defining words: `create`, `constant`, `variable` | `010-lib.fth` lines 185–192, 327–350 |
| 9 | Control flow as code emission | `010-lib.fth` `if,/then,/else,/begin,/while,/repeat,` |
| 10 | Immediacy and the single-pass compiler | `STATE`, the `immediate` bit, and why the compiler never needs a second pass |

### Part II — A C compiler in Forth

| # | Chapter | Source under discussion |
|---|---|---|
| 11 | Arena and I/O | `020-cc-arena.fth`, `030-cc-io.fth` |
| 12 | Preprocessing and lexing | `040-cc-prep.fth`, `050-cc-lex.fth` |
| 13 | Types and symbols | `060-cc-types.fth`, `070-cc-sym.fth` |
| 14 | ELF and codegen | `080-cc-elf.fth`, `090-cc-emit.fth` |
| 15 | Expressions | `100-cc-expr.fth` |
| 16 | Declarations and statements | `110-cc-decl.fth` |
| 17 | The main loop, end to end | `120-cc-main.fth` and the bootstrap chain |

### Appendices

- **A.** The 32 seed primitives — one-line reference.
- **B.** The memory map.
- **C.** The full hex0 → seed → C compiler → M2-Planet chain.
- **D.** Exercises (with worked solutions).

## How to read this book

The book is written so each chapter stands alone enough that you can
read it next to the file it discusses, in a side-by-side editor.
Wherever you see a citation like `010-lib.fth:33`, open that file at
that line and read it before continuing.  The book exists to make the
source readable; it is not a substitute for it.
