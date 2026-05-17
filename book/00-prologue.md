# Prologue — Two Thousand and Forty Bytes

There is a file in this repository called `000-seed.hex0`.  Its source
form is 27,067 bytes long, but most of that is comments — annotated
hex laid out for human readers.  The machine bytes total exactly
**2,040**, and those bytes are a working Forth.

This book is the manual for those 2,040 bytes, and for the
seven-thousand-line scaffold of Forth code that grows out of them into
a self-hosting C compiler.

---

## 1.  The journey

The codebase implements a chain:

```
   000-seed.hex0
        │
        │  assembled by stage0-posix's 229-byte hex0-seed
        ▼
   seed-forth           (a 2,040-byte ELF executable; ~32 primitives)
        │
        │  reads, in order
        ▼
   010-lib.fth          (Forth helpers built on those 32 primitives)
        │
        ▼
   020-cc-arena.fth     ┐
   030-cc-io.fth        │
   040-cc-prep.fth      │
   050-cc-lex.fth       │
   060-cc-types.fth     ├  ~8,000 lines of Forth that implement
   070-cc-sym.fth       │  a C-subset compiler
   080-cc-elf.fth       │
   090-cc-emit.fth      │
   100-cc-expr.fth      │
   110-cc-decl.fth      │
   120-cc-main.fth      ┘
        │
        │  reads C source from stdin, writes ELF to disk
        ▼
   /tmp/cc-out          (a working C-subset compiler in 64KB)
        │
        │  compiles
        ▼
   M2-Planet.c          (oriansj's self-hosting C compiler, used by Guix)
        │
        ▼
   M1 output           ────  byte-identical to ────  M1 output
   (our chain)                                       (GCC + M2-Planet)
```

The last line is the point.  M2-Planet is a real C compiler maintained
as part of the Guix Full Source Bootstrap.  When we compile M2-Planet
using our seed-forth-built compiler, the M1 intermediate output we
produce is byte-for-byte identical to what GCC produces from the same
M2-Planet source.  That is what makes the chain *auditable*: every
byte at the bottom is justified by the bytes above it, and no step
introduces unprovenance.

That is the bootstrap story.  It is half of what this book is about.

---

## 2.  The Forth story

The other half is the *language*.

Forth is what programmers built when computers had 4 KB of RAM and no
operating system.  It has no syntax — only a stream of
whitespace-separated tokens.  It has almost no semantics — only a data
stack and a dictionary of named definitions.  Type a word, the system
looks it up and runs it; type a number, the system pushes it on the
stack.  That is the entire model.

From that minimalism comes an unusual property: **the compiler is
itself a program written in the language.**  When you write

```forth
: square  dup * ;
```

the colon `:` and semicolon `;` are not keywords.  They are ordinary
dictionary entries, and what they do is execute *at parse time*: `:`
reads the name `square`, builds a dictionary header for it, and flips
the system into "compile mode"; `;` appends a `ret` instruction and
flips back.  In this codebase, both of them are 30-byte snippets of
hand-encoded x86-64 you will read in Part II.

The consequence is that Forth is extensible at the level of parsing,
compilation, and execution.  If you want a `for ... next` loop, you
write three new immediate words that emit `branch` and `0branch`
machine code at compile time.  If you want a `struct` keyword that
declares typed fields, you write it.  The language meets you halfway.

Most programmers who learn Forth describe a moment, somewhere around
the middle, when they realise that `if`/`then`/`else` are not
keywords — they are user-defined words that emit machine code at
compile time, and they are about thirty lines each.  At that point the
whole language collapses into a single idea: *words manipulate a
stack, and some words manipulate the dictionary that holds other
words.*

When you reach that moment in this book — Part I, Chapter 11 — you
will have written it yourself, or at least watched it being written,
starting from a base of 32 hand-encoded primitives.

---

## 3.  What this book teaches you

| By the end of | You can |
|---|---|
| **Part I** (Chs 1–12) | Read `010-lib.fth` line by line and explain every definition, including the control-flow combinators that make Forth a real language. |
| **Part II** (Chs 13–20) | Read `000-seed.hex0` byte by byte and explain why each x86-64 instruction is there.  Modify it without breaking the 2,040-byte invariant. |
| **Part III** (Chs 21–32) | Read a complete C-subset compiler implemented in 8,000 lines of Forth, understand its preprocessor, lexer, type system, symbol table, codegen, expression parser, and statement parser, and add a new operator or statement. |
| **Appendices** | Verify your extensions against the bootstrap chain.  Reproduce the byte-identical M1 result. |

---

## 4.  How to read this book

The book is literate.  Every fenced code block tagged `file=<path>` is
the canonical source for that file.  Chapter order is source order;
running `tools/tangle.sh verify --strict` confirms that the prose in
this book is consistent — byte-identical — with the canonical
`000-seed.hex0`, `010-lib.fth`, and so on.  When that strict check
passes, the book *is* the source.

Two practical tips before you start.

**Read side-by-side.**  Open the book in one editor pane and the file
under discussion in another.  Citations like `010-lib.fth:33` mean
"open `010-lib.fth` at line 33 before continuing."

**Try the playground first.**  Part I uses Forth syntax that you can
run interactively in `gforth` (`apt install gforth`) with the five-line
shim at [`book/playground.fth`](playground.fth) loaded.  You do not
need to build seed-forth itself until Part II, when we start reading
the hex.

---

## 5.  A sidebar on authorship

The codebase you are about to read was produced by a human author in
collaboration with an ensemble of large language models — Anthropic,
Google, OpenAI, DeepSeek, Alibaba, Moonshot, MiniMax, and others.
That collaboration is documented in `AI_STRATEGIES.md`, and it is
reflected in the careful annotation style throughout the source.

The seed Forth in particular is a synthesis artifact: many independent
attempts at the same 2,040-byte image, cross-checked against each
other and against a hand-derived reference.  The fact that 2,040 bytes
of x86-64 — every bit of which had to be argued for — was produced
this way is part of what makes the project interesting as a research
artifact, not just as a Forth.

But you do not need to care about any of that to learn Forth, or to
understand how a 2,040-byte seed grows into a C compiler.  The journey
works the same way it would have worked in 1972.

Turn the page.

Next: [Chapter 1 — Stacks and Words](01-stacks-and-words.md).
