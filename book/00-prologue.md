# Prologue — Two Thousand and Forty Bytes

Most of the code in this book was written by AI.  That is the first
thing to say, because it is usually a reason to stop reading.

Language models now produce plausible code faster than any human can
read it, and *plausible* is not *correct*.  The bottleneck in
software was never typing; it is understanding, and trust.  When a
machine out-writes you at every step, the easy outcome is a large
pile of code that works until it doesn't and that no person actually
understands — and a human reduced to rubber-stamping it.

This book is an experiment in the other outcome: what it actually
takes for a human to stay in the loop — to guide, audit, and vouch
for — code an AI wrote faster than they could.

It turns on two things working together.  The first is a *mechanical
test of correctness that fluent-looking code cannot fake*.  The
program built here is a compiler, and its output must match an
independent reference byte for byte, and reproduce itself exactly
when it compiles itself.  No amount of confident-sounding code passes
that check; only correct code does.  The second is *this book
itself* — a literate program in Donald Knuth's sense: source written
to be read by a human, in narrative order, with every load-bearing
line explained.  The first keeps the machine honest.  The second
keeps the human in command.

The proving ground is a bootstrap: 2,040 bytes of hand-checkable
machine code that grow into a C compiler.  It was chosen because its
correctness is absolute and checkable — most software offers nothing
so unforgiving.  That is also the honest limit of the claim.  The
lesson is not "audit any AI code this way"; it is "find or build a
ground truth the machine can't argue with, then write the
understanding down."  What follows is one worked example of doing
exactly that.

---

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

The methodology — which models wrote what, and the cross-checking
that pinned down every byte of the seed — is documented in
`AI_STRATEGIES.md` at the repo root.  You can still read this purely
as a Forth book and never think about any of it; the journey works
the same way it would have worked in 1972.  But the reason it
exists, and exists in this form, is the experiment described above:
an AI did most of the writing, a mechanical oracle proved the result
correct, and this book is the part that lets a human understand it
and stand behind it.

Turn the page.

```
       __
   __( o)>   "you're about to write `if` yourself.  i know."
   \___/
```

Next: [Chapter 1 — Stacks and Words](01-stacks-and-words.md).
