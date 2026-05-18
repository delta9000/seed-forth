# Chapter 7 — Comparisons from Unsigned Division

> **Status:** stub.  Canonical blocks below cover `010-lib.fth`
> lines 87–120.  Prose goes between them.

## Goal

By the end of this chapter the reader can:

- explain why an unsigned divide by `2^63` extracts the sign bit;
- read the chain from `=` (one token: `-`) through `<`, `>`, `<=`,
  `>=` (one extra token each);
- recognise the `0= 0=` "canonicalise to Forth boolean" idiom.

## Source coverage

`010-lib.fth` lines 87–120.  Eight definitions: `=`, `<>`, `2^63`,
`neg-flag`, `<`, `>`, `<=`, `>=`.

## Concepts introduced

- **Equality via subtract.**  `a = b` iff `a - b == 0`.  One primitive
  (`-`, derived in Ch 4) plus one (`0=`) gives us all of `=` and `<>`.
- **The sign bit via unsigned divide.**  A 64-bit value with bit 63
  set, divided unsigned by `2^63`, yields exactly `1`.  Any
  non-negative value yields `0`.  Two `0=`s canonicalise.
- **`2^63` as a constant.**  The literal `9223372036854775808` is
  `0x8000000000000000`; round-tripping it through the seed's decimal
  parser exercises an edge case (it's bigger than the maximum signed
  64-bit positive).
- **Composition: `<` from `<` plus `swap`; `<=` from `<` plus `0=`.**
  Each new comparison is one token of work given the one below.

## Concepts carried in

- `-` from Ch 4.
- `0=` (seed primitive).
- `/` (seed primitive, unsigned 64-bit divide).
- `swap` (seed primitive).

## Concepts deferred

- The seed's `/` machine code (`DIV` instruction) — Part II, Ch 15.
- Signed division (we don't define it; the C compiler doesn't need
  it).

## Section plan

1. **`=` and `<>`: two tokens each.**  `=` is `- 0=`.  `<>` is `= 0=`.
   That's it.
2. **Signed comparison is trickier.**  Forth's `/` is unsigned, so a
   naïve `<` from `-` would mis-classify negative results.  We need a
   sign-extracting primitive.
3. **The `2^63` trick.**  Walk an example: `n = -1` (all bits set,
   `0xFFFFFFFFFFFFFFFF`).  `(-1) / 2^63 = 0xFFFFFFFFFFFFFFFF /
   0x8000000000000000 = 1`.  And `n = 100`: `100 / 2^63 = 0`.  The
   trick is just "is bit 63 set?", phrased without bitwise AND
   (which we'd otherwise need a 64-bit literal for).
4. **`neg-flag` and `0= 0=`.**  Why the double zero-test?  Because
   `2^63 /` yields `1` or `0`, but we want the Forth `-1` / `0`
   convention.  `0=` flips `1 → 0` and `0 → -1`; the second `0=`
   flips back, but to canonical form: `0 → -1` and anything-non-zero
   → `0`.  Net: `1 → -1`, `0 → 0`.
5. **The cascade.**  `<` is `- neg-flag`.  `>` is `swap <`.  `<=` is
   `> 0=`.  `>=` is `< 0=`.  Each comparison after the first costs
   one token.

## Canonical source

```forth file=010-lib.fth
\ ===== Comparison operators =====
\ All return -1 (true) / 0 (false), Forth boolean convention.

\ = ( a b -- f )  -1 if a = b, else 0.  Equal iff (a - b) = 0.
: =   - 0= ;

\ <> ( a b -- f )  inverse of =.
: <>  = 0= ;

\ neg-flag ( n -- f )  -1 if n is signed-negative (bit 63 set), else 0.
\ Strategy: the seed's `/` is unsigned (DIV instruction).  A value with
\ bit 63 set, divided by 2^63, yields exactly 1; any non-negative value
\ yields 0.  Then `0= 0=` canonicalises (1 -> -1, 0 -> 0).
\ The literal 9223372036854775808 = 2^63 = 0x8000000000000000 round-trips
\ through parse_decimal_code because that parser uses an unsigned 64-bit
\ 2^63 = 0x8000000000000000, the sign bit of a 64-bit signed integer.
: 2^63  [lit] 9223372036854775808 ;

\ neg-flag ( n -- f )  return true if n is negative (sign bit set).
\ Dividing by 2^63 yields 0 for non-negative, 1 for negative.
: neg-flag  2^63 / 0= 0= ;

\ < ( a b -- f )  signed less-than: a < b iff (a - b) is negative.
: <   - neg-flag ;

\ > ( a b -- f )  signed greater-than: b < a.
: >   swap < ;

\ <= ( a b -- f )  not (a > b).
: <=  > 0= ;

\ >= ( a b -- f )  not (a < b).
: >=  < 0= ;

```

## Try it

```forth
\ In gforth (where 2^63 must be written as a hex literal):
: 2^63  $8000000000000000 ;
: neg-flag  2^63 / 0= 0= ;
: <  -  neg-flag ;
: >  swap < ;

 3  5  <  .   \ -1
 5  3  <  .   \ 0
-1  5  <  .   \ -1
 5 -1  <  .   \ 0
```

## Exercises

1. `<>` is defined as `= 0=`.  Why isn't it `- 0= 0=` (one fewer
   colon-call indirection)?  Count tokens; consider future readers.

2. The `2^63` literal is `0x8000000000000000`, which equals the
   most-negative signed 64-bit integer.  What does
   `9223372036854775808 .` print on a built seed-forth?  On gforth?
   Why the difference?

3. Define `0< ( n -- f )` (true if `n < 0`) and `0> ( n -- f )` (true
   if `n > 0`).  Compare to the standard Forth names.

4. The `0= 0=` canonicalisation appears here for the first time.
   Find at least one other place in `010-lib.fth` where the same
   pattern would simplify a definition.  (Hint: look at the
   comparison chains.)

## Takeaways

- One arithmetic primitive (`-`) and one logic primitive (`0=`) give
  us all six comparisons in twelve total tokens.
- The sign bit can be extracted with one unsigned divide by `2^63`,
  avoiding the need for a bitwise AND with a 64-bit immediate.
- Forth's `-1` / `0` boolean convention is what `0= 0=` produces;
  the convention exists precisely so that `if,` and `0branch` can
  test any value.

Next: Chapter 8 — Stack Shufflers.
