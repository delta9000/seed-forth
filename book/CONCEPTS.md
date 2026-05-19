# Concept index and dependency graph

This file does two jobs:

1. **Concept index** — every named idea in the book and the chapter
   that introduces it.  Use this when you want to remind yourself
   what "the consumed-slot property" means or which chapter first
   talks about lvalues.

2. **Dependency graph** — for each chapter, which previous chapters
   it requires.  Use this when picking what to write next: a chapter
   is "safe to write" once everything in its dependency list is at
   least 📝 in [README.md](README.md).

## Concept index

Each row: **concept** — first introduced in *Ch N*; used by *(Ch M,
Ch O, …)*.  Concepts not listed under a "used by" appear only in
their introducing chapter.

### Vocabulary and conventions

- **Stack (data stack)** — Ch 1; *every chapter*
- **Return stack** — Ch 4; *Ch 8, Ch 14, Ch 18, Ch 26*
- **Stack-effect notation `( a b -- c )`** — Ch 1; *every chapter*
- **Forth boolean convention (`-1`/`0`)** — Ch 6; *Chs 7, 11, 19, 27, 30*
- **RPN / postfix evaluation** — Ch 1; *Chs 4, 8, 27*
- **Dictionary entry layout** (`link/flags/name-len/name/body`) —
  Ch 10; *Chs 12, 17, 18, 23, 24*
- **Cells (8-byte) and bytes (1-byte)** — Ch 2; *Chs 9, 14, 17, 21*

### Forth primitives (treated as black boxes in Part I)

- **`nand`** — Ch 1 (use); Ch 15 (machine code)
- **`+`, `dup`, `drop`, `swap`** — Ch 1 (use); Ch 14–15 (machine code)
- **`>r`, `r>`, `r@`** — Ch 4 (use); Ch 14 (machine code)
- **`@`, `!`, `c@`, `c!`** — Ch 2 (use); Ch 14 (machine code)
- **`/`, `*`, `0=`** — Ch 6–7 (use); Ch 15 (machine code)
- **`here-addr`, `c,`** — Ch 2 (definitions); Ch 9, 11, 12 (use)
- **`emit`, `key`** — Ch 1 (sketched); Ch 16 (machine code)
- **`syscall6`** — Ch 5 (wrapper use); Ch 16 (machine code)
- **`find`, `'`, `execute`, `read_word`** — Ch 17
- **`:`, `;`, `[lit]`, `lit`** — Ch 10 (`:` used in `constant`);
  Chs 18, 20 (machine code)
- **`branch`, `0branch`** — Ch 19; *Ch 11 uses their xts*
- **`state`, `latest`** — Ch 10; *Chs 12, 18, 20*

### Forth-level ideas

- **Two's complement** — Ch 4
- **Functional completeness of NAND** — Ch 3
- **De Morgan's law as code** — Ch 3
- **Range-check trick `(c-base)/range == 0`** — Ch 6
- **Sign-extraction via `/2^63`** — Ch 7
- **Little-endian writers (`,4`, `,8`)** — Ch 9; *Chs 10, 11, 12, 21*
- **The IMMEDIATE flag** — Ch 10; *Chs 11, 12, 18, 20*
- **STATE (interpret vs compile mode)** — Ch 10; *Chs 11, 12, 18, 20*
- **The 19-byte runtime body** (`sub rbp,8; mov [rbp],rdi; movabs
  rdi,V; ret`) — Ch 10; *Ch 12, Ch 14*
- **Fixup-on-the-stack** — Ch 11; *Ch 19 (the underlying mechanism),
  Ch 30 (same idea in the C compiler's output)*
- **`comma-call` (compile a 5-byte rel32 CALL)** — Ch 11; *Ch 26*
- **Loop without `exit` (accumulate in a variable)** — Ch 12; *Ch 23*

### Seed VM internals (Part II)

- **ELF + program header** — Ch 13; *Ch 25*
- **The data-stack-in-`rdi`/`rbp` convention** — Ch 13; *Chs 14–20*
- **The sysvar page at `0x413000`** — Ch 13; *Chs 17, 18, 20*
- **The token buffer at `0x412800`** — Ch 13; *Ch 17, Ch 20*
- **The I/O scratch byte at `0x412000`** — Ch 13; *Ch 16*
- **The 16 MiB single segment** — Ch 13; *Ch 21*
- **`DIV` unsigned, `IDIV` signed** — Ch 15
- **In-line cell after CALL site** (`lit_code`) — Ch 18; *Ch 19*
- **Consumed-slot property** (branches return *to* destination, not
  past slot) — Ch 19
- **`NUMBER_HOOK`** — Ch 20

### C compiler ideas (Part III)

- **Bump allocator** — Ch 21
- **Source buffer / output buffer / back-patching** — Ch 21;
  *Chs 25, 26, 30, 31*
- **Macro table (parallel arrays)** — Ch 22
- **Token kinds (`KW_*`, `ID`, `PUNCT`, `NUM`, `STR`, `CHR`)** —
  Ch 23; *Chs 27–31*
- **Compact type encoding (one word per type)** — Ch 24;
  *Chs 27–31*
- **Struct descriptor (16 + 40·N bytes)** — Ch 24; *Ch 28*
- **Symbol table (parallel arrays)** — Ch 24; *Chs 26–31*
- **Scope stack (push/pop count)** — Ch 24; *Chs 30, 31*
- **System V AMD64 calling convention** — Ch 25; *Chs 26, 28, 31*
- **Frame pointer `rbp` + local-at-`-8n` addressing** — Ch 25;
  *Chs 26, 28, 31*
- **Lvalue vs rvalue** — Ch 28
- **Precedence climbing** — Ch 27
- **Fixed 256-byte function frame** — Ch 31 (every function
  reserves the same conservative slab; no per-function back-patch)
- **Stage-A parity (byte-identical M1 output)** — Ch 32

## Dependency graph

Each chapter lists its hard prerequisites.  "Carried in" from the
chapter stubs is the canonical source; this is a digest.

```
Ch 0   (prologue)         — none
Ch 1   stacks/words       — none
Ch 2   here/c,            — Ch 1
Ch 3   logic from nand    — Ch 1
Ch 4   over/subtract      — Ch 1
Ch 5   syscalls           — Ch 1
Ch 6   classifiers        — Chs 1, 3, 4
Ch 7   comparisons        — Chs 1, 4, 6
Ch 8   stack shufflers    — Chs 1, 4
Ch 9   memory writers     — Chs 1, 2, 4
Ch 10  immediate/constant — Chs 1, 2, 9
Ch 11  control flow       — Chs 1, 2, 4, 9, 10
Ch 12  defining words     — Chs 2, 3, 4, 7, 9, 10, 11
        (---- Part I complete; 010-lib.fth fully literate ----)
Ch 13  ELF + entry        — Ch 1                              (opens seed)
Ch 14  stack prims        — Chs 1, 13
Ch 15  arith prims        — Chs 14
Ch 16  I/O prims          — Chs 5, 14
Ch 17  dictionary         — Chs 10, 13, 14
Ch 18  colon compiler     — Chs 10, 17
Ch 19  branches           — Chs 11, 18
Ch 20  parser + REPL      — Chs 17, 18, 19
        (---- Part II complete; 000-seed.hex0 fully literate ----)
Ch 21  arena + I/O bufs   — Chs 5, 9, 12
Ch 22  preprocessor       — Chs 6, 12, 21
Ch 23  lexer              — Chs 6, 12, 21
Ch 24  types + symbols    — Chs 12, 21
Ch 25  ELF + codegen 1    — Ch 21
Ch 26  codegen 2          — Chs 24, 25
Ch 27  expressions 1      — Chs 23, 24, 25, 26
Ch 28  expressions 2      — Chs 24, 27
Ch 29  decl: types/globs  — Chs 24, 25, 26
Ch 30  statements         — Chs 11, 26, 27, 28
Ch 31  functions          — Chs 24, 26, 27, 28, 30
Ch 32  main + bootstrap   — *all previous*
```

## Reading orders (for the future reader, not the writer)

The book is written for **source order**, but a curious reader has
two valid alternatives:

- **Top-down ("what is this?"):** prologue → Ch 32 (skim) → Ch 1 →
  Ch 13 → Ch 21.  Gives you the shape of the whole machine before
  diving into any layer.

- **VM-first ("how does the seed work?"):** prologue → Chs 1, 13–20
  → Chs 2–12 → Part III.  Forth's primitives become machine code
  first, then you see them used.

Source order (the default) is best for someone who has decided to
follow the project from the bottom up and wants every concept earned.

## Suggested writing order

The dependency graph admits many valid orders.  Two pragmatic ones:

- **Source order** — Ch 2, Ch 3, ..., Ch 32.  Simplest; matches what
  the book teaches.  Use this unless you have a reason not to.

- **Climax-first** — Ch 1, Ch 2, Ch 11, Ch 12.  Once Ch 11 is
  written, you can demo control-flow combinators in every later
  chapter without forward references.  Use this if you'd rather
  see the Forth-level high point early and write the supporting
  chapters around it.

For Parts II and III, source order is the safer default because the
dependency graph has fewer constraints (every Part II chapter
depends only on Ch 1 and a few of its own siblings), so any sequence
that respects the diagram works.

## Keeping this file accurate

Update this file when:
- a chapter changes its line range in "Source coverage" (the index
  silently rots otherwise);
- a chapter adds a "Concept introduced" that wasn't here before;
- a chapter is renamed or split.

If [README.md](README.md)'s TOC and this file disagree, this file
is the source of truth for concepts; the TOC is the source of truth
for filenames.
