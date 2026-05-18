# Chapter 8 — Stack Shufflers

> **Status:** stub.  Canonical blocks below cover `010-lib.fth`
> lines 121–136.  Prose goes between them.

## Goal

By the end of this chapter the reader can:

- read and write all classical Forth stack-shuffle words by name;
- derive arbitrary shuffles using only the seed's five
  stack-manipulation primitives (`dup`, `drop`, `swap`, `>r`, `r>`);
- explain why deep-stack operators like `pick`/`roll` aren't
  worth defining in this seed (and what their cost would be).

## Source coverage

`010-lib.fth` lines 121–136.  Four definitions: `nip`, `rot`, `2dup`,
`2drop`.

## Concepts introduced

- **The shuffle vocabulary.**  Standard Forth has about a dozen
  named shuffles (`over`, `nip`, `tuck`, `rot`, `-rot`, `swap`,
  `2dup`, `2drop`, `2swap`, `2over`, etc.).  Most are one-liners on
  top of three or four primitives.
- **Building 2-cell shuffles from 1-cell ones.**  `2dup` is `over
  over`; `2drop` is `drop drop`.  No new ideas, just doubling.

## Concepts carried in

- `swap`, `drop`, `dup`, `>r`, `r>` (seed primitives, Ch 1).
- `over` (Ch 4).

## Concepts deferred

- `pick`/`roll` (not defined in this codebase; brief discussion only).
- The C compiler's heavy use of `>r r@ r>` for register-spill-like
  patterns — Part III, Ch 26.

## Section plan

1. **`nip` — the simplest derivative.**  `swap drop`.  Walk the
   stack in two lines.  Note that this is what you'd write if you
   forgot the name `nip` existed.
2. **`rot` — the return-stack trick again.**  `>r swap r> swap`.
   This is the same pattern as `over` (Ch 4), generalised.
3. **`2dup` from `over over`.**  After the first `over`, stack is
   `a b a`.  After the second, `a b a b`.  Free pair-dup from a
   pair of single-copies.
4. **`2drop` is just `drop drop`.**  No surprises.
5. **What's missing and why.**  `pick` and `roll` would require
   non-constant return-stack juggling (or actual stack-pointer
   manipulation), which the seed doesn't expose.  The C compiler
   *would* need them in theory; it avoids them in practice by
   keeping stack depth shallow at every junction.

## Canonical source

```forth file=010-lib.fth
\ ===== Stack shuffles =====
\ Standard Forth stack-manipulation words built on the seed primitives
\ swap, dup, drop, >r, r>, plus over (defined above).

\ nip ( a b -- b )  drop second-from-top.
: nip   swap drop ;

\ rot ( a b c -- b c a )  rotate third-from-top to top.
: rot   >r swap r> swap ;

\ 2dup ( a b -- a b a b )  duplicate the top pair.
: 2dup  over over ;

\ 2drop ( a b -- )  drop the top pair.
: 2drop drop drop ;

```

## Try it

```forth
\ gforth has all these built-in; you can either trust them or
\ paste our definitions to shadow.  The traces are identical:
: nip   swap drop ;
: rot   >r swap r> swap ;
: 2dup  over over ;
: 2drop drop drop ;

1 2 nip          .s   \ <1> 2
1 2 3 rot        .s   \ <3> 2 3 1
1 2 2dup         .s   \ <4> 1 2 1 2
1 2 3 4 2drop    .s   \ <2> 1 2
```

## Exercises

1. Define `tuck ( a b -- b a b )` two ways: as `swap over` and using
   `>r dup r> swap`.  Which compiles to fewer bytes?

2. Define `-rot ( a b c -- c a b )` (the inverse of `rot`) using
   *only* the seed's primitives plus already-defined helpers.

3. Define `2swap ( a b c d -- c d a b )`.  Hint: `rot >r rot r>`
   is one route.

4. Why is `pick` ( ... n -- ... x_n ) hard to define here?  Trace
   what it would have to do for `n=3` using only `dup`, `swap`,
   `drop`, `>r`, `r>`.  Show that the token count grows linearly
   with `n`, not constant-time.

## Takeaways

- Every shuffle is either a primitive or a short composition of
  primitives.  The shuffle vocabulary is finite — about a dozen
  classical names, all derivable.
- The return stack is used as a temporary parking spot for values
  that need to skip past `dup` / `over` operations.  The discipline
  is: `>r` and `r>` come in pairs *within the same word*.
- Deeper-than-third-of-stack access is not provided by this seed.
  Code that wants it must restructure or use the return stack
  explicitly.

Next: Chapter 9 — Memory Updates and Cell Writers.
