# Chapter 1 — Stacks and Words

```text
Missing capability: no vocabulary or notation for thinking about Forth values.
New pattern: values live on the data stack; words read and write it; stack-effects name the shape.
Artifact after this chapter: the mental model the book runs on, plus over from the seed primitives.
Proof link: every line of 010-lib.fth reads on this notation; later chapters assume fluency.
```

> "Forth is the language you would have invented if you were given a
> computer with 4 KB of RAM and a weekend."

This chapter teaches you the two ideas that everything in this codebase
is built on:

1. **The data stack.**  Forth has no expressions, no operator
   precedence, no parentheses.  Every computation pushes and pops
   values from one shared stack.
2. **Words.**  A "word" is what Forth calls a named, callable thing —
   what C calls a function and Python calls a callable.  Every word
   takes its inputs from the stack and leaves its outputs on the stack.

That is the whole language model.  By the end of this chapter you
will have *previewed* six words from `010-lib.fth` and built enough
intuition to read the systematic walk that begins in Chapter 2.

```
       __
   __( o)>   "RPN is going to feel weird for about twenty minutes.
   \___/      then it's going to feel inevitable.  push through."
```

A navigation note before we start.  Every fenced code block tagged
`file=<path>` in this book is the canonical source for that file —
when the strict tangle check passes, those blocks reconstruct the
checked-in `.fth` and `.hex0` files byte-for-byte.  In this chapter,
the only canonical block is `010-lib.fth`'s file header, near the
end of §1.3.  The six definitions we read in §§1.4–1.6 are
*illustrative* here; their canonical, line-numbered, source-of-record
appearances live in Chapter 4 (`over`, `-`) and Chapter 8 (`nip`,
`rot`, `2dup`, `2drop`).  This split keeps the book's chapter order
matching the source order of `010-lib.fth`.

---

## 1.1  Reverse Polish, one more time

If you have ever used an HP calculator you know the drill.  To compute
`(3 + 4) * 5` you press

```
3 ENTER 4 + 5 *
```

That is exactly Forth.  The `ENTER` key is the space character; the
calculator's stack display is the only "variable" the language has.
Type this at the Forth REPL once you have one running:

```forth
3 4 + 5 *  .
```

The trailing `.` (pronounced "dot") prints the top of the stack.
Result: `35`.

Three properties fall out of this that you should hold in your head
before reading any more code:

- **No operator precedence.**  `3 4 + 5 *` and `3 4 5 * +` are
  different programs.  The order you push and pop is the program.
- **Operators are just words.**  `+` is a word that takes two numbers
  off the stack and leaves one.  It is not built into the parser;
  it is a dictionary entry like any other.  In this codebase it is
  defined in `000-seed.hex0` as a 5-byte machine-code routine at
  offset `0x1A1` — Chapter 15 will read its bytes.
- **There is no "return value".**  A word "returns" by leaving things
  on the stack.  A word can leave zero, one, two, or any number of
  values — and *which* word it is determines how many.

The last point is the one that takes adjustment.  In Python, `len(xs)`
gives you one number back.  In Forth, the equivalent word might leave
one number, or two (length and capacity), or zero (storing the length
into a variable instead).  You learn to read the *stack effect* of each
word the way you learn type signatures in C.

---

## 1.2  Stack-effect comments

Forth comments come in two flavours: `\ to end of line` and `( ... )`
inline.  By convention, the `( ... )` comments are reserved for stack
effects, and you put one on every word you define.  Here is the
convention applied to a word you are about to read, `over`:

```
\ over ( a b -- a b a )
```

This means: before `over` runs, the stack has `a` below `b`; after it
runs, the stack has `a`, then `b`, then `a` again on top.  Rightmost is
top-of-stack.  The `--` separates before from after.

You will see hundreds of these comments throughout this codebase.  They
are not optional decoration; they are how you read Forth.  Pencilling
them in as you trace through unfamiliar code is the equivalent of
running a debugger.

---

## 1.3  The file you are about to build

The file `010-lib.fth` is the first layer above the bare seed.  Its
header tells you that:

```forth file=010-lib.fth
\ 010-lib.fth — minimal helpers built on top of the 32 hand-encoded primitives.
\ Loaded before any Forth-level vocabulary.
\
\ Conventions:
\   - All arithmetic constants use [lit] (the decimal literal compiler)
\     because the seed has no interpret-mode number parser at all — [lit]
\     is the only path; see Ch 20 for the parser and the NUMBER_HOOK stub.
\   - Sysvar absolute addresses are baked in (decimal) since [lit] needs a
\     literal.  Update if 000-seed.hex0's sysvar layout ever moves.
```

The block above is tagged `file=010-lib.fth`.  When you run
`tools/tangle.sh extract /tmp/out`, those exact nine lines become the
first nine lines of `/tmp/out/010-lib.fth`.  The book is the source.

The two conventions in the header mention `[lit]` and "sysvar absolute
addresses" — both will be explained in their own chapters.  For now,
treat them as warnings on the door: this file is allowed to assume
nothing it does not say.

---

## 1.4  `over`, the first non-primitive word

Forth's seed gives us `dup`, `drop`, `swap`, `>r`, and `r>` as
stack-manipulation primitives.  Conspicuously absent: `over`, which
copies the second-from-top value up.  Almost every interesting Forth
program needs `over`, so it is defined immediately in `010-lib.fth`:

```forth
\ over ( a b -- a b a )  copy second-from-top to top.
\ Standard Forth idiom, missing from our seed primitives.
: over  >r dup r> swap ;
```

Read the body slowly.  The trick uses a *second* stack — the return
stack — which Chapter 4 will introduce in full.  For now, take it on
faith that `>r` moves the top of the data stack onto the return stack,
and `r>` moves it back.  Trace it:

| step  | data stack    | return stack | what happened           |
|-------|--------------|--------------|-------------------------|
| start | `a b`        | `[ ]`        |                         |
| `>r`  | `a`          | `[ b ]`      | move top to return stk  |
| `dup` | `a a`        | `[ b ]`      | duplicate the new top   |
| `r>`  | `a a b`      | `[ ]`        | pull `b` back           |
| `swap`| `a b a`      | `[ ]`        | swap top two            |

We end with `( a b a )`, exactly as the comment promised.  Do not worry
yet about *why* `>r r>` exists at all — only that the trick works.

This is also your first colon definition.  The syntax is

```
: NAME  body... ;
```

— a colon, the name, the body (any sequence of words separated by
whitespace), and a semicolon.  No commas, no parentheses, no return
type, no argument list.  Forth's only metasyntactic feature is
whitespace.

Chapter 18 will tell you the full truth about `:` and `;` — that they
are themselves ordinary words, that `:` builds a dictionary header and
switches the system into "compile mode", and that `;` appends a `ret`
instruction and switches back.  You do not need that truth yet.  You
do need to be comfortable with the syntax.

---

## 1.5  `-`, or: subtraction from nothing

The seed has `+`, but no `-`.  How do you subtract without a subtract?

```forth
\ - ( a b -- a-b )  subtract via 2's complement (we have + and nand).
\ Used by classifier helpers and the local rel32 CALL encoder below.
: -  dup nand [lit] 1 + + ;
```

Two's-complement says `-b == (~b) + 1`, and `~b == b nand b`.  So

```
a - b  ==  a + (~b) + 1
       ==  a + (b nand b) + 1
```

Read the body again with that in mind:

- `dup`             — duplicate `b`, giving `... a b b`.
- `nand`            — combine top two with nand, giving `... a ~b`.
- `[lit] 1 +`       — push the literal `1`, add: `... a (~b+1)` = `... a -b`.
- `+`               — add: `... (a + -b)` = `... (a - b)`.

Two things to notice.

**First**, the codebase types `[lit] 1` rather than just `1`.  That is
this codebase's wrinkle: the seed does not auto-parse numbers in
interpret mode, and uses an explicit word `[lit]` to mark "the next
token is a decimal literal to be pushed."  Chapter 20 walks the parser
that makes this work; for now, read `[lit] N` as "the number `N`".

**Second**, this is your first hint of what makes the seed special.
The whole bitwise universe — `and`, `or`, `xor`, `not` — and now
subtraction itself, all derive from just `nand` + `+`.  The codebase
does this everywhere, and the rest of Part I is mostly about watching
the trick scale up.

---

## 1.6  Stack shufflers: `nip`, `rot`, `2dup`, `2drop`

Skipping ahead in the file past the syscall wrappers (Ch 5), the
character classifiers (Ch 6), and the comparison operators (Ch 7),
we arrive at the `===== Stack shuffles =====` section.  These are the
last names you'll meet in this chapter; they round out the standard
Forth shuffler vocabulary.

```forth
\ nip ( a b -- b )  drop second-from-top.
: nip   swap drop ;

\ rot ( a b c -- b c a )  rotate third-from-top to top.
: rot   >r swap r> swap ;

\ 2dup ( a b -- a b a b )  duplicate the top pair.
: 2dup  over over ;

\ 2drop ( a b -- )  drop the top pair.
: 2drop drop drop ;
```

Four definitions, four lines each, no surprises.  Try `rot` on paper
before reading the trace:

<details>
<summary>Trace of <code>rot</code></summary>

| step  | data stack | return stack |
|-------|-----------|--------------|
| start | `a b c`   | `[ ]`        |
| `>r`  | `a b`     | `[ c ]`      |
| `swap`| `b a`     | `[ c ]`      |
| `r>`  | `b a c`   | `[ ]`        |
| `swap`| `b c a`   | `[ ]`        |

Net effect: `( a b c -- b c a )`.  ✓
</details>

`2dup` is a little gem.  After the first `over` the stack reads
`a b a`; after the second `over` it reads `a b a b`, which is exactly
the pair duplicated.  This is the kind of "just trust the algebra"
move that becomes natural after a week.

---

## 1.7  Try it

You have two ways to run Chapter 1's code, depending on how much
ceremony you want.

### The fast path: gforth

Install gforth from your package manager:

```sh
# Debian / Ubuntu
sudo apt install gforth
# macOS (Homebrew)
brew install gforth
```

The seed Forth in this repository is missing only two words that
standard Forth (and gforth) has under different names: `nand` (gforth
calls it `and invert`) and `[lit]` (gforth auto-parses numeric
tokens, so `[lit]` is unneeded).  A 5-line shim at
[`book/playground.fth`](playground.fth) defines both as
compatibility wrappers; with that loaded, every code block in this
chapter pastes verbatim into gforth.

```sh
gforth book/playground.fth
```

You should see a `seed-forth playground loaded.` banner, then a
prompt.  Try:

```
3 4 + 5 *  .   \ prints 35
1 2 over .s    \ shows <3> 1 2 1
10 3 - .       \ prints 7  (using gforth's built-in -)
bye
```

To exercise the chapter's *own* definitions (rather than gforth's
built-ins), paste them in:

```
: over  >r dup r> swap ;
: -  dup nand [lit] 1 + + ;
: nip   swap drop ;
: rot   >r swap r> swap ;
: 2dup  over over ;
: 2drop drop drop ;
```

gforth will print `redefined over redefined - ...` warnings — that is
expected, you are deliberately shadowing the built-ins with the seed
definitions.  Now `10 3 -` runs the seed's two's-complement-via-nand
implementation, not gforth's native subtract, and produces the same 7.

### The full path: build the seed

Once you want to leave Chapter 1's gforth playground and actually run
the seed Forth this book is about, you need the hex0 assembler.  From
the repo root:

```sh
git submodule update --init --recursive
./build.sh         # produces ./seed-forth (2040 bytes)
./test.sh          # runs the unit tests, including this chapter's words
```

`build.sh` uses stage0-posix's 229-byte `hex0-seed` to assemble
`000-seed.hex0` into the executable Forth.  Part II, starting in
Chapter 13, explains those bytes; for now, treat them as a black box.
`test.sh` exercises the
words you just read — `over`, `-`, `nip`, etc. — by feeding
`010-lib.fth` plus `test-010-lib.fth` into the seed.

Open `test-010-lib.fth` and read the assertions.  You will see the
same definitions from this chapter, each followed by an expected
stack picture.  When you can predict the expected stack for every
test in that file without running it, you are done with Chapter 1.

### And: verify the book

Whichever path you take, you can verify the literate side:

```sh
tools/tangle.sh verify
```

That extracts every code block tagged `file=010-lib.fth` from the
book (currently, just the six in this chapter) and checks that each
one appears, in order, in the real `010-lib.fth`.  As more chapters
land, coverage grows; when it reaches 100% and the `--strict` mode
passes, the book *is* the source.

---

## 1.8  Exercises

1.  **★★** Write the stack-effect comment for this definition without running
    it:

    ```forth
    : -rot  rot rot ;
    ```

2.  **★★** `tuck` is a classical Forth word with effect `( a b -- b a b )`.
    Define it using only `over`, `swap`, `dup`, `drop`, `>r`, `r>`.
    Multiple correct answers exist.  Compare yours to the one-liner
    `swap over`.

3.  **★★★** `pick` is `( ... n -- ... x_n )` — push a copy of the element `n`
    deep in the stack, where `0 pick` ≡ `dup` and `1 pick` ≡ `over`.
    Why is `pick` *not* defined in `010-lib.fth`?  (Hint: the seed's
    stack primitives are `dup`, `swap`, `drop`, `>r`, `r>`, plus the
    arithmetic and memory words listed in Appendix A.  Ask yourself
    how you would implement `pick` using only those.  The answer is
    "you can't in O(1) time" — why?)

4.  **★★** Open `010-lib.fth` at the line `: digit?  [lit] 48 - [lit] 10 / 0= ;`
    Write its stack-effect comment, then explain in one English
    sentence what the strategy `(c - 48) / 10 == 0` is doing and why
    it does not need any conditional.

Solutions appear in Appendix D.

---

## 1.9  Takeaways

- Forth has one data stack.  Every word consumes and produces values
  on that stack.
- Stack-effect comments `( before -- after )` are how you read Forth.
  Read them; pencil them in when they aren't there.
- A colon definition `: NAME  body ;` is the surface syntax for
  defining a new word.  Treat it as "function definition" for now.
- The codebase you are reading derives everything from a tiny set of
  primitives.  `-` is built from `+` and `nand`; `over` from
  `>r dup r> swap`; the bigger stack-shufflers from `over`.  The next
  nine chapters widen that lens.
- This book is literate.  The code blocks you read are the source.
  `tools/tangle.sh verify` checks that the book and the source
  agree.

Next: Chapter 2 — Code Emission and the HERE Pointer, where we begin
the systematic walk of `010-lib.fth` from its first two definitions
(`here-addr` and `c,`) and discover that the very first thing this
file does is teach Forth how to write bytes into memory.
