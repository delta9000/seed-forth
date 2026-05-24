# Chapter 6 — Character Classification

```text
Missing capability: no way to test whether a byte is a digit, letter, or whitespace.
New pattern: range checks via (byte - base) / span == 0.
Artifact after this chapter: digit?, alpha-lower?, alpha-upper?, alpha?, space?.
Proof link: the lexer (Ch 23) reuses these for identifier and number recognition.
```

Five small predicates in `010-lib.fth` (lines 63–86), `digit?`,
`alpha-lower?`, `alpha-upper?`, `alpha?`, and `space?`, build a
character classifier vocabulary on a single three-token idiom: `(c
- base) / range 0=` is true exactly when `c` falls in `[base,
base+range)`.  The trick rides on the seed's `/` being x86 `DIV`
(unsigned), so underflow on the subtract still produces a non-zero
quotient and the test stays correct without any conditional.  Open
`010-lib.fth` to those 24 lines and read along; the chapter argues
why classifiers earn the optimisation effort (a lexer runs them on
every byte of input), walks through `digit?` byte by byte, then
shows the two composition patterns the rest use: `or`-chain for
unions like `alpha?`, and `over` plus `0= or` folding for the
four-codepoint `space?`.

By the end of the chapter you'll be able to read the `(c - base) /
range == 0` range-check idiom and explain why it works on unsigned
arithmetic without conditionals, combine single-character
classifiers into chains like `alpha?` and `space?`, and write a new
classifier such as `hex-digit?` or `printable?`.  Where these
classifiers are actually *used* (Part III's lexer at
`050-cc-lex.fth`) is Ch 23; the seed's `/` primitive in x86-64
(`DIV`) is Part II, Ch 15.

---

A lexer is, at its core, a loop that asks "what kind of character is
this?" for every byte of input.  When the C compiler in Part III
reads a 600-line `.c` file, it asks that question several thousand
times.  The cost of each call adds up, so the classifiers want to be
fast — ideally branch-free, ideally a handful of tokens.  This
chapter shows the three-token range-check trick that makes them so.

## 1. Why classifiers matter

The whole shape of a lexer is `read a byte; classify it; dispatch.`
The dispatch is rarely the hot path — keywords, punctuation, and
identifiers all flow through it once each.  The classification, by
contrast, runs on *every* byte: every space between tokens, every
character of every identifier, every digit of every number.  If
`digit?` takes ten tokens, you've slowed the lexer by an order of
magnitude on number-heavy input.  If it takes three, you've spent the
budget where it matters.

There's a second reason classifiers are worth obsessing over.  The
seed's lexer is written in Forth and compiled by the seed's own
compiler.  Every classifier call is a CALL instruction in the
output; every token inside the classifier is part of its body.
Shorter classifiers mean a shorter compiled lexer, which means a
smaller binary, which feeds back into the byte budget we keep talking
about.  Three-token classifiers are an aesthetic and a performance
choice at once.

## 2. The range-check trick

The idiom is:

```
( c -- flag )   c base - range / 0=
```

Read it as: subtract `base` from `c`, divide by `range`, test if zero.
The result is true exactly when `c ∈ [base, base+range)`.  Let's see
why, walking three cases through `digit?  ( c -- )  [lit] 48 -
[lit] 10 / 0= ;` (digits are `'0'..'9'` = ASCII 48..57):

- `c == '5' == 53`: `53 - 48 == 5`; `5 / 10 == 0`; `0=` → `-1`.  ✓ digit.
- `c == 'A' == 65`: `65 - 48 == 17`; `17 / 10 == 1`; `0=` → `0`.  ✓ not a digit.
- `c == 0`: `0 - 48` underflows to `2^64 - 48 ≈ 1.84×10^19`; dividing
  that by 10 leaves a huge number; `0=` → `0`.  ✓ not a digit.

The third case is the load-bearing one.  In a signed-arithmetic
language you'd worry that `0 - 48 == -48` and `-48 / 10 == -4` (or
`-5`, depending on rounding) — non-zero, so `0=` still returns 0,
fine.  But the seed's `/` is the x86 `DIV` instruction, which is
*unsigned*.  Negative values reinterpreted as unsigned become huge,
the division still produces a huge quotient, and `0=` still gives 0.
Both interpretations land on the same answer.  This isn't a happy
accident: the seed authors chose unsigned `/` partly so this trick
would keep working without sign-juggling.

The trick generalises.  Any contiguous range `[base, base+range)`
becomes a three-token classifier by plugging in the right two
literals.  No conditionals, no comparisons, no temporaries.

## 3. `digit?`, `alpha-lower?`, `alpha-upper?`, `alpha?`

Three classifiers fall out of the trick with no further work:

```forth
: digit?         [lit] 48 - [lit] 10 / 0= ;     \ '0'..'9'
: alpha-lower?   [lit] 97 - [lit] 26 / 0= ;     \ 'a'..'z'
: alpha-upper?   [lit] 65 - [lit] 26 / 0= ;     \ 'A'..'Z'
```

Each is the same three-token shape with a different `(base, range)`
pair: `(48, 10)` for digits, `(97, 26)` for lowercase, `(65, 26)` for
uppercase.  The ranges are chosen to cover the relevant ASCII block
exactly — 26 lowercase letters, 26 uppercase, 10 digits.

`alpha?` is the union of upper and lower:

```forth
: alpha?  dup alpha-lower? swap alpha-upper? or ;
```

Trace it on input `( c -- )`:

| token             | stack                                  |
|-------------------|----------------------------------------|
| (in)              | `c`                                    |
| `dup`             | `c c`                                  |
| `alpha-lower?`    | `c (c-is-lower?)`                      |
| `swap`            | `(c-is-lower?) c`                      |
| `alpha-upper?`    | `(c-is-lower?) (c-is-upper?)`          |
| `or`              | `c-is-lower? ∨ c-is-upper?`            |

The `dup` is the key move.  We need `c` twice — once for each
sub-classifier — so we copy it first, run the first classifier,
shuffle the copy of `c` up with `swap`, run the second classifier,
then `or` the two flags.  Identical pattern shows up wherever a
compound predicate is built from independent tests.

## 4. `space?`: four-way OR

Whitespace in C source means space (32), tab (9), newline (10), or
carriage return (13).  None of those are contiguous, so the
range-check trick doesn't apply.  Instead the classifier chains four
single-codepoint equality tests:

```forth
: space?  dup [lit] 32 - 0= over [lit]  9 - 0= or
          over [lit] 10 - 0= or  swap [lit] 13 - 0= or ;
```

A single-codepoint equality test is just `c X - 0=`: subtract the
target, check if zero.  Four of those, ORed together.

The stack-management here is the subtle part because we need `c` four
times.  Trace it with `c` on top:

| token            | stack                                    |
|------------------|------------------------------------------|
| (in)             | `c`                                      |
| `dup`            | `c c`                                    |
| `[lit] 32 -`     | `c (c-32)`                               |
| `0=`             | `c (c==32?)`                             |
| `over`           | `c (c==32?) c`                           |
| `[lit] 9 -`      | `c (c==32?) (c-9)`                       |
| `0=`             | `c (c==32?) (c==9?)`                     |
| `or`             | `c (c∈{32,9}?)`                          |
| `over`           | `c (c∈{32,9}?) c`                        |
| `[lit] 10 -`     | `c (c∈{32,9}?) (c-10)`                   |
| `0=`             | `c (c∈{32,9}?) (c==10?)`                 |
| `or`             | `c (c∈{32,9,10}?)`                       |
| `swap`           | `(c∈{32,9,10}?) c`                       |
| `[lit] 13 -`     | `(c∈{32,9,10}?) (c-13)`                  |
| `0=`             | `(c∈{32,9,10}?) (c==13?)`                |
| `or`             | `(c∈{32,9,10,13}?)`                      |

The first test uses `dup` (keep `c` underneath for next round), the
middle two use `over` (still need `c` after this round), and the last
uses `swap` (we're done with `c`; bring it up to be consumed).  That
asymmetry — `dup` once, `over` twice, `swap` once — is the signature
of "use a value N times" in raw Forth.  It's the same shape Ch 8
codifies as the `nip`/`rot`/`2dup` family.

## 5. What's not here

The seed's classifier set has only what the C lexer needs.  No
`punct?`, no `printable?`, no `xdigit?`, no `cntrl?` — those either
fall out as exercises or are folded into the lexer's
token-class-dispatch code instead.

In particular, **C punctuation** (`+`, `-`, `*`, `/`, `(`, `)`, `;`,
`,`, etc.) is handled in Ch 23 by direct codepoint comparison inside
the lexer, not by a classifier.  That's because the lexer needs to
know *which* punctuation character it saw, not just "yes, it's
punctuation" — the binary flag isn't useful.  When you only need to
classify, the trick from this chapter applies; when you need to
identify, you reach for the lexer's switch-style dispatch.

There's also no locale awareness here.  ASCII is the only encoding
the seed deals with — both `010-lib.fth` and the C source it compiles
in Part III are 7-bit ASCII.  Everything from `0` to `127` is in
range; everything above is treated as bytes-of-an-identifier or
syntax error.  No UTF-8, no extended Latin, no character properties.
A self-bootstrapping compiler doesn't need them, and adding them
would multiply both the byte cost and the conceptual surface area.

## Canonical source

```forth file=010-lib.fth
\ ===== Character classification helpers =====
\ All return -1 if true, 0 if false (Forth boolean convention).
\ Approach: just hard-code the literal byte values and use 0= equality chains.

\ digit? ( c -- flag )  true if c is in '0'..'9' (ASCII 48..57)
\ Approach: compute (c-48)/10.  If c<48 the subtract underflows to a huge
\ unsigned, /10 is huge, 0= is 0.  If c in 48..57, (c-48)/10 = 0, 0= is -1.
\ If c >= 58, (c-48)/10 >= 1, 0= is 0.  ✓
: digit?  [lit] 48 - [lit] 10 / 0= ;

\ alpha-lower? ( c -- flag )  true if c is 'a'..'z' (97..122)
\ Same trick: (c-97)/26 = 0 iff c in 97..122.
: alpha-lower?  [lit] 97 - [lit] 26 / 0= ;

\ alpha-upper? ( c -- flag )  true if c is 'A'..'Z' (65..90)
: alpha-upper?  [lit] 65 - [lit] 26 / 0= ;

\ alpha? ( c -- flag )  true if c is alphabetic
: alpha?  dup alpha-lower? swap alpha-upper? or ;

\ space? ( c -- flag )  true if c is ' '|tab|LF|CR
: space?  dup [lit] 32 - 0= over [lit]  9 - 0= or
          over [lit] 10 - 0= or  swap [lit] 13 - 0= or ;

```

## Try it

### The fast path: gforth

Save as `/tmp/ch6.fth` and run `gforth book/playground.fth /tmp/ch6.fth`:

```forth
: digit?         48 - 10 / 0= ;
: alpha-lower?   97 - 26 / 0= ;
: alpha-upper?   65 - 26 / 0= ;
: alpha?         dup alpha-lower? swap alpha-upper? or ;
: space?         dup 32 - 0= over 9 - 0= or
                 over 10 - 0= or  swap 13 - 0= or ;

." 5 digit? = "  char 5 digit? . cr        \ -1
." A digit? = "  char A digit? . cr        \  0
." A alpha? = "  char A alpha? . cr        \ -1
." ! alpha? = "  char ! alpha? . cr        \  0
." sp space? = " bl space?      . cr       \ -1
." TAB space? = " 9 space?      . cr       \ -1
." X space? = "  char X space?  . cr       \  0
bye
```

The seed's `[lit]` is a no-op in standard Forth, so the playground
omits it; numbers parse directly.  Other than that the definitions
are byte-identical to the seed source.

### The full path: build the seed

```sh
./build.sh
{ sed -e 's/\\.*$//' -e 's/([^)]*)//g' 010-lib.fth
  echo '[lit] 53 digit?  0= [lit] 49 + emit'      \ true  -> '1'
  echo '[lit] 65 digit?  0= [lit] 49 + emit'      \ false -> '0'
  echo '[lit] 65 alpha?  0= [lit] 49 + emit'      \ true  -> '1'
  echo '[lit] 33 alpha?  0= [lit] 49 + emit'      \ false -> '0'
  echo '[lit] 32 space?  0= [lit] 49 + emit'      \ true  -> '1'
  echo '[lit] 88 space?  0= [lit] 49 + emit'      \ false -> '0'
} | grep -v '^[[:space:]]*$' | ./seed-forth
```

The seed has no `.` for printing decimals.  The trick `0= [lit] 49 +
emit` turns a Forth flag into the ASCII character `'1'` (true) or
`'0'` (false): an extra `0=` flips `-1` to `0` and `0` to `-1`, then
adding 49 lands on `49` (`'1'`) or `48` (`'0'`).  The expected output
is `101010` — six classifications, alternating true and false in the
test order above.

## Exercises

1. **★★ Extend.** Write `hex-digit? ( c -- flag )` that returns true for
   `0..9 a..f A..F`.  How many tokens?  How does it compare to
   `digit? + alpha-lower-hex? + alpha-upper-hex?`?

2. **★★ Trace.** The `space?` chain uses `dup` then three `over`s.  Why not four
   `over`s?  Trace the stack carefully.

3. **★★ Trace.** The trick assumes `/` is *unsigned* division.  What would break if
   `/` were signed?  (Hint: the underflow argument fails.)

4. **★★ Extend.** Write `octal-digit?` and `binary-digit?`.  Then write a generic
   `between? ( c lo hi -- flag )` that takes its range from the
   stack.  Why is the per-range hard-coded version still preferable
   for the C lexer?

## Takeaways

- A range check on a single character costs three tokens: subtract,
  divide, zero-test.  No conditionals required.
- The trick depends on unsigned division and the wrap-around
  behaviour of unsigned subtract.  In Ch 15 we'll see the x86 `DIV`
  instruction that makes it cheap.
- Combining classifiers with `or` builds compound predicates with
  no new primitives.  `alpha?` and `space?` are the templates;
  every later predicate follows the pattern.

Next: Chapter 7 — Comparisons from Unsigned Division.
