# Start here

Suppose a language begins with only a small collection of operations. You can
copy a value, discard it, add two values, read memory and write memory. How
much machinery can you build before you need another primitive?

Seed Forth makes that question concrete. Its annotated source describes a
1,772-byte x86-64 Linux executable with 32 named primitives. A Forth library
builds more words from them, and later parts of the project use that vocabulary
to implement a C compiler and a toolchain. Those later outcomes are the
destination of a longer series, not prerequisites for understanding the first
page.

Here is a small goal you can reach first: read a sequence that writes one byte
to memory, updates its cursor, and leaves the rest of the data stack alone.
You will explain each state change rather than take the sequence on trust.
Along the way, you will learn why a word can have a clear interface before you
understand the machine code that implements it.

## What you need

You need ordinary arithmetic and a willingness to write down intermediate
states. Prior programming experience can help, but assembly, Forth, pointers
and compiler construction are not assumed. Terms such as *cell*, *address*
and *bitwise* are introduced before the exercises rely on them.

The first three chapters require no installation. Their traces are worked by
hand from a stated contract, then checked against the relevant source. They
are not transcripts from a running seed. Code marked as a definition is real
seed Forth syntax; a memory picture with invented addresses is an illustrative
model, not a command to paste into a process.

If your aim is to reproduce the whole bootstrap immediately, this draft is
not yet a complete execution guide. The pinned repository's build and driver
documentation remains the operational reference. Keeping that distinction
visible prevents a missing tool or an untested command from masquerading as
a failure to understand the mechanism.

## Pick a route

Start with [Values and words](01-values-and-words.md) if stacks or Forth are
new to you. It explains why `dup +` doubles a value and why the top value in
division is the divisor.

If you already know Forth, check these three edition-specific questions:

1. Does a bare token such as `7` push a number in this seed, or does it need
   `[lit]`?
2. Does `here` return the cursor value or the address of the cell holding that
   value? Does `latest` follow the same convention?
3. Is `/` signed or unsigned, and does `0=` return one or all ones for true?

The answers are: use `[lit] 7`; `here` returns the cursor value while `latest`
returns a sysvar cell's address; `/` is unsigned and `0=` produces an all-ones
cell for true. If any answer differed from your expectation, read the relevant
contract before importing habits from another Forth.

Experienced readers can take a chapter's short diagnostic and move to its
independent or boundary exercises. You do not need to rehearse a procedure
you can already explain accurately. The goal is a capability, not a page
count.

## A trace is an argument you can inspect

Every stack picture puts the top at the right. Each row says whether it shows
the state before or after the operation. Values and addresses use explicit
units: one cell is eight bytes in this edition, and a byte address advances
by one for each byte. Small binary examples announce their width so they do
not quietly become claims about a 64-bit result.

When you see a worked trace, cover the next row and predict it if you want to
test your current model. Write down a reason, even a short one. If the result
surprises you, locate the first operation where your state differs. That is
usually a more useful question than asking whether you understand the whole
chapter.

Hints and complete solutions remain available. You can use them immediately
when you cannot begin. After reading a solution, try the changed case it
offers: reproducing an answer while looking at it and solving another case
independently are different accomplishments. Neither one alone demonstrates
that you will remember the mechanism next week or recognize it inside a
compiler.

## What we temporarily take as given

For now, a primitive word follows its stated stack contract when given valid
inputs. A definition made with `: name ... ;` composes those operations.
Readable and writable memory exists where an example explicitly says it does.
The machinery behind those promises has not vanished: later units will open
the dictionary, compiler, memory layout and machine instructions.

This order lets you first ask what the system does, then how it does it.
The full [learning path](../../LEARNING-PATH.md) identifies each deferred
interface. No first-unit exercise requires decoding a native instruction or
knowing a Linux syscall number.

The small seed also leaves many invalid cases unchecked. A word requiring two
stack values is not promised to stop safely when given one. A memory store
does not establish that its address is yours to write. We will state such
preconditions instead of inventing friendly error behavior.

## Pause and resume

You can stop after a worked example or before a practice set. Leave yourself
three notes: the starting state, the last operation you could explain, and
the next state you want to predict. On return, reopen that contract and make
one prediction before moving on. No fixed study interval or streak is needed
to use the book.

The first milestone is modest and useful: trace a word, trace a memory write,
and explain an arithmetic construction. Begin with
[Values and words](01-values-and-words.md).

## Source and status

The size, primitive count and profile are tied to
[`000-seed.hex0` at 7d7e1996](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0).
See the [edition record](../../EDITION.md) for claim boundaries. This draft has
not been tested with a representative new reader, and this manuscript pass
has not built or executed the seed or any compiler chain.
