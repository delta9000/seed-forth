# Chapter 2 — Code Emission and the HERE Pointer

> **Status:** ✅ complete.  Prose covers every section-plan beat; both
> Try-it paths (gforth and seed-forth) verified.  Canonical blocks
> cover `010-lib.fth` lines 9–21.

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

---

A Forth dictionary is a single contiguous arena of bytes.  When you
define a word, when the compiler emits a machine instruction, when
`create` reserves space for a variable — all of them are appending
bytes to one growing region.  The frontier is called `HERE`, and the
first two definitions in `010-lib.fth` exist to name that frontier and
to push it forward one byte at a time.

## 1. Why a "HERE" exists at all

Every high-level language has a name for "the next byte to allocate."
In C it's whatever `malloc` returns.  In assembly it's implicit in the
program counter or the link register.  Forth makes it explicit as a
system variable — a cell in memory — and calls it `HERE`.

The reason is structural: Forth's compiler is written in Forth.  When
`: foo ... ;` compiles a new word, it does not call a linker or a
loader.  It writes bytes into memory starting at `HERE` and advances
`HERE` past whatever it wrote.  Every defining word in the system —
`constant`, `create`, `variable`, the control-flow combinators of Ch
11 — works the same way.  If you understand `HERE` and the one word
that advances it, you understand how the whole compiler builds itself.

## 2. `here-addr` — a one-line preview of the [lit] convention

The HERE variable lives at a fixed address on the sysvar page.  To
update it, the code needs that address on the stack.

```forth
: here-addr  [lit] 4272144 ;            \ &HERE = 0x413010
```

`4272144` is `0x413010` in decimal — the address of the HERE cell on
the sysvar page.  The definition simply pushes that address and
returns.  There is no shuffling, no arithmetic, no lookup; it is the
simplest possible colon definition after the file header.

The `[lit]` word is the seed's explicit literal compiler.  In a normal
Forth you would write `4272144` and the parser would push it.  This
seed does not auto-parse numbers in interpret mode (that is Ch 20's
job), so it uses `[lit]` as a compile-time marker that says "the next
token is a decimal literal; emit code to push it."  Read every
`[lit] N` in the codebase as "the number N" and you will not go wrong.

The address itself is baked in.  The sysvar page layout is fixed in
`000-seed.hex0` and this literal must change if the layout ever moves.
That is the price of building a compiler before you have a symbol
table; Ch 13 shows the full map.

## 3. `c,` and the workhorse pattern

`c,` (pronounced "comma") stores one byte at HERE and bumps the
pointer.  It is the fundamental building block of every word that
emits code.

```forth
: c,
  here c!                                 \ *HERE = byte
  here-addr @ [lit] 1 + here-addr !       \ HERE += 1
;
```

Trace it with `( b -- )`, assuming HERE currently points at address
`A`:

| line | action                              | result                     |
|------|--------------------------------------|----------------------------|
| 1    | `here` pushes the *contents* of HERE | stack: `b A`               |
| 1    | `c!` stores low byte of TOS at `A`   | byte `b` written; stack: empty |
| 2    | `here-addr @` fetches the sysvar cell | stack: `0x413010`         |
| 2    | `[lit] 1 +` adds one                 | stack: `0x413011`         |
| 2    | `here-addr !` stores it back         | HERE cell now holds `A+1` |

The pattern repeats wherever code is emitted: read the pointer, write
the data, re-fetch the pointer address, increment, store.  It is a
manual read-modify-write sequence that a higher-level word (`+!` in Ch
9) will collapse into one call.

Why does line 2 re-fetch `here-addr @` instead of reusing the address
from line 1?  Because `here` pushes the value of the HERE cell (the
current pointer), while `here-addr` pushes the address of that cell.
They are different numbers.  You need the address of the cell to write
back to it, and you cannot produce it from the pointer value without
knowing where the cell lives — which is exactly what `here-addr`
encodes.

## 4. The big picture

`c,` emits one byte.  Every byte in every dictionary header, every
opcode in every colon definition, every absolute address in every
`constant` body, every rel32 offset in a branch instruction inside
the Forth itself travels through `c,` (or one of its multi-byte cousins
`,4` and `,8`, which call `c,` four or eight times).  Part III's C
compiler runs a parallel emission path of its own — its `cc-emit-byte`
writes into an arena buffer rather than HERE — but the *idea* is the
same: a single one-byte primitive at the bottom of the world.  This is
the first word after the file header because it is the word everything
else in `010-lib.fth` builds on.

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

All words used below (`c!`, `create`, `allot`, `variable`, `!`, `@`,
`1 +`, `type`) are standard Forth.  No shim needed.

### The fast path: gforth

```sh
gforth
```

Paste or type at the REPL:

```forth
create scratch  16 allot
variable my-here
scratch my-here !

: my-c,  my-here @ c!  my-here @ 1 +  my-here ! ;

65 my-c,  66 my-c,  67 my-c,
scratch 3 type   \ prints "ABC"
```

`my-c,` mirrors the seed's `c,` — it reads a private pointer, stores
a byte, increments the pointer, and writes it back.  The three
literals 65, 66, 67 (ASCII `A`, `B`, `C`) land at `scratch`, and
`type` prints them.

### The full path: build the seed

```sh
./build.sh
{ sed -e 's/\\.*$//' -e 's/([^)]*)//g' 010-lib.fth
  echo 'here [lit] 65 c, [lit] 66 c, [lit] 67 c,'
  echo 'here [lit] 3 - c@ emit  here [lit] 2 - c@ emit  here [lit] 1 - c@ emit'
} | grep -v '^[[:space:]]*$' | ./seed-forth
```

The `sed` strips Forth comments (which the seed's tokenizer does not
recognise) so `010-lib.fth` loads cleanly.  The second `echo` appends
the test snippet: store three bytes with `c,`, then read each back
with `c@` and print it with `emit`.  The seed should print `ABC`.

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

- Every byte the Forth system emits — every dictionary header, every
  machine instruction inside a colon definition, every cell in a
  `create`d array — passes through `c,`.
- The sysvar page at 0x413000 is hard-coded throughout `010-lib.fth`
  by absolute address.  When 000-seed.hex0 changes layout, those
  literals must be updated in lockstep.
- Forth's "compiler" is not a separate program.  It is a chain of
  Forth words that ultimately call `c,`.  The C compiler in Part III
  follows the same shape with its own emitter.

Next: Chapter 3 — Logic from One Primitive, where we use `nand` (and
nothing else) to build the full Boolean vocabulary.