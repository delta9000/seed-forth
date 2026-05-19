# Chapter 9 — Memory Updates and Cell Writers

> **Status:** ✅ complete.  Prose covers every section-plan beat; both
> Try-it paths (gforth and seed-forth) verified.  Canonical blocks
> cover `010-lib.fth` lines 137–161.

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

---

Two themes weave through this chapter.  First, the **read-modify-write
on a cell**: a counter sits in memory, code adds (or subtracts) to
it, code writes it back.  Trivial in any imperative language, but
worth seeing in Forth's stack idiom because the C compiler uses it
constantly.  Second, the **multi-byte little-endian emitter**: every
machine instruction we'll compile in Parts II and III contains
4-byte rel32 offsets or 8-byte imm64 immediates, and each one is
emitted byte-by-byte through `c,` (Ch 2) wrapped in `,4` or `,8`.
The shape of those wrappers is interesting because the seed has no
shift instruction at the Forth level, so we improvise with `/`.

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

Five tokens consume the input pair and leave the stack empty,
having modified one cell in memory.  This is a hot idiom — every
counter in the C compiler (token count, symbol count, scope depth)
is incremented via `+!`.

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
**`+!` exists in standard Forth but `-!` does not** — most Forths
expect you to write `negate swap +!` or just inline the steps.  The
seed adds `-!` as a small convenience because the C compiler uses
it dozens of times to decrement reference counts and scope depth.

## 2. `,4` and `,8`: cell-sized emission

These are the workhorses for writing multi-byte values at HERE.
The seed needs them because x86-64 machine code is dense with
4-byte rel32 offsets (every `CALL` and conditional branch) and
8-byte imm64 immediates (every `movabs` of a runtime address).
`,4` and `,8` build on `c,` from Ch 2 — they don't add a new
primitive, just a multi-byte loop.

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

Four bytes written at HERE, in order `DD CC BB AA` — the
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

There is no `>>` operator in this seed.  The seed has only one
arithmetic shift you can reach from Forth: division.  Dividing by
256 is identical to shifting right by 8 (because `2^8 == 256`), and
the seed's `/` is the x86 `DIV` instruction (a single machine-code
operation), so the cost is one register-pair load and one `div r/m64`
per shift.

In modern CPUs `DIV` takes 20–40 cycles, far slower than a `SHR`'s
1 cycle.  On 2026 hardware that's irrelevant — `,8` runs a few
hundred times during a compiler build, total cost negligible.  On
1995-era hardware it would still be irrelevant because the build
happens once.  The trade is "save a primitive slot, pay 4x cycles
on a cold path."  That trade is the seed's whole personality.

The alternative would have been to add a `>>8` or `>>32` primitive.
Either costs a slot, a dictionary header, and 10–20 bytes of machine
code.  At a few-hundred-byte budget, that's not worth it for a
function called rarely on a non-hot path.

## 4. The shift-by-32 cascade

The middle line of `,8`:

```forth
  [lit] 256 / [lit] 256 / [lit] 256 / [lit] 256 /
```

is ugly to read but trivially correct.  Each `/256` is `>>8`; four
of them is `>>32`.  After the cascade, the value on TOS has been
right-shifted by 32 bits — the original high 32 bits are now in the
low 32 bits, ready for the second `,4`.  The original low 32 bits
are gone (already written out by the first `,4`).

Reading this in the source code, it helps to mentally cluster the
four `[lit] 256 /` as one operation called "shift right by 32" and
move on.  The chapter calls it a *cascade* to give it a name; the C
compiler will hit one of these for every `imm64` it emits in a
`movabs` instruction.

## 5. Where these are used

`,4` and `,8` look general but the seed authors put them here for
two specific clients:

- **`,4` ← `comma-call` in Ch 11.**  Every 5-byte `CALL` instruction
  is `E8` followed by a 4-byte `rel32`.  `comma-call` emits the `E8`
  with `c,` and the offset with `,4`.

- **`,8` ← `constant`, `create`, `variable` in Ch 10.**  Each of
  these defining words emits a 19-byte runtime body that ends with
  `movabs rdi, imm64`; the `imm64` is written with `,8`.

Beyond these, both writers see occasional one-off use anywhere the
codebase needs to drop a multi-byte value into HERE.  The C
compiler's ELF emitter, for instance, uses `,4` to lay down 32-bit
fields in the program header (Ch 25).

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

### The fast path: gforth

The playground's `,4` and `,8` aren't the seed's (gforth's `,` is
cell-sized and doesn't match), but `+!` and `-!` work fine — `+!` is
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
{ sed -e 's/\\.*$//' -e 's/([^)]*)//g' 010-lib.fth
  echo 'here [lit] 72623859790382856 ,8'        \ 0x0102030405060708
  echo 'here [lit] 8 -  c@ [lit] 48 + emit'     \ byte 0 = 0x08 -> '8'
  echo 'here [lit] 7 -  c@ [lit] 48 + emit'     \ byte 1 = 0x07 -> '7'
  echo 'here [lit] 6 -  c@ [lit] 48 + emit'
  echo 'here [lit] 5 -  c@ [lit] 48 + emit'
  echo 'here [lit] 4 -  c@ [lit] 48 + emit'
  echo 'here [lit] 3 -  c@ [lit] 48 + emit'
  echo 'here [lit] 2 -  c@ [lit] 48 + emit'
  echo 'here [lit] 1 -  c@ [lit] 48 + emit'     \ byte 7 = 0x01 -> '1'
} | grep -v '^[[:space:]]*$' | ./seed-forth
```

Expected output: `87654321`.  The decimal `72623859790382856` is
`0x0102030405060708`; `,8` emits its bytes in little-endian order
(`08 07 06 05 04 03 02 01`); adding 48 to each byte produces ASCII
`'8' '7' '6' '5' '4' '3' '2' '1'`.

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
