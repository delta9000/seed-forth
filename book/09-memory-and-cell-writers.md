# Chapter 9 — Memory Updates and Cell Writers

```text
Missing capability: no compound updates or multi-byte writers on top of @ and !.
New pattern: read-modify-write helpers and little-endian byte writers built on the primitive store.
Artifact after this chapter: +!, -!, ,4, ,8.
Proof link: the C compiler bumps counters via +!; its ELF + code emission flow through ,4 / ,8 analogues.
```

Ch 2's `c,` writes one byte, but machine code is mostly wider than
that.  Every `CALL` carries a 4-byte rel32 offset, and every
`movabs` carries an 8-byte immediate.  Before the library can build
defining words (Chs 10 and 12), it needs to write those values at
HERE in little-endian order, and the seed has no shift instruction
to split them into bytes.

So how do you get byte 2 of `0xAABBCCDD` with no `>>`?
`010-lib.fth` lines 155–178 answer with four words.  `+!` and `-!`
are the read-modify-write on a cell, Forth's `*addr += n`, which the
C compiler uses for every counter.  `,4` and `,8` are the
little-endian writers, and §2 shows what they use in place of a
shift.

## 1. `+!` and `-!`: idiomatic increment

```forth
: +!  swap over @ + swap ! ;
: -!  swap over @ swap - swap ! ;
```

`+! ( n addr -- )` adds `n` to the 64-bit cell at `addr`.  It is the
Forth equivalent of `*addr += n;` in C.

Trace with input `( n addr -- )`:

| token  | stack                  | reasoning                       |
|--------|------------------------|---------------------------------|
| (in)   | `n addr`               |                                 |
| `swap` | `addr n`               | get addr underneath             |
| `over` | `addr n addr`          | copy addr to the top            |
| `@`    | `addr n cell-value`    | fetch the old cell value        |
| `+`    | `addr (n+cell-value)`  | compute the new value           |
| `swap` | `(n+cell-value) addr`  | get addr back on top            |
| `!`    | empty                  | store the new value at addr     |

Six tokens consume the input pair and leave the stack empty,
having modified one cell in memory.  Every counter in the C compiler
(token count, symbol count, scope depth) is incremented via `+!`.

`-!` is the mirror image.  The only difference is that subtraction
isn't commutative, so the argument order needs care.  We want
`*addr -= n`, which is `*addr = *addr - n`, *not* `n - *addr`.  The
extra `swap` before the `-` puts the cell value on top so `-` sees
`( cell-value n -- )` and produces `cell-value - n`:

| token  | stack                       |
|--------|-----------------------------|
| (in)   | `n addr`                    |
| `swap` | `addr n`                    |
| `over` | `addr n addr`               |
| `@`    | `addr n cell-value`         |
| `swap` | `addr cell-value n`         |
| `-`    | `addr (cell-value-n)`       |
| `swap` | `(cell-value-n) addr`       |
| `!`    | empty                       |

One extra `swap` is the price of non-commutativity.  Notice that
**`+!` exists in standard Forth but `-!` does not**; most Forths
expect you to write `negate swap +!` or just inline the steps.  The
seed adds `-!` as a small convenience.  The C compiler uses it five
times, every one a decrementing counter: four nesting depths (scope,
`#include`, and two parenthesis-depth trackers) and one
bytes-remaining count.

## 2. `,4` and `,8`: cell-sized emission

`,4` and `,8` build on `c,` from Ch 2.  They add no primitive,
just an unrolled multi-byte loop.

```forth
: ,4
  dup c,                       \ byte 0
  [lit] 256 / dup c,           \ byte 1
  [lit] 256 / dup c,           \ byte 2
  [lit] 256 / c, ;             \ byte 3
```

Trace on input `( v -- )` for a 32-bit value `v = 0xAABBCCDD`:

| token         | stack         | byte emitted at HERE |
|---------------|---------------|----------------------|
| (in)          | `0xAABBCCDD`  |                       |
| `dup`         | `0xAABBCCDD 0xAABBCCDD` |                |
| `c,`          | `0xAABBCCDD`  | `0xDD` (low byte)    |
| `[lit] 256 /` | `0x00AABBCC`  |                       |
| `dup`         | `0x00AABBCC 0x00AABBCC` |                |
| `c,`          | `0x00AABBCC`  | `0xCC`               |
| `[lit] 256 /` | `0x0000AABB`  |                       |
| `dup`         | `0x0000AABB 0x0000AABB` |                |
| `c,`          | `0x0000AABB`  | `0xBB`               |
| `[lit] 256 /` | `0x000000AA`  |                       |
| `c,`          | empty         | `0xAA` (high byte)   |

Four bytes written at HERE, in order `DD CC BB AA`: the
little-endian representation of `0xAABBCCDD`.  Each iteration emits
the current low byte (via `c,`, which only uses the low 8 bits of
TOS), then shifts right by 8 (via `[lit] 256 /`), and repeats.

```forth
: ,8
  dup ,4                                                 \ low 4 bytes
  [lit] 256 / [lit] 256 / [lit] 256 / [lit] 256 /        \ shift right 32
  ,4 ;                                                   \ high 4 bytes
```

`,8` is two `,4`s with a 32-bit right-shift in between.  The first
`,4` emits bytes 0–3 (low half); the four `[lit] 256 /` calls shift
the high half down to where `,4` can see it; the second `,4` emits
bytes 4–7.  Eight bytes total, little-endian.

## 3. Why divide by 256?

There is no `>>` in this seed, and the closest thing to a shift
that Forth code can reach is division.  Dividing by 256 is
identical to shifting right by 8 (because `2^8 == 256`), and the
seed's `/` is the x86 `DIV` instruction.

On modern CPUs `DIV` takes 20–40 cycles against 1 for `SHR`.  That
doesn't matter here: `,8` runs a few hundred times during a compiler
build.  A `>>8` or `>>32` primitive would cost a slot, a dictionary
header, and 10–20 bytes of machine code, so the trade is Ch 3's
again: save a primitive, pay cycles on a cold path.

## 4. The shift-by-32 cascade

The middle line of `,8`:

```forth
  [lit] 256 / [lit] 256 / [lit] 256 / [lit] 256 /
```

is ugly to read but trivially correct.  Each `/256` is `>>8`; four
of them is `>>32`.  After the cascade, the value on TOS has been
right-shifted by 32 bits: the original high 32 bits are now in the
low 32 bits, ready for the second `,4`.  The original low 32 bits
are gone (already written out by the first `,4`).

When reading, treat the four `[lit] 256 /` as one operation, "shift
right by 32".  The C compiler's `cc-emit-8le` (Ch 21) uses the same
cascade for every `imm64` it emits in a `movabs` instruction.

## 5. Where these are used

`,4` and `,8` look general, but in the library they serve two
specific clients:

- **`,4` ← `call,` in Ch 10.**  Every 5-byte `CALL` instruction
  is `E8` followed by a 4-byte `rel32`.  `call,` emits the `E8`
  with `c,` and the offset with `,4`.

- **`,8` ← `constant` in Ch 10; `create`, `variable` in Ch 12.**
  Each of these defining words emits a 19-byte runtime body that
  ends with `movabs rdi, imm64`; the `imm64` is written with `,8`.

Nothing else calls them: `,4` and `,8` appear nowhere in the C
compiler's source (`020`–`130`).  The compiler writes into its own
output buffer, not HERE, so it carries its own copies of the same
shape (`cc-emit-4le` and `cc-emit-8le` on top of `cc-emit-byte`,
Ch 21), and its ELF emitter (Ch 25) lays down 32-bit
program-header fields with those.

## Canonical source

```forth file=010-lib.fth
\ ===== Memory update helpers =====

\ +! ( n addr -- )  add n to the cell at addr.
: +!  swap over @ + swap ! ;

\ -! ( n addr -- )  subtract n from the cell at addr.
: -!  swap over @ swap - swap ! ;

\ ===== 4-byte little-endian writer =====
\ ,4 ( v -- )  emit low 4 bytes of v at HERE in LE order.
\ Used by call, (rel32) and any Forth-level code emitter that needs
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

### The fast path: gforth

The playground's `,4` and `,8` aren't the seed's (gforth's `,` is
cell-sized and doesn't match), but `+!` and `-!` work fine: `+!` is
standard, and we just define `-!` locally.  Save as `/tmp/ch9.fth`:

```forth
: -!  swap over @ swap - swap ! ;
variable counter
." init: " counter @ . cr        \ 0
1  counter +!  ." +1:  " counter @ . cr        \ 1
10 counter +!  ." +10: " counter @ . cr        \ 11
3  counter -!  ." -3:  " counter @ . cr        \ 8
bye
```

Run: `gforth book/playground.fth /tmp/ch9.fth`.  Expected:

```
init: 0
+1:  1
+10: 11
-3:  8
```

### The full path: build the seed

To see `,8` in action, write a hand-picked 64-bit value at HERE and
read the bytes back:

```sh
./build.sh
{ cat 010-lib.fth
  echo 'here [lit] 72623859790382856 ,8'        # 0x0102030405060708
  echo 'here [lit] 8 -  c@ [lit] 48 + emit'     # byte 0 = 0x08 -> '8'
  echo 'here [lit] 7 -  c@ [lit] 48 + emit'     # byte 1 = 0x07 -> '7'
  echo 'here [lit] 6 -  c@ [lit] 48 + emit'
  echo 'here [lit] 5 -  c@ [lit] 48 + emit'
  echo 'here [lit] 4 -  c@ [lit] 48 + emit'
  echo 'here [lit] 3 -  c@ [lit] 48 + emit'
  echo 'here [lit] 2 -  c@ [lit] 48 + emit'
  echo 'here [lit] 1 -  c@ [lit] 48 + emit'     # byte 7 = 0x01 -> '1'
} | ./seed-forth
```

Expected output: `87654321`.  The decimal `72623859790382856` is
`0x0102030405060708`; `,8` emits its bytes in little-endian order
(`08 07 06 05 04 03 02 01`); adding 48 to each byte produces ASCII
`'8' '7' '6' '5' '4' '3' '2' '1'`.  To reach that final `1`, the
value was shifted right 56 bits by seven divisions, on a machine
with no shift.

## Exercises

1. **★★ Extend.** Define `,2 ( w -- )` that writes a 16-bit value in little-endian.
   Use it to write `0x457F` (the first two bytes of the four-byte ELF
   magic `7F 45 4C 46`); note the byte order in the file is `7F 45`.

2. **★ Trace.** Why does `+!` use `over` rather than `>r dup r> swap`?
   Both leave the same final stack — count tokens.

3. **★★ Trace.** Trace `0x123456789ABCDEF0 ,8` byte by byte.  What sequence does
   HERE contain after the call?

4. **★★ Extend.** `,4` takes a number apart with `[lit] 256 /`.
   Put one back together: write `4c@ ( addr -- n )` that reads four
   little-endian bytes with `c@`, using `[lit] 256 *` where a machine
   with shifts would shift left.  Check the round trip on the seed:
   `here [lit] 1094861636 ,4 4c@ [lit] 1094861636 = 0= [lit] 49 + emit`
   should print `1`.  Which byte do you have to read first, and
   why?

## Takeaways

- `+!` and `-!` update a cell in place, and every counter in the C
  compiler goes through them.
- `,4` and `,8` write values at HERE low byte first, one `c,` per
  byte.
- With no shift primitive, a right shift by 8 is `[lit] 256 /`, and
  a shift by 32 is that four times.

**Part I tally.**  Built so far: byte emission, Boolean logic,
subtraction, file I/O, character tests, comparisons, shuffles,
**counters and 4- and 8-byte writes**.  Still missing: `constant`,
`if,`, `variable`.

Next: Chapter 10 — Immediacy and Constants.  The library can now lay
down any byte sequence at HERE, including x86 machine code.  Ch 10
uses that to write a word that writes words: `constant`, which
hand-assembles 19 bytes of x86-64 for every constant you define.
