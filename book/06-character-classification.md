# Chapter 6 — Character Classification

> **Status:** stub.  Canonical blocks below cover `010-lib.fth`
> lines 63–86.  Prose goes between them.

## Goal

By the end of this chapter the reader can:

- read the `(c - base) / range == 0` range-check idiom and explain
  why it works on unsigned arithmetic without conditionals;
- combine single-character classifiers into a chain (`alpha?`,
  `space?`);
- write a new classifier (e.g. `hex-digit?`, `printable?`).

## Source coverage

`010-lib.fth` lines 63–86.  Five definitions plus the section header:
`digit?`, `alpha-lower?`, `alpha-upper?`, `alpha?`, `space?`.

## Concepts introduced

- **Branch-free range check.**  `(c - base) / range == 0` is true
  exactly when `c` is in `[base, base+range)`, given that the
  seed's `/` is unsigned and an underflow wraps to a huge value.
- **The Forth boolean convention.**  `-1` for true, `0` for false.
  `0=` canonicalises any zero/non-zero to `-1`/`0`.
- **`or`-chaining for unions.**  `alpha?` = `alpha-lower? or
  alpha-upper?`.
- **Multi-equality folding with `over` + `or`.**  `space?` matches
  four codepoints by chaining four `c - X 0= or` calls.

## Concepts carried in

- `-`, `/`, `0=` from Chs 4 and 1 (and seed primitives `/`, `0=`).
- `or` from Ch 3.
- `dup`, `swap`, `over` from Chs 1 and 4.

## Concepts deferred

- Where these classifiers are *used* — Part III's lexer
  (`050-cc-lex.fth`, Ch 23).
- The seed's `/` primitive in x86-64 — Part II, Ch 15.

## Section plan

1. **Why classifiers matter.**  Every lexer in this codebase calls
   `digit?`, `alpha?`, `space?` thousands of times.  Cheap classifiers
   are a lexer's whole budget.
2. **The range-check trick.**  Walk `(c - 48) / 10 == 0`:
   - `c == '5' == 53`: `(53 - 48) / 10 == 0`, then `0= == -1`.  ✓
   - `c == 'A' == 65`: `(65 - 48) / 10 == 1`, then `0= == 0`.  ✓
   - `c == 0`:   `(0 - 48)` underflows to `2^64 - 48`, divides to
     `~1.84e18`, then `0= == 0`.  ✓
   Three branchless tokens, one truth value.
3. **`digit?`, `alpha-lower?`, `alpha-upper?`.**  Same idiom with
   different `base`/`range` pairs.  Note that `alpha?` then ORs the
   two case-classifiers together.
4. **`space?`: four-way OR.**  Read the chained `over [lit] N - 0=
   or` pattern.  Each iteration produces a flag, ORs it into the
   accumulator that started as `dup [lit] 32 - 0=`.  Trace stack
   shape at each step.
5. **What's not here.**  ASCII control-char detection, punctuation
   classes, locale-aware predicates.  None of them matter for a C
   tokenizer; the lexer in Ch 23 handles punctuation as a separate
   token class instead.

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

```forth
\ In the gforth playground:
: nand and invert ;  : [lit] ;
: -  dup nand 1 + + ;
: digit?  48 - 10 / 0= ;
: alpha-lower?  97 - 26 / 0= ;
: alpha-upper?  65 - 26 / 0= ;
: alpha?  dup alpha-lower? swap alpha-upper? or ;

char 5 digit?    .   \ -1
char A digit?    .   \ 0
char A alpha?    .   \ -1
char ! alpha?    .   \ 0
```

## Exercises

1. Write `hex-digit? ( c -- flag )` that returns true for
   `0..9 a..f A..F`.  How many tokens?  How does it compare to
   `digit? + alpha-lower-hex? + alpha-upper-hex?`?

2. The `space?` chain uses `dup` then three `over`s.  Why not four
   `over`s?  Trace the stack carefully.

3. The trick assumes `/` is *unsigned* division.  What would break if
   `/` were signed?  (Hint: the underflow argument fails.)

4. Write `octal-digit?` and `binary-digit?`.  Then write a generic
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
