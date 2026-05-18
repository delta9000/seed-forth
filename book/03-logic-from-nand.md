# Chapter 3 — Logic from One Primitive

> **Status:** stub.  Canonical blocks below cover `010-lib.fth` lines
> 22–30.  Prose goes between them.

## Goal

By the end of this chapter the reader can:

- explain why `nand` alone is functionally complete (every boolean
  function expressible in two-valued logic);
- derive `and`, `or`, `not`, and `xor` from `nand`;
- read a chained-nand expression and predict its truth table.

## Source coverage

`010-lib.fth` lines 22–30.  Two definitions: `and`, `or`, plus the
section header that motivates them.

## Concepts introduced

- **Functional completeness.**  A single two-input boolean function is
  enough to express any other boolean function, given duplication and
  reuse of inputs.  `nand` (and `nor`) are the canonical examples; the
  seed picks `nand`.
- **De Morgan's law as code.**  `a or b == ~(~a and ~b)` becomes a
  five-word Forth definition.
- **The `~` trick from `nand`.**  `b nand b == ~(b and b) == ~b`.  We
  used this already in Chapter 1's `-`; now we see why it works.

## Concepts carried in

- Stack effect notation, `nand`, `dup`, `swap` — all from Ch 1.

## Concepts deferred

- The hex bytes of the `nand_code` primitive in `000-seed.hex0` —
  Part II, Ch 15.
- Why `nand` rather than `and` + `invert` separately — touched on
  here, fully covered when we read the seed at Part II.

## Section plan

1. **Why "logic from nand" matters.**  Open with the question: if
   you were designing a Forth VM and could only have one bitwise
   primitive, which would you pick?  Show that `and`, `or`, `not`,
   `xor` all derive from `nand` (or from `nor`), but not from `and`
   alone.  The seed authors picked `nand` and saved a primitive slot.
2. **`and` in three words.**  Trace `nand dup nand`.  The first
   `nand` produces `~(a & b)`.  `dup nand` gives `~(~(a&b) & ~(a&b))
   == ~~(a&b) == (a & b)`.  Two negations cancel.
3. **`or` in five words.**  Trace `dup nand swap dup nand nand`
   stepwise.  Initial stack `( a b )` ends as `~(~a & ~b) == (a | b)`.
   Walk through with truth-table sanity checks.
4. **Brief sidebar: `xor` and `not`.**  Show how a reader could add
   them (they aren't in `010-lib.fth` because nothing needs them).
   `not = b nand b`; `xor = (a or b) and (a nand b)`.
5. **What this buys.**  Every conditional in this codebase ultimately
   tests a flag produced by some chain of `nand` and friends.  Forth's
   "boolean economy" pays off in seed-size: one logic primitive
   replaces four or five.

## Canonical source

```forth file=010-lib.fth
\ ----- bool / bitwise helpers built on nand -----
\ All derived because nand is the only logical primitive in the seed.

\ and ( a b -- a&b ) = ~~(a&b) = nand of nand-of-itself
: and  nand dup nand ;

\ or  ( a b -- a|b ) via De Morgan: ~(~a & ~b)
: or   dup nand swap dup nand nand ;

```

## Try it

In gforth via the playground (where `nand` is `and invert`):

```forth
\ Paste our definitions to shadow gforth's built-in and/or:
: and  nand dup nand ;
: or   dup nand swap dup nand nand ;

\ Truth-table check using -1 (all bits set) and 0 (all bits clear):
-1 -1 and .   \ -1
-1  0 and .   \ 0
 0 -1 and .   \ 0
 0  0 and .   \ 0
-1 -1 or  .   \ -1
-1  0 or  .   \ -1
 0 -1 or  .   \ -1
 0  0 or  .   \ 0
```

## Exercises

1. Define `xor ( a b -- a^b )` in terms of `nand` alone.  Confirm with
   the four-row truth table for `0` and `-1`.

2. Define `not ( a -- ~a )` in terms of `nand` alone.  How does
   `not` differ from `0=`?  When would you want each?

3. Prove on paper that `nor` (`not or`) is *also* functionally
   complete.  Then redefine `and` and `or` using only `nor`.  How
   many tokens longer do they become?

4. The seed could have spent a primitive slot on `not` and reduced
   `and` to one fewer token.  Why didn't it?  (Hint: count primitives
   in the seed dictionary and tally the byte cost of each.)

## Takeaways

- `nand` is functionally complete: every boolean function is
  expressible.
- `and = nand dup nand` and `or = dup nand swap dup nand nand` are
  not clever — they are direct transcriptions of "double negation"
  and "De Morgan's law".
- Picking the right primitive saves bytes in the seed.  We will see
  the same logic applied again in Ch 7 (comparisons from one
  arithmetic primitive: subtract).

Next: Chapter 4 — The Return Stack: `over` and Subtract.
