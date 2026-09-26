# Chapter 6 — Character Classification

```text
Missing capability: no way to test whether a byte is a digit, letter, or whitespace.
New pattern: range checks via (byte - base) / span == 0.
Artifact after this chapter: digit?, alpha-lower?, alpha-upper?, alpha?, space?.
Proof link: the lexer (Ch 23) reuses these for identifier and number recognition.
```

Is this byte a digit?  In C you would write `c >= '0' && c <= '9'`.
The library has no `>=`, no `&&`, and no `if,`.  It has subtraction
(Ch 4), the seed's `/`, and `0=`, which only knows whether a number
is zero.  A range test out of those three looks impossible, and the
lexer in Part III needs one for every byte of every `.c` file it
reads.

`010-lib.fth` (lines 64–86) answers with five predicates: `digit?`,
`alpha-lower?`, `alpha-upper?`, `alpha?`, and `space?`.  The first
three share one three-token idiom with no conditional in it; §2
shows why it works, and why it depends on `/` being unsigned.  The
other two combine tests with Ch 3's `or`.  The lexer that calls them is Ch 23; the
`/` primitive is Ch 15.

## 1. Why classifiers matter

The whole shape of a lexer is `read a byte; classify it; dispatch.`
The dispatch runs once per token; the classification runs on
*every* byte: every space between tokens, every character of every
identifier, every digit of every number.  If `digit?` takes ten
tokens, you've roughly tripled the per-byte cost on number-heavy
input.  If it takes three, you've spent the budget where it
matters.

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

The third case is the one that matters.  With signed division,
`0 - 48 == -48` and `-48 / 10 == -4`, which is non-zero, so `c == 0` happens
to come out right.  But look just below the range: for `c` in
39..47 (`'` through `/`), `c - 48` is -9..-1, and signed division
truncates toward zero, so `(c - 48) / 10 == 0` and `0=` says
"digit."  Nine false positives.  The seed's `/` is the x86 `DIV`
instruction, which is *unsigned*.  Every negative difference,
reinterpreted as unsigned, is at least `2^64 - 48`; the quotient
stays huge, and `0=` gives 0.  This isn't a happy accident: the seed
authors chose unsigned `/` partly so this trick would keep working
without sign-juggling.

The trick generalises.  Any contiguous range `[base, base+range)`
becomes a subtract-divide-test classifier by plugging in the right two
literals.  No conditionals, no comparisons, no temporaries.

## 3. `digit?`, `alpha-lower?`, `alpha-upper?`, `alpha?`

Three classifiers fall out of the trick with no further work:

```forth
: digit?         [lit] 48 - [lit] 10 / 0= ;     \ '0'..'9'
: alpha-lower?   [lit] 97 - [lit] 26 / 0= ;     \ 'a'..'z'
: alpha-upper?   [lit] 65 - [lit] 26 / 0= ;     \ 'A'..'Z'
```

Each is the same subtract-divide-test shape with a different `(base, range)`
pair: `(48, 10)` for digits, `(97, 26)` for lowercase, `(65, 26)` for
uppercase.  The ranges are chosen to cover the relevant ASCII block
exactly: 26 lowercase letters, 26 uppercase, 10 digits.

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

The `dup` is the key move.  We need `c` twice, once for each
sub-classifier, so we copy it first, run the first classifier,
shuffle the copy of `c` up with `swap`, run the second classifier,
then `or` the two flags.  The same pattern appears wherever a
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
sequence (`dup` once, `over` twice, `swap` once) is the signature
of "use a value N times" in raw Forth.  It's the same shape Ch 8
codifies as the `nip`/`rot`/`2dup` family.

## 5. What's not here

The classifier set has only what the C lexer needs: no `punct?`,
no `printable?`, no `xdigit?`.  **C punctuation** (`+`, `(`, `;`,
and the rest) is handled in Ch 23 by direct codepoint comparison,
because the lexer needs to know *which* character it saw, not just
"it's punctuation."  To classify, use this chapter's trick; to
identify, use the lexer's dispatch.

There is no locale awareness either.  `010-lib.fth` and the C source
it compiles are 7-bit ASCII; bytes above 127 are identifier bytes or
syntax errors.  A self-bootstrapping compiler doesn't need UTF-8.

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

The seed's `[lit]` is a no-op in standard Forth, so this snippet
omits it; numbers parse directly.  Otherwise the definitions match
the seed source token for token.

### The full path: build the seed

```sh
./build.sh
{ cat 010-lib.fth
  echo '[lit] 53 digit?  0= [lit] 49 + emit'      # true  -> '1'
  echo '[lit] 65 digit?  0= [lit] 49 + emit'      # false -> '0'
  echo '[lit] 65 alpha?  0= [lit] 49 + emit'      # true  -> '1'
  echo '[lit] 33 alpha?  0= [lit] 49 + emit'      # false -> '0'
  echo '[lit] 32 space?  0= [lit] 49 + emit'      # true  -> '1'
  echo '[lit] 88 space?  0= [lit] 49 + emit'      # false -> '0'
} | ./seed-forth
```

The seed has no `.` for printing decimals.  The trick `0= [lit] 49 +
emit` turns a Forth flag into the ASCII character `'1'` (true) or
`'0'` (false): an extra `0=` flips `-1` to `0` and `0` to `-1`, then
adding 49 lands on `49` (`'1'`) or `48` (`'0'`).  The expected output
is `101010`: six classifications, alternating true and false in the
test order above.  Not one of those answers came from a comparison
or a branch.  Each came from a subtract, a divide, and a zero test.

## Exercises

1. **★★ Extend.** Write `hex-digit? ( c -- flag )` that returns true for
   `0..9 a..f A..F`.  How many tokens?  How does it compare to
   `digit? + alpha-lower-hex? + alpha-upper-hex?`?

2. **★★ Trace.** The `space?` chain uses `dup`, two `over`s, and a final
   `swap`.  What would be left on the stack if the last `swap` were
   an `over`?  Trace the stack carefully.

3. **★★ Trace.** The trick assumes `/` is *unsigned* division.  What would break if
   `/` were signed?  (Hint: the underflow argument fails.)

4. **★★ Extend.** Write `octal-digit?` and `binary-digit?`.  Then write a generic
   `between? ( c lo hi -- flag )` that takes its range from the
   stack.  Why is the per-range hard-coded version still preferable
   for the C lexer?

## Takeaways

- A range check on a character is subtract, divide, zero-test, with
  no conditionals.
- The check is correct below the range only because `/` is unsigned,
  so a negative difference becomes a huge quotient.
- Compound predicates like `alpha?` and `space?` combine single
  tests with `dup`/`over`/`swap` and `or`, needing no new primitives.

**Part I tally.**  Built so far: byte emission, Boolean logic,
subtraction, file I/O, **character tests**.  Still missing: `<`,
`if,`, `variable`.

Next: Chapter 7 — Comparisons from Unsigned Division.  `digit?`
tests a range without `<`, but the compiler still needs `<` itself,
for signed numbers, and the seed has no sign test, no shift, and no
`and` primitive to read the sign bit with.
