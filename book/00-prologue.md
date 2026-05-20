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
30-byte snippets of hand-encoded x86-64 you will read in Part II.

The consequence is that Forth is extensible at the level of
parsing, compilation, and execution.  If you want a `for ... next`
loop, you write three new immediate words that emit `branch` and
`0branch` machine code at compile time.  If you want a `struct`
keyword that declares typed fields, you write it.  The language
meets you halfway.

## The moment

Most programmers who learn Forth describe a moment, somewhere
around the middle, when they realise that `if`/`then`/`else` are
not keywords.  They are user-defined words that emit machine code
at compile time, and they are about thirty lines each.  At that
point the whole language collapses into a single idea: *words
manipulate a stack, and some words manipulate the dictionary that
holds other words.*

When you reach that moment in this book — Part I, Chapter 11 —
you will have written it yourself, or at least watched it being
written, starting from a base of 32 hand-encoded primitives.
Everything afterwards (the seed VM in Part II, the C compiler in
Part III) is a payoff for understanding that one move.

## A note on how this was built

The codebase you are about to read was produced by a human author
in collaboration with an ensemble of large language models from
Anthropic, Google, OpenAI, DeepSeek, Alibaba, Moonshot, MiniMax,
and others.  That collaboration is documented in
`AI_STRATEGIES.md`, and it is reflected in the careful annotation
style throughout the source.

The seed Forth in particular is a synthesis artifact: many
independent attempts at the same 2,040-byte image, cross-checked
against each other and against a hand-derived reference.  Every
bit of those 2,040 bytes had to be argued for.  That is part of
what makes the project interesting as a research artifact, not
just as a Forth.

You do not need to care about any of that to learn Forth, or to
understand how a 2,040-byte seed grows into a C compiler.  The
journey works the same way it would have worked in 1972.

Turn the page.

```
       __
   __( o)>   "you're about to write `if` yourself.  i know."
   \___/
```

Next: [Chapter 1 — Stacks and Words](01-stacks-and-words.md).
