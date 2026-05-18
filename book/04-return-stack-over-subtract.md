# Chapter 4 — The Return Stack: `over` and Subtract

> **Status:** stub.  Canonical blocks below cover `010-lib.fth`
> lines 31–38.  Prose goes between them.

## Goal

By the end of this chapter the reader can:

- explain why Forth uses two stacks and what each is for;
- read and write `>r` / `r>` / `r@` idioms;
- derive subtraction from `+` and `nand` and predict the
  bit-by-bit behaviour for negative inputs;
- know exactly what `over` does mechanically, not just
  symbolically.

## Source coverage

`010-lib.fth` lines 31–38.  Two definitions: `over`, `-`.

## Concepts introduced

- **The return stack.**  A second LIFO that the seed's primitives
  `>r` / `r>` / `r@` push to and pop from.  Its primary purpose is
  call/return for colon definitions; we borrow it temporarily for
  stack-shuffle tricks.
- **Two's complement arithmetic.**  `-b = (~b) + 1`.  Combined with
  the fact that `~b = b nand b`, subtraction reduces to addition.
- **The cost of a "borrowed" return-stack slot.**  Three primitives
  (`>r`, `dup`, `r>`) plus a `swap` to do what a hypothetical `over`
  primitive would do in zero extra primitives.

## Concepts carried in

- `dup`, `swap`, `>r`, `r>`, `+`, `nand`, `[lit]` from Ch 1, the
  seed primitive set.
- The stack-effect convention from Ch 1.

## Concepts deferred

- The seed's `>r` / `r>` machine code — Part II, Ch 14.
- The full call/return story (how `:` and `;` themselves use the
  return stack) — Part II, Ch 18.
- Multi-step return-stack juggling (e.g. preserving a value across a
  long expression) — Ch 8's `rot` and later compiler-internal uses.

## Section plan

1. **Why two stacks at all?**  Most VMs have one stack for both data
   and calls.  Forth splits them so user code can manipulate the data
   stack freely without disturbing call/return.  Sketch what a
   single-stack Forth would look like and where it would hurt.
2. **`>r` / `r>` / `r@` as a sidebar.**  Read the seed primitive
   stack effects: `>r ( n -- ; R: -- n )`, `r> ( -- n; R: n -- )`,
   `r@ ( -- n; R: n -- n )`.  Note the `R:` convention.
3. **`over` via the return stack.**  Trace `>r dup r> swap` from
   `( a b -- )` to `( a b a -- )`, exactly as in Ch 1 but now with
   the return-stack column made explicit.  Explain why this works:
   `>r` parks `b` so `dup` can copy `a`; `r>` brings `b` back.
4. **`-` from `+` and `nand`.**  Derive two's complement from
   first principles for readers who don't remember it from a
   computer-architecture class.  Walk `: -  dup nand [lit] 1 + + ;`
   one token at a time, on the input `( 10 3 -- )` and on the input
   `( 3 10 -- )` (underflow → very large unsigned number that wraps
   to -7 when interpreted signed).
5. **Why subtraction isn't a primitive.**  Cost in primitive slots
   vs. cost in token-count when invoked.  The seed authors picked
   "save a slot, pay a few tokens".  Compare to the analogous choice
   in Ch 3 (`nand` over `and`+`invert`).

## Canonical source

```forth file=010-lib.fth
\ over ( a b -- a b a )  copy second-from-top to top.
\ Standard Forth idiom, missing from our seed primitives.
: over  >r dup r> swap ;

\ - ( a b -- a-b )  subtract via 2's complement (we have + and nand).
\ Used by classifier helpers and the local rel32 CALL encoder below.
: -  dup nand [lit] 1 + + ;

```

## Try it

```forth
\ In the gforth playground:
: over  >r dup r> swap ;
: -  dup nand [lit] 1 + + ;

1 2 over .s    \ <3> 1 2 1
10 3 -  .      \ 7
3 10 -  .      \ -7    (two's-complement; gforth prints signed)
```

## Exercises

1. Derive `tuck ( a b -- b a b )` two ways: once via `swap over`,
   once via `>r dup r> swap`-style primitives.  Show that both
   produce identical bytes when compiled (you'll need a built
   seed-forth for the byte comparison; gforth optimises).

2. Trace `0 [lit] 1 -` on paper.  What does the data stack hold?
   What is the bit pattern (in hex)?  Why does that bit pattern
   represent `-1` in two's complement?

3. Why does `-` have an extra `+` at the end (two `+`s total)?
   Walk the stack again and identify what each `+` consumes.

4. Write `negate ( n -- -n )` using only `nand`, `[lit]`, and `+`.
   How many tokens?  Compare to `0 swap -`.

## Takeaways

- The return stack is a second LIFO that exists primarily for
  call/return.  User code may borrow it via `>r`/`r>` provided
  every push is matched by a pop *within the same word*.
- `over` is not a primitive in this seed; it is built from four
  other primitives in five tokens.
- Subtraction is not a primitive either; it is built from `+` and
  `nand` in five tokens.  Both choices reflect the seed authors'
  preference for fewer primitive slots at the cost of slightly
  longer derived definitions.

Next: Chapter 5 — Talking to Linux: `syscall6` Wrappers.
