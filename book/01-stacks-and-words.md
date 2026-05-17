# Chapter 1 — Stacks and Words

> "Forth is the language you would have invented if you were given a
> computer with 4 KB of RAM and a weekend."

This chapter teaches you the two ideas that everything else in this
codebase is built on:

1. **The data stack.**  Forth has no expressions, no operator precedence,
   no parentheses.  Every computation pushes and pops values from one
   shared stack.
2. **Words.**  A "word" is what Forth calls a named, callable thing —
   what C calls a function and Python calls a callable.  Every word
   takes its inputs from the stack and leaves its outputs on the stack.

That is the whole language model.  By the end of this chapter you will
read six real words from `010-lib.fth`, in this repository, and predict
what each one does to the stack before you run it.

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
  offset `0x1A1`.
- **There is no return value.**  A word "returns" by leaving things on
  the stack.  A word can leave zero, one, two, or any number of values
  — and *which* word it is determines how many.

The last point is the one that takes adjustment.  In Python, `len(xs)`
gives you one number back.  In Forth, the equivalent word might leave
one number, or two (length and capacity), or zero (storing the length
into a variable instead).  You learn to read the *stack effect* of each
word the way you learn type signatures in C.

---

## 1.2  Stack-effect comments

Open `010-lib.fth` at line 33 (`010-lib.fth:33`).  You will see:

```forth
\ over ( a b -- a b a )  copy second-from-top to top.
: over  >r dup r> swap ;
```

Ignore the body for now — Chapter 6 explains `>r` and `r>`.  Focus on
the comment `( a b -- a b a )`.

This is the universal Forth convention for documenting a word: write
what the stack looks like just **before** the word runs, then `--`,
then what the stack looks like **after**.  The rightmost name in each
half is the top of the stack.  So:

- `( a b -- a b a )` — `over` consumes nothing, but copies the value
  one slot down to the top.  Before: `a` is below `b`, `b` on top.
  After: `a`, then `b`, then `a` again on top.

You will see hundreds of these comments throughout this codebase.  They
are not optional decoration — they are how you read Forth.  Pencilling
them in as you trace through unfamiliar code is the equivalent of
running a debugger.

A few more from `010-lib.fth`:

```forth
\ nip ( a b -- b )                                 line 126
\ rot ( a b c -- b c a )                           line 129
\ 2dup ( a b -- a b a b )                          line 132
\ 2drop ( a b -- )                                 line 135
```

You can already predict everything those words do.  `nip` drops the
second-from-top.  `rot` brings the third-from-top to the top.  `2dup`
duplicates the top pair.  `2drop` discards two values.  These are
*stack shufflers*, and they will appear in every Forth program you ever
read.

---

## 1.3  Your first six words

We will now read six words from `010-lib.fth` end to end.  All six are
defined in the first hundred lines of the file.  This is not a curated
toy subset — it is what the C compiler in this repo is built on.

### `over` (line 33)

```forth
: over  >r dup r> swap ;
```

This is the canonical way to build `over` from the four primitives
`>r`, `dup`, `r>`, `swap`.  Trace it with the stack `( a b -- )` on
the left and the *return stack* `[ ]` on the right:

| step  | data stack    | return stack | what happened           |
|-------|--------------|--------------|-------------------------|
| start | `a b`        | `[ ]`        |                         |
| `>r`  | `a`          | `[ b ]`      | move top to return stk  |
| `dup` | `a a`        | `[ b ]`      | duplicate the new top   |
| `r>`  | `a a b`      | `[ ]`        | pull `b` back           |
| `swap`| `a b a`      | `[ ]`        | swap top two            |

We end with `( a b a )`, exactly as the comment promises.  Don't worry
yet about *why* `>r r>` exists — Chapter 6 — only that the trick works.

### `nip` and `rot` (lines 126, 129)

```forth
: nip   swap drop ;
: rot   >r swap r> swap ;
```

`nip` is obvious once you know `swap` and `drop`: swap brings the
second-from-top up, drop discards it.  Try `rot` yourself before
reading on:

<details>
<summary>Trace</summary>

| step  | data stack | return stack |
|-------|-----------|--------------|
| start | `a b c`   | `[ ]`        |
| `>r`  | `a b`     | `[ c ]`      |
| `swap`| `b a`     | `[ c ]`      |
| `r>`  | `b a c`   | `[ ]`        |
| `swap`| `b c a`   | `[ ]`        |

Net effect: `( a b c -- b c a )`.  ✓
</details>

### `+` and `-` (line 37)

`+` is a primitive — it lives in the seed at `0x1A1` and is not
defined in Forth at all.  But `-` is:

```forth
: -  dup nand [lit] 1 + + ;
```

This is your first taste of how minimal the seed really is.  There is
no subtract primitive; instead, the seed gives us `+` and the
single bitwise primitive `nand`.  Two's-complement arithmetic says
that `-b == (~b) + 1`, and `~b == b nand b`, so:

```
a - b  ==  a + (~b) + 1
       ==  a + (b nand b) + 1
```

Read the definition again with that in mind: `dup` makes `b b`,
`nand` reduces it to `~b`, `[lit] 1 +` adds one (giving `-b`), and
the final `+` adds it to the `a` that was waiting two slots down.

You will eventually stop being surprised by definitions like this.
The entire codebase is the same recipe applied at larger and larger
scales: derive everything from a handful of primitives, name the
result, and reuse it.

### `2dup` and `2drop` (lines 132, 135)

```forth
: 2dup  over over ;
: 2drop drop drop ;
```

`2dup` is a one-line gem.  After the first `over` the stack reads
`a b a`; after the second `over` it reads `a b a b`, which is
exactly the pair duplicated.  Walk through it on paper if you don't
believe it.

---

## 1.4  What a colon definition is, at this stage

You have already seen the surface syntax six times.  It looks like
this:

```forth
: name  body ;
```

For now, treat that as: "define a new word called *name* whose body
is the words between the colon and the semicolon."  That is *almost*
true and is enough to read Part I.

The full truth — that `:` and `;` are themselves ordinary words, that
`:` builds a dictionary header and switches the system into "compile
mode", and that `;` appends a `ret` instruction and switches back —
is the subject of Chapter 4.  You do not need it yet.  You do need
to be comfortable with the syntax.

One thing to notice: there is no comma between body words, no
parentheses, no return type, no argument list.  Forth's only
metasyntactic feature is whitespace.  Anywhere you can put a
character is a place where a word might end and a new word might
begin.

---

## 1.5  Why `[lit] 1`?  A note you can skip on first reading

In the `-` definition above you saw `[lit] 1 +` rather than just
`1 +`.  That is unusual; classical Forth lets you type `1` and have
it pushed automatically.  This codebase has a wrinkle: the seed does
not auto-parse numbers in interpret mode, and uses the explicit word
`[lit]` to mark "the next token is a decimal literal to be pushed."
Chapter 5 explains exactly why; for now just read `[lit] 1` as "the
number 1" wherever you see it.

If this annoys you, good — it should.  The annoyance is informative:
it is telling you that even *number parsing* is not built in.  Like
everything else in Forth, it is a word, and you can read its source
in `000-seed.hex0` at `parse_decimal_code @ 0x5FD`.  Chapter 5 takes
that walk.

---

## 1.6  Try it

You cannot yet run a REPL — the seed-forth binary does not have a
prompt in the usual sense; it reads its program from `stdin` and
exits.  But you can run the unit tests, which exercise exactly the
words this chapter introduced.  From the repo root:

```sh
./build.sh
./test.sh
```

Then open `test-010-lib.fth` and read the assertions.  You will see
the same `over`, `nip`, `rot`, `2dup`, `2drop`, `-` from this chapter,
each followed by an expected stack picture.  When you can predict the
expected stack for every test in that file without running it,
you are done with Chapter 1.

---

## 1.7  Exercises

1.  Write the stack effect comment for this definition without running
    it:

    ```forth
    : -rot  rot rot ;
    ```

2.  `tuck` is a classical Forth word with effect `( a b -- b a b )`.
    Define it using only `over`, `swap`, `dup`, `drop`, `>r`, `r>`.
    Multiple correct answers exist.  Compare yours to the one-liner
    that uses just two words.

3.  `pick` is `( ... n -- ... x_n )` — push a copy of the element `n`
    deep in the stack, where `0 pick` ≡ `dup` and `1 pick` ≡ `over`.
    Why is `pick` *not* defined in `010-lib.fth`?  (Hint: read what
    Chapter 2 will tell you about the seed primitives, and ask
    yourself how you would implement `pick` using only `dup`, `swap`,
    `drop`, `>r`, `r>`.  The answer is "you can't, in O(1) time" —
    why?)

4.  Open `010-lib.fth` at line 71 and read the definition of
    `digit?`.  Write its stack-effect comment, then explain in one
    English sentence what the strategy `(c - 48) / 10 == 0` is doing
    and why it does not need any conditional.

Solutions appear in Appendix D once that chapter is written.

---

## 1.8  Takeaways

- Forth has one data stack.  Every word consumes and produces values
  on that stack.
- Stack-effect comments `( before -- after )` are how you read Forth.
  Read them; pencil them in if they aren't there.
- A colon definition `: name  body ;` is the surface syntax for
  defining a new word.  Treat it as "function definition" for now.
- The codebase you are reading derives everything from a tiny set of
  primitives.  Even `-` is built from `+` and `nand`.  The next nine
  chapters will widen that lens.

Next: [Chapter 2 — The Seed Vocabulary](02-the-seed-vocabulary.md),
where we leave `010-lib.fth` and read the hand-encoded machine code in
`000-seed.hex0` that everything in this chapter ultimately runs on.
