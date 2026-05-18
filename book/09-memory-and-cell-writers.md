# Chapter 9 — Memory Updates and Cell Writers

> **Status:** stub.  Canonical blocks below cover `010-lib.fth`
> lines 137–161.  Prose goes between them.

## Goal

By the end of this chapter the reader can:

- read and write the `+!` / `-!` "atomic-ish increment-cell" idiom;
- explain the little-endian byte layout the codebase uses everywhere
  and emit a multi-byte value with `,4` and `,8`;
- predict what `,8` does to a 64-bit value bit by bit, including the
  `[lit] 256 / ... / ... / ... /` cascade that performs the
  right-shift-by-32.

## Source coverage

`010-lib.fth` lines 137–161.  Four definitions: `+!`, `-!`, `,4`, `,8`.

## Concepts introduced

- **Read-modify-write on a cell.**  `+! ( n addr -- )` adds `n` to
  the 64-bit cell at `addr`.  Inverse: `-!`.  Both are short — three
  primitives plus a `swap`.
- **Little-endian multibyte writers.**  `,4` emits the low four
  bytes of TOS at HERE, low byte first.  `,8` is two `,4`s with a
  right-shift-by-32 in between.
- **Right-shift by repeated divide.**  No shift primitive in the
  seed; instead `[lit] 256 /` four times moves the high half down.
  Slow but trivially correct.

## Concepts carried in

- `c,` from Ch 2 (the underlying byte writer).
- `here`, `here-addr` from Ch 2.
- `+`, `-`, `/`, `dup`, `swap`, `over`, `@`, `!` from earlier
  chapters and seed primitives.

## Concepts deferred

- Atomicity: these "atomic-ish" increments are *not* multi-threaded
  safe, but seed-forth is single-threaded.  No threading story
  appears anywhere in this book.
- Big-endian writers: never needed (x86-64 is LE; ELF is LE; M1
  output is LE-token text).
- The use of `,8` in `constant`, `create`, `variable` for the
  `movabs` imm64 slot — Ch 10.

## Section plan

1. **`+!` and `-!`: idiomatic increment.**  Walk
   `: +!  swap over @ + swap ! ;`.  Stack picture:
   `( n addr -- ) swap → ( addr n ) over → ( addr n addr ) @ → ( addr
   n cell-value ) + → ( addr new-value ) swap → ( new-value addr ) !
   → ( )`.  Same for `-!`.
2. **`,4` and `,8`: the workhorses for cell-sized emission.**  `,4`
   is `dup c,` four times with a `[lit] 256 /` shift between each.
   `,8` is `dup ,4` then four shifts then `,4` for the high half.
3. **Why divide by 256?**  Because the seed has `/` but no `>>`.
   Dividing by 256 is the same as shifting right by 8.  Cheap on
   `DIV` (a few hundred cycles in 1995-era CPUs; nothing in 2026).
4. **The shift-by-32 cascade.**  Read `[lit] 256 / [lit] 256 / [lit]
   256 / [lit] 256 /` as one operation: shift right by 32, the
   high half of a 64-bit value moved into the low half so the
   second `,4` can write it.
5. **Where these are used.**  `,4` is called by `comma-call` (Ch 11)
   to emit a 4-byte `rel32`.  `,8` is called by `constant`, `create`,
   `variable` (Ch 10) to embed `imm64` values in the runtime body of
   defined words.

## Canonical source

```forth file=010-lib.fth
\ ===== Memory update helpers =====

\ +! ( n addr -- )  add n to the cell at addr.
: +!  swap over @ + swap ! ;

\ -! ( n addr -- )  subtract n from the cell at addr.
: -!  swap over @ swap - swap ! ;

\ ===== 4-byte little-endian writer =====
\ ,4 ( v -- )  emit low 4 bytes of v at HERE in LE order.
\ Used by comma-call (rel32) and any Forth-level code emitter that needs
\ compact little-endian immediates.
: ,4
  dup c,                       \ byte 0
  [lit] 256 / dup c,           \ byte 1
  [lit] 256 / dup c,           \ byte 2
  [lit] 256 / c, ;             \ byte 3

\ ,8 ( v -- )  emit all 8 bytes of v at HERE in LE order.
\ Used for movabs imm64 in defining words and for 8-byte branch target slots.
: ,8
  dup ,4                                                 \ low 4 bytes
  [lit] 256 / [lit] 256 / [lit] 256 / [lit] 256 /        \ shift right 32
  ,4 ;                                                   \ high 4 bytes

```

## Try it

```forth
\ Increment a counter in gforth:
variable counter
counter @ .       \ 0
1 counter +!
counter @ .       \ 1
10 counter +!
counter @ .       \ 11
3 counter -!
counter @ .       \ 8
```

For `,4` and `,8`, you need a built seed-forth — gforth's `,` writes
a cell at a time and behaves slightly differently.  Test via the
`test-010-lib.fth` cases.

## Exercises

1. Define `,2 ( w -- )` that writes a 16-bit value in little-endian.
   Use it to write the ELF magic `0x457F` (note the byte order in
   the file is `7F 45`).

2. Why does `+!` use `over` rather than `dup swap`?  Both
   alternatives leave the same final stack — count tokens.

3. Trace `0x123456789ABCDEF0 ,8` byte by byte.  What sequence does
   HERE contain after the call?

4. The shift cascade `[lit] 256 / [lit] 256 / [lit] 256 / [lit] 256 /`
   takes 12 tokens.  A hypothetical `shr32 ( v -- v>>32 )` primitive
   would take 1.  Why didn't the seed authors add it?  (Hint: how
   often does `,8` actually run during a compiler build?)

## Takeaways

- `+!` and `-!` are the canonical Forth idiom for incrementing a
  cell.  Every counter in the C compiler uses them.
- `,4` and `,8` are little-endian by definition; the seed has no
  other endian convention.
- Right-shift by 8 is `[lit] 256 /`.  Right-shift by 32 is the
  same idea four times.  The codebase prefers this to adding a
  `shr` primitive.

Next: Chapter 10 — Immediacy and Constants.
