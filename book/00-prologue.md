# Prologue — Seventeen Hundred and Seventy-Two Bytes

Here is where this book ends up.  From the repository root, paste
this into a terminal:

```sh
./build.sh
{ cat 010-lib.fth [0-9][0-9][0-9]-cc-*.fth; cat <<'EOC'; } | ./seed-forth
int fib(int n) { if (n < 2) return n; return fib(n - 1) + fib(n - 2); }
void print(int n) { if (n > 9) print(n / 10); putchar('0' + n % 10); }
int main(void) {
    int i;
    print(0);
    for (i = 1; i < 12; i = i + 1) { putchar(' '); print(fib(i)); }
    putchar('\n');
    return fib(10);
}
EOC
chmod +x /tmp/cc-out && /tmp/cc-out   # prints "0 1 1 2 3 5 8 13 21 34 55 89"
echo $?                               # prints "55"
```

`./seed-forth` is 1,772 bytes of x86-64 machine code, typed in as
hex.  It read twelve files of Forth from the pipe and became a C
compiler.  The compiler read the C that followed, recursion and
all, and wrote `/tmp/cc-out`, a Linux executable, directly.  No
assembler, linker, or C library took part.  Fed M2-Planet's own
source instead of nine lines of Fibonacci, the same pipeline
builds a C compiler whose output matches a GCC-built M2-Planet's
byte for byte.

Every step between those 1,772 bytes and that output is in this
book, in an order you can check.

---

Most of the code in this book was written by AI.  That is usually a
reason to stop reading, so it belongs up front.

Language models produce plausible code faster than anyone can read
it, and *plausible* is not *correct*.  The easy outcome is a pile of
code that works until it doesn't, which no person understands, and
a human reduced to rubber-stamping it.  This book is an experiment
in the other outcome: a human who stays in the loop, guiding,
auditing, and vouching for code an AI wrote faster than they could.

It turns on two things.  The first is a *test of correctness that
fluent-looking code cannot fake*: the compiler's output must match
an independent reference byte for byte, and reproduce itself exactly
when it compiles itself.  The second is *this book*, a literate
program in Donald Knuth's sense: source written to be read by a
human, in narrative order, with every line that matters explained.
The first keeps the machine honest.  The second keeps the human in
command.

A bootstrap was chosen as the proving ground because its correctness
is absolute; most software offers nothing so unforgiving.  That is
also the limit of the claim.  The lesson is not "audit any AI code
this way"; it is "find or build a ground truth the machine can't
argue with, then write the understanding down."

---

The seed lives in `000-seed.hex0`.  Its source form is 41,293 bytes
long, most of it comments: annotated hex laid out for human readers.
The machine bytes total exactly **1,772**.  On top of them sit
seven thousand lines of Forth that grow into a self-hosting C
compiler.

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

Two earlier teaching Forths make useful landmarks.  **JONESFORTH**
(Richard Jones, 2007) is the closest in tone, a heavily commented
assembly source, but it runs on i386 with *indirect threaded code*
and an inner interpreter that walks compiled cells.  This seed
targets x86-64 with *subroutine threading*: every compiled word is
a `call` instruction, so the CPU itself is the inner interpreter.
**sectorforth** (Cesar Blum, 2020) is a 512-byte 16-bit Forth with
eight primitives.  Our seed is four times larger and has 32
primitives because it has to carry a C compiler, not just a Forth.

## The moment

Most programmers who learn Forth describe a moment, somewhere
around the middle, when they realise that `if`/`then`/`else` are
not keywords.  They are user-defined words that emit machine code
at compile time, and with the loop words they take about thirty lines of code.  At that
point the whole language collapses into a single idea: *words
manipulate a stack, and some words manipulate the dictionary that
holds other words.*

When you reach that moment in this book (Part I, Chapter 11),
you will have written it yourself, or at least watched it being
written, starting from a base of 32 hand-encoded primitives.
Everything afterwards (the seed VM in Part II, the C compiler in
Part III) is a payoff for understanding that one move.

How the AI work was done (which models wrote what, and the
cross-checking that pinned down every byte of the seed) is in
`AI_STRATEGIES.md` at the repo root.  You can read this purely as a
Forth book and never think about it.

Chapter 1 starts at the bottom: a single line of Forth, which has
no expressions, no argument lists, and no `return`.

Next: [Chapter 1 — Stacks and Words](01-stacks-and-words.md).
