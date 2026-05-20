# Chapter 7 — Comparisons from Unsigned Division

Eight definitions in `010-lib.fth` (lines 87–120), `=`, `<>`, `2^63`,
`neg-flag`, `<`, `>`, `<=`, `>=`, give the seed every comparison
operator it will ever need without spending a single primitive
slot.  Equality reduces to `- 0=`; the sign bit drops out of an
unsigned divide by `2^63`; and `<`, `>`, `<=`, `>=` are each one
token longer than the one before.  Open `010-lib.fth` to those
34 lines and read along; the chapter takes its time on the
sign-bit-via-unsigned-divide move (the key trick that makes the
chain possible) and then lets the four signed comparisons fall out
in sequence.

By the end of the chapter you'll be able to explain why an
unsigned divide by `2^63` extracts the sign bit, read the chain
from `=` through `<`, `>`, `<=`, `>=` (each one extra token),
and recognise the `0= 0=` "canonicalise to Forth boolean" idiom.
The seed's `/` machine code (the `DIV` instruction) is Part II,
Ch 15; signed division is not defined anywhere in this codebase
because the C compiler doesn't need it.

---

Comparison is where most languages spend a primitive per operator:
`<`, `>`, `<=`, `>=`, `=`, `<>`, sometimes a separate set for signed
vs unsigned.  Six or twelve primitives, each with its own machine
code, each with its own dictionary entry.  The seed spends zero
primitive slots on comparison.  Every comparison this chapter
defines is built from `-`, `/`, and `0=`, with `2^63` as a literal
constant.

## 1. `=` and `<>`: two tokens each

```forth
: =   - 0= ;
: <>  = 0= ;
```

`=` is one of the simplest derived words in the seed.  Two numbers
are equal exactly when their difference is zero, so subtract them
and ask "is this zero?"  `0=` is a seed primitive that takes one
value off the stack and pushes `-1` if it was zero, `0` otherwise —
exactly the Forth boolean convention.  Two tokens, no further work.

`<>` is the negation.  Rather than write a slightly different
derivation, the seed reuses `=` and flips the answer.  `0=` here
plays the role of `not`: applied to a Forth boolean it produces the
opposite Forth boolean (`-1 → 0`, `0 → -1`).

This is the cheapest comparison story possible: two operators, four
tokens total, one of them a function call to the other.  Notice that
neither definition cares whether you are comparing addresses,
characters, integers, or signed-vs-unsigned numbers.  Equality is
bitwise, and `- 0=` is bitwise equality.  This is the same property
that makes Forth's stack work uniformly across types: the operators
don't see types, only 64-bit cells.

## 2. Signed comparison is trickier

`<` is harder.  The obvious attempt is "`a < b` iff `a - b` is
negative."  That's correct, but it raises an awkward question: how do
you ask "is this negative?" when the only sign-related primitive is
unsigned division?

A handful of approaches don't work:

- **`0<`** would be an obvious primitive, but the seed doesn't have
  it (it would cost a slot, and we're about to show it's derivable).
- **Bitwise AND with `0x8000000000000000`** is the textbook
  sign-bit test, but it needs a 64-bit immediate and an `AND`
  primitive — and the seed has neither a bitwise `AND` primitive
  (only `nand`) nor a way to compile a 64-bit immediate efficiently
  inside a derived word.
- **Sign-extend / shift right by 63** would work on a CPU with
  arithmetic shift, but the seed doesn't expose shifts at the Forth
  level.  Adding them as primitives would cost slots; deriving them
  from `*` or `/` would be expensive.

The seed's answer is a third path: **unsigned divide by `2^63`.**
Any 64-bit value, treated as unsigned, divided by `2^63 =
0x8000000000000000`, yields one of exactly two answers: `1` if the
top bit was set, `0` otherwise.  That's the sign-bit extraction we
needed, and it costs no new primitives.

## 3. The `2^63` trick

Here is the constant:

```forth
: 2^63  [lit] 9223372036854775808 ;
```

`9223372036854775808` is `2^63`, equal to `0x8000000000000000`.  In
unsigned 64-bit arithmetic it sits exactly in the middle of the
range; bit 63 is set, every other bit is zero.

Now `n / 2^63` for any 64-bit `n`, interpreting both as unsigned:

- `n = 0`: `0 / 2^63 == 0`.
- `n = 100`: `100 / 2^63 == 0` (numerator way smaller than
  denominator).
- `n = 2^63 - 1 = 0x7FFFFFFFFFFFFFFF` (largest positive signed):
  `≈ 9.22e18 / 9.22e18 == 0` (just under the divisor).
- `n = 2^63 = 0x8000000000000000` (the divisor itself):
  `1`.
- `n = -1 = 0xFFFFFFFFFFFFFFFF` (all bits set):
  `0xFFFFFFFFFFFFFFFF / 0x8000000000000000 == 1`.

The pattern is clean: anything with bit 63 clear divides to `0`;
anything with bit 63 set divides to `1`.  That's "is the sign bit
set?" answered as an unsigned arithmetic operation.

One subtle reason this trick is in the seed at all: the literal
`9223372036854775808` is bigger than the largest signed 64-bit
positive integer (`2^63 - 1 == 9223372036854775807`).  The seed's
decimal-literal parser accumulates an *unsigned* 64-bit value, so it
round-trips this number cleanly.  A signed-only parser would
overflow on the last digit.  Ch 20 covers the parser's machine code;
for now, take it on faith that the seed reads this literal correctly.

The literal `9223372036854775808` lives in a colon definition rather
than being inlined at every call site — that's what `: 2^63 [lit]
9223372036854775808 ;` is for.  Named once, called by name forever
after.

## 4. `neg-flag` and the `0= 0=` canonicalisation

```forth
: neg-flag  2^63 / 0= 0= ;
```

`2^63 /` gives us `0` or `1` — but the Forth boolean convention is
`0` or `-1`.  We need to convert.

`0=` flips:

- `0= 0` is `-1`.  (Zero becomes true.)
- `0= 1` is `0`.   (Non-zero becomes false.)
- `0= -1` is `0`.  (Non-zero becomes false.)

So `0=` is "logical NOT."  Applied once to our `0/1` flag:

- non-negative value → `0` → after `0=` → `-1`.
- negative value → `1` → after `0=` → `0`.

That's the *opposite* of what we want.  We want true (`-1`) for
negative, false (`0`) for non-negative.  So apply `0=` *again*:

- non-negative value → `0` → `0=` → `-1` → `0=` → `0`.  ✓
- negative value → `1` → `0=` → `0` → `0=` → `-1`.  ✓

The double `0= 0=` is the **canonicalise-to-Forth-boolean** idiom.
Any non-zero value, double-NOT'd, becomes `-1`; zero stays `0`.  It
shows up wherever the seed needs to turn a "0-or-something-else" raw
value into a proper Forth flag.

It might feel wasteful — three tokens to go from `1` to `-1` — but
remember the alternative: a sign-bit-test primitive in the seed.
Three tokens at call sites that fit on one fingertip is much cheaper
than another primitive slot in a 2,040-byte binary.

## 5. The cascade

Once `neg-flag` is in hand, the four signed comparisons unspool in
one token each:

```forth
: <   - neg-flag ;
: >   swap < ;
: <=  > 0= ;
: >=  < 0= ;
```

- `<` subtracts, then asks "is the result negative?"
- `>` is `<` with the operands swapped.
- `<=` is `> 0=` — "not greater-than."
- `>=` is `< 0=` — "not less-than."

Each new comparison is a one-token transformation of the previous.
This is the same pattern Ch 3 used for the boolean operators (each
new connective is a tiny rearrangement of `nand`).  It's also the
shape the C compiler's expression code will use in Part III, where
relational operators compile to one CMP and one of six SET cc forms.

Two implementation caveats worth flagging:

- **Signed overflow.**  `<` here is `(a - b) neg-flag`, which is the
  textbook signed comparison.  It works whenever `a - b` doesn't
  overflow — i.e., whenever the operands are in the same half of the
  signed range.  Comparing values near `2^63` could in principle
  trip this, but the C compiler never does that (all its numbers are
  small token counts, addresses, indices).
- **Unsigned comparison isn't here.**  C has both signed and
  unsigned `<`; this seed has only signed.  The C compiler in Part
  III treats all integer comparisons as signed.  That's a real
  semantic gap with standard C, but a deliberate one — the seed's C
  is a strict subset (Ch 32 enumerates exactly what's missing).

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
\ accumulator; the value also happens to be the sign bit of a 64-bit
\ signed integer.
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

### The fast path: gforth

The `2^63` trick depends on **unsigned** division, but gforth's `/`
is signed — so transcribing `neg-flag` verbatim would produce wrong
answers.  The playground covers other portability gaps but not this
one, so we shim `neg-flag` with gforth's native `0<` and let the rest
of the cascade follow.

```forth
\ Save as /tmp/ch7.fth and run with: gforth book/playground.fth /tmp/ch7.fth
: neg-flag   0< ;            \ shim: seed's 2^63 trick needs unsigned /
: =          - 0= ;
: <>         = 0= ;
: <          - neg-flag ;
: >          swap < ;
: <=         > 0= ;
: >=         < 0= ;

." 3=3  = "  3  3 =  . cr     \ -1
." 3<>3 = "  3  3 <> . cr     \  0
." 3<5  = "  3  5 <  . cr     \ -1
." -1<5 = " -1  5 <  . cr     \ -1
." 3<=3 = "  3  3 <= . cr     \ -1
." 3>5  = "  3  5 >  . cr     \  0
bye
```

### The full path: build the seed

```sh
./build.sh
{ sed -e 's/\\.*$//' -e 's/([^)]*)//g' 010-lib.fth
  echo '[lit] 3 [lit] 5 <  0= [lit] 49 + emit'      \ true  -> '1'
  echo '[lit] 5 [lit] 3 <  0= [lit] 49 + emit'      \ false -> '0'
  echo '[lit] 7 [lit] 7 =  0= [lit] 49 + emit'      \ true  -> '1'
  echo '[lit] 7 [lit] 8 =  0= [lit] 49 + emit'      \ false -> '0'
  echo '[lit] 3 [lit] 3 <= 0= [lit] 49 + emit'      \ true  -> '1'
  echo '[lit] 4 [lit] 3 <= 0= [lit] 49 + emit'      \ false -> '0'
} | grep -v '^[[:space:]]*$' | ./seed-forth
```

Expected output: `101010` — same true/false encoding as Ch 6.  The
seed runs the canonical `neg-flag` definition (the one that uses
`2^63 /`) with no shim, since its `/` is the unsigned `DIV`
instruction.

## Exercises

1. **★★** `<>` is defined as `= 0=`.  Why isn't it `- 0= 0=` (one fewer
   colon-call indirection)?  Count tokens; consider future readers.

2. **★★★** The `2^63` literal is `0x8000000000000000`, which equals the
   most-negative signed 64-bit integer.  What does
   `9223372036854775808 .` print on a built seed-forth?  On gforth?
   Why the difference?

3. **★★** Define `0< ( n -- f )` (true if `n < 0`) and `0> ( n -- f )` (true
   if `n > 0`).  Compare to the standard Forth names.

4. **★★★** The `0= 0=` canonicalisation appears here for the first time.
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
