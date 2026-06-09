# Prologue — Two Thousand and Forty Bytes

There is a file in this repository called `000-seed.hex0`.  Its
source form is 27,067 bytes long, but most of that is comments —
annotated hex laid out for human readers.  The machine bytes total
exactly **2,040**, and those bytes are a working Forth.

This book is the manual for those 2,040 bytes, and for the
seven-thousand-line scaffold of Forth code that grows out of them
into a self-hosting C compiler.

---

## The language

Forth is what programmers built when computers had 4 KB of RAM and
no operating system.  It has no syntax, only a stream of
whitespace-separated tokens.  It has almost no semantics, only a
data stack and a dictionary of named definitions.  Type a word,
the system looks it up and runs it; type a number, the system
pushes it on the stack.  That is the entire model.

From that minimalism comes an unusual property: **the compiler is
itself a program written in the language.**  When you write

```forth
: square  dup * ;
```

the colon `:` and semicolon `;` are not keywords.  They are
ordinary dictionary entries, and what they do is execute *at parse
time*: `:` reads the name `square`, builds a dictionary header for
it, and flips the system into "compile mode"; `;` appends a `ret`
instruction and flips back.  In this codebase, both of them are
short snippets of hand-encoded x86-64 you will read in Part II.

The consequence is that Forth is extensible at the level of
parsing, compilation, and execution.  If you want a `for ... next`
loop, you write three new immediate words that emit `branch` and
`0branch` machine code at compile time.  If you want a `struct`
keyword that declares typed fields, you write it.  The language
meets you halfway.

If you have read prior pedagogical Forth implementations, two are
close enough to this one to be worth a brief calibration.  **JONESFORTH**
(Richard Jones, 2007) is the closest spiritual ancestor in tone —
a heavily commented assembly source for a complete Forth — but it
runs on i386 with *indirect threaded code* and a separate "inner
interpreter" that walks compiled cells.  This book's seed targets
x86-64 with *subroutine threading*: every compiled word is just a
`call` instruction, so the CPU itself is the inner interpreter,
and the seed pays nothing for `NEXT`.  **sectorforth** (Cesar Blum,
2020) goes the other direction — a 512-byte 16-bit Forth with
eight primitives.  Our seed is four times larger (2,040 bytes) and
has 32 primitives because it has to host a C compiler at the top,
not just a Forth.  Appendix E lists these and others in more
depth; for now the orientation is: the seed sits between
sectorforth (smaller, no compiler payload) and JONESFORTH (similar
spirit, different threading model and architecture).

## The moment

Most programmers who learn Forth describe a moment, somewhere
around the middle, when they realise that `if`/`then`/`else` are
not keywords.  They are user-defined words that emit machine code
at compile time, and together they are only about sixty lines.  At that
point the whole language collapses into a single idea: *words
manipulate a stack, and some words manipulate the dictionary that
holds other words.*

When you reach that moment in this book — Part I, Chapter 11 —
you will have written it yourself, or at least watched it being
written, starting from a base of 32 hand-encoded primitives.
Everything afterwards (the seed VM in Part II, the C compiler in
Part III) is a payoff for understanding that one move.

This codebase was produced by a human author working with an
ensemble of large language models; the methodology and the
cross-checking that pinned down every byte of the seed are
documented separately in `AI_STRATEGIES.md` at the repo root.
You do not need to care about any of that to learn Forth, or to
understand how 2,040 bytes grow into a C compiler.  The journey
works the same way it would have worked in 1972.

Turn the page.

```
       __
   __( o)>   "you're about to write `if` yourself.  i know."
   \___/
```

Next: [Chapter 1 — Stacks and Words](01-stacks-and-words.md).
