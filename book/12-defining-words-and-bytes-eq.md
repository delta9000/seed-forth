# Chapter 12 — `allot`, `create`, `variable`, `bytes-eq`

> **Status:** stub.  Canonical blocks below cover `010-lib.fth`
> lines 292–373 (end of file).  Prose goes between them.

## Goal

By the end of this chapter the reader can:

- explain the relationship between `create`, `variable`, and
  `constant` — they all share a 19-byte runtime body with different
  `imm64` payloads and different post-body data;
- use `allot` to extend a `create`d word's data area;
- read the loop-and-accumulate idiom used by `bytes-eq` to compare
  two byte ranges without short-circuiting.

## Source coverage

`010-lib.fth` lines 292–373 (end of file).  Five definitions:
`allot`, `create`, `variable`, `bytes-eq-flag` (a variable),
`bytes-eq`.

## Concepts introduced

- **`allot` as bump.**  `allot n` is `here-addr @ + here-addr !` —
  the same advance idiom we saw in `c,` but parameterised.
- **`create`'s runtime convention.**  A `create`d word pushes the
  address of the bytes *immediately following* its body.  Data area
  starts at `HERE + 9` because the body is `[18-byte prologue + 1
  ret] = 19` bytes from the `:` call, and at the moment of `,8`
  HERE points 9 bytes before the data area.
- **`variable` = `create , 0`.**  Pre-allots a single zero cell.
  Read the definition and notice it's `create`'s body plus a single
  `[lit] 0 ,`.
- **Loop-and-accumulate without short-circuit.**  `bytes-eq` cannot
  early-exit on mismatch because the seed has no `exit` primitive.
  Instead it accumulates the running flag in a variable and reads
  every byte.

## Concepts carried in

- All of Ch 10 (`constant`, the 19-byte runtime body, `:`/`state`).
- All of Ch 11 (`begin,`/`while,`/`repeat,`).
- `,8`, `c,`, `here`, `here-addr` from Chs 2 and 9.
- `>r`, `r>`, `over`, `c@`, `=`, `and`, `+`, `-` from earlier
  chapters.

## Concepts deferred

- *Use* of `bytes-eq` for symbol-table lookup — Part III, Ch 24
  (`070-cc-sym.fth`).
- The seed's `,` (comma) primitive that emits a full 8-byte cell —
  Part II, Ch 17.

## Section plan

1. **`allot` in one line.**  `here-addr @ + here-addr !` advances
   HERE by `n` without writing anything.  Used after `create` to
   reserve a buffer.
2. **`create`'s runtime body.**  Walk all eight `c,` calls + `,8` +
   final `c,`.  Same 19-byte prologue as `constant`, but the `imm64`
   slot holds `HERE + 9` (the address of where the data area will
   start).  At the moment of `,8`, HERE points at the first byte of
   the imm64 slot; after `,8` (8 bytes) + `[lit] 195 c,` (1 byte
   `ret`), HERE is exactly at the data area.
3. **`variable` = `create` + a cell.**  The definition is `create`'s
   body verbatim, followed by `[lit] 0 ,` (emit an 8-byte zero cell)
   before resetting STATE.  The defined word pushes the address of
   that zero cell.
4. **`bytes-eq`: comparison without `exit`.**  Walk the loop.  The
   accumulator starts as `-1` (true).  Each iteration ANDs in the
   byte-equality of the current pair.  When `u` hits zero, the
   variable holds the AND of all per-byte equalities.
5. **Why no early exit?**  The seed has no `exit` (and no `?dup
   exit`, no `r-drop`, no exception machinery).  Adding one would
   cost a primitive slot; for the C compiler's short identifier
   compares, the wasted work is negligible.

## Canonical source

```forth file=010-lib.fth
\ ===== Defining-words: allot / constant / variable / create =====
\ These let Forth code build named constants, variables, and arbitrary data
\ structures without escaping back into 000-seed.hex0.  All three of constant /
\ variable / create call the seed's `:` primitive to do the dirty work of
\ tokenizing the next input word and constructing a dictionary header (link,
\ flags=0, name-len, name bytes); then they hand-emit a 19-byte runtime body
\ and reset STATE=0 (since `:` left it at 1).

\ allot ( n -- )  Bump HERE by n bytes (no initialization).
\ Used after `create` to grow an array, or stand-alone for scratch buffers.
: allot  here-addr @ + here-addr ! ;

\ ----- runtime body shared by constant/variable/create -----
\ All three emit the same prologue: spill old TOS, load a new TOS via movabs.
\ The differences are what 64-bit value goes into the movabs imm64 slot,
\ and what (if anything) follows the `ret`.  Bytes:
\
\   48 83 ED 08          sub rbp, 8       ; make data-stack room
\   48 89 7D 00          mov [rbp+0], rdi ; spill old TOS
\   48 BF <imm64>        movabs rdi, V    ; load the value as the new TOS
\   C3                   ret
\
\ Total: 4 + 4 + 10 + 1 = 19 bytes.

\ (constant is defined earlier in this file, before the control-flow
\ combinators, so they can capture branch/0branch xts at load time.)

\ create ( -- )  Reads next token; defines a word that pushes the address of
\ the data area immediately following its body.  Caller fills the data area
\ via `,` / `c,` / `allot`.
\
\ At the moment `,8` is about to consume its argument, HERE points at the
\ first byte of the imm64 slot.  After `,8` (8 bytes) and the `ret` byte
\ (1 byte), HERE will point exactly at the data area — i.e. data-area-start
\ = HERE_now + 9.
: create
  :
  [lit] 72 c, [lit] 131 c, [lit] 237 c, [lit] 8 c,        \ sub rbp, 8
  [lit] 72 c, [lit] 137 c, [lit] 125 c, [lit] 0 c,        \ mov [rbp], rdi
  [lit] 72 c, [lit] 191 c,                                 \ movabs rdi prefix
  here [lit] 9 +                                           \ data-area starts 9 bytes ahead
  ,8                                                       \ imm64 = data-area address
  [lit] 195 c,                                             \ ret
  [lit] 0 state ! ;

\ variable ( -- )  Reads next token; defines a word that pushes the address
\ of an 8-byte cell (initialized to 0) embedded in the dictionary right after
\ the body.  Identical to `create` followed by `0 ,`, inlined here for
\ clarity (and to avoid depending on dispatch through `create`'s xt).
: variable
  :
  [lit] 72 c, [lit] 131 c, [lit] 237 c, [lit] 8 c,        \ sub rbp, 8
  [lit] 72 c, [lit] 137 c, [lit] 125 c, [lit] 0 c,        \ mov [rbp], rdi
  [lit] 72 c, [lit] 191 c,                                 \ movabs rdi prefix
  here [lit] 9 +                                           \ cell address = HERE+9
  ,8
  [lit] 195 c,                                             \ ret
  [lit] 0 ,                                                \ data cell, init 0 (8 bytes)
  [lit] 0 state ! ;

\ ===== bytes-eq =====
\ bytes-eq ( a1 a2 u -- f )  -1 if first u bytes at a1 match those at a2; 0 else.
\ Used by symbol-table name comparison and keyword recognition in the C
\ compiler.  Because the seed has no `exit` primitive, we cannot short-
\ circuit out of the loop on first mismatch.  Instead we accumulate the
\ still-equal flag in a variable and examine every byte.  This is O(u)
\ even on early mismatch, which is acceptable for the short names compared by
\ this compiler.
variable bytes-eq-flag
: bytes-eq
  [lit] 0 0= bytes-eq-flag !                     \ flag := -1 (assume equal)
  begin,
    dup [lit] 0 >
  while,
    >r                                           ( a1 a2  R-u )
    over c@ over c@ =                            ( a1 a2 byte-eq )
    bytes-eq-flag @ and bytes-eq-flag !          ( a1 a2 )
    [lit] 1 + swap [lit] 1 + swap                ( a1+1 a2+1 )
    r> [lit] 1 -                                  ( a1+1 a2+1 u-1 )
  repeat,
  drop drop drop                                  \ discard a1, a2, u(=0)
  bytes-eq-flag @ ;
```

## Try it

`create`/`variable`/`allot` exist in gforth; `bytes-eq` you can
paste in once `nand` / `[lit]` / our control-flow combinators are
present.  For a fast experiment:

```forth
\ gforth:
create buf  16 allot
65 buf c!   66 buf 1 + c!   67 buf 2 + c!
buf 3 type     \ prints "ABC"
```

For the seed-forth-only `bytes-eq`, build the seed and try the
assertions in `test-010-lib.fth`.

## Exercises

1. Why is `bytes-eq-flag` a *variable* (a shared cell) rather than a
   local on the data stack?  Trace the loop and explain what would
   go wrong if you tried to keep the flag on the data stack.

2. Define `2variable ( -- )` that defines a word pushing the address
   of a *two*-cell store.  Compare its emitted bytes to `variable`.

3. Define `string, ( c-addr u -- )` that copies `u` bytes from
   `c-addr` to HERE and advances HERE.  Use `create string, "Hello"`
   to build a named string blob.

4. The arithmetic-without-exit constraint forced O(n) compare even
   on mismatch.  How much extra work does that cost the C compiler
   in the worst case?  (Hint: longest identifier in the M2-Planet
   source; total `bytes-eq` calls per build.)

## Takeaways

- `create`, `variable`, and `constant` share a single 19-byte
  runtime body template.  They differ only in (a) what `imm64`
  goes into the `movabs` slot and (b) what (if anything) gets
  emitted after the `ret`.
- `allot` is the bump operator.  Combined with `create`, it
  builds arbitrary-shape data structures.
- Without an `exit` primitive, loops can't early-out.  The
  workaround — accumulate in a variable — is cheap enough for the
  C compiler's use case.

Next: Chapter 13 — The ELF and the Entry Point (Part II opens; we
leave `010-lib.fth` for `000-seed.hex0`).
