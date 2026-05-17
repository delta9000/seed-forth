# Chapter 2 — Code Emission and the HERE Pointer

> **Status:** stub.  The canonical code blocks below are in place;
> the prose around them is the writing task.  When the chapter is
> complete, `tools/tangle.sh verify --strict` covers `010-lib.fth`
> through line 21.

## Goal

By the end of this chapter the reader can:

- explain what `HERE` is and why Forth needs a name for "the next byte
  to write to";
- read and write the `here-addr @ ... here-addr !` idiom for
  read-modify-writing a sysvar cell;
- predict the post-state of HERE after a sequence of `c,` calls.

## Source coverage

`010-lib.fth` lines 9–21.  Two definitions: `here-addr` and `c,`.

## Concepts introduced

- The **sysvar page** at `0x413000` and the absolute address
  `0x413010` for the HERE cell.
- Pushing a large literal with `[lit]`.  (Full treatment in Part II,
  Ch 20.  Here, accept that `[lit] N` means "the integer `N`.")
- The seed primitive **`c!`** ("c-store") — store the low byte of TOS
  at the address below it.
- The **read-modify-write** pattern on a sysvar cell.

## Concepts deferred

- *Why* the sysvar page lives at `0x413000` and how it is initialised.
  See Part II, Ch 13.
- The `here` seed primitive (push the contents of the HERE cell, not
  its address).  See Part II, Ch 17.
- All of `,` (comma), `,4`, `,8` — multi-byte writers built on `c,`.
  See Ch 9.

## Section plan

1. **Why a "HERE" exists at all.** A Forth dictionary is a single
   growing arena of bytes.  HERE is the bump pointer.  Every defining
   word — `:` itself, `constant`, `create`, every immediate combinator
   in Ch 11 — advances HERE.
2. **`here-addr` — a one-line preview of the [lit] convention.**  The
   definition is one literal and a return.  Use it to introduce the
   reader to the absolute-address style this codebase uses
   (`4272144 == 0x413010`).
3. **`c,` and the workhorse pattern.**  Read the four lines.  Trace
   the stack:  `( b -- )`, `here` pushes the contents of the HERE
   cell, `c!` writes the byte, `here-addr @` re-fetches, `[lit] 1 +`
   increments, `here-addr !` stores it back.  Two cell accesses to
   bump one byte.  Note that this is deliberately *not* an atomic
   "increment cell" — that idiom is the focus of Ch 9 (`+!`).
4. **The big picture.**  Every byte the C compiler emits in Part III
   ultimately goes through `c,` (or one of its multi-byte cousins
   built on top of it).  This is the first line in the file because
   it is the foundation of everything below.

## Canonical source

```forth file=010-lib.fth

\ here-addr ( -- a )  push the address of the HERE sysvar cell.
\ Useful because most "advance HERE" idioms want to update the cell, not just
\ read its current value (which is what `here` does).
: here-addr  [lit] 4272144 ;            \ &HERE = 0x413010

\ c, ( b -- )  store low byte of TOS at HERE and advance HERE by 1.
\ This is the workhorse for any code-emission vocabulary built in Forth.
: c,
  here c!                                 \ *HERE = byte
  here-addr @ [lit] 1 + here-addr !       \ HERE += 1
;

```

## Try it

In gforth via the playground:

```sh
gforth book/playground.fth
```

```forth
\ Allocate scratch memory and use it as a fake HERE for the experiment.
create scratch  16 allot
variable my-here
scratch my-here !

: my-c,
  my-here @ c!
  my-here @ 1 +  my-here ! ;

65 my-c,   66 my-c,   67 my-c,
scratch 3 type    \ prints "ABC"
```

Same idea as the seed's `c,`, just against a private cell instead of
the system HERE.

## Exercises

1. After `[lit] 65 c, [lit] 66 c,`, what's at `here-addr @ - 2` and
   `here-addr @ - 1`?  Answer in two ASCII characters.

2. Why does `c,` re-fetch `here-addr @` *after* the `c!` instead of
   reusing the value pushed by `here` on the first line?  (Hint:
   `here` is a primitive that pushes the *contents* of the HERE cell;
   `here-addr` pushes the address.)

3. Write `2c,` ( w -- ) that stores the low *two* bytes of TOS at HERE
   in little-endian order.  Compare yours to `,4` when we meet it in
   Chapter 9.

4. The expression `[lit] 4272144` is 0x413010.  What sits at 0x413000,
   0x413008, 0x413018, 0x413020, 0x413028?  (You can answer from the
   memory-map in `README.md`; the full breakdown is Ch 13.)

## Takeaways

- Every byte the system emits — every dictionary header, every machine
  instruction inside a colon definition, every cell in a `create`d
  array — passes through `c,`.
- The sysvar page at 0x413000 is hard-coded throughout `010-lib.fth`
  by absolute address.  When 000-seed.hex0 changes layout, those
  literals must be updated in lockstep.
- Forth's "compiler" is not a separate program.  It is a chain of
  Forth words that ultimately call `c,`.

Next: Chapter 3 — Logic from One Primitive, where we use `nand` (and
nothing else) to build the full Boolean vocabulary.
