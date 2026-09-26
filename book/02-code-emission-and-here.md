# Chapter 2 — Code Emission and the HERE Pointer

```text
Missing capability: defining-words have no way to emit bytes into the dictionary at compile time.
New pattern: here-addr names the bump cursor; c, writes one byte and advances it (,4 and ,8 follow in Ch 9).
Artifact after this chapter: byte-level emission primitives every later library word reaches for.
Proof link: every byte the library hand-assembles passes through c,; the dictionary's tail is here-addr.
```

The seed can store a byte: `c!` takes a value and an address.  What
it cannot do is remember where the *next* byte goes.  Every word
Part I builds by hand (a constant's machine code, the CALL inside a
compiled `if,`, a variable's cell) is a run of bytes laid end to end,
and without "write here, then move on" each one would land on top of
the last.

In Forth those bytes go into the dictionary, one contiguous arena,
and the frontier of that arena is called `HERE`.  The first two
definitions after the file header (`010-lib.fth` lines 11–21) name
that frontier and push it forward.  `here-addr`
pushes the address of the HERE cell on the sysvar page; `c,`
("c-comma") stores one byte at HERE and bumps the cell by one.
Ch 13 covers the sysvar page itself, Ch 17 the `here` primitive, and
Ch 9 the multi-byte writers `,4` and `,8` built on `c,`.

## 1. Why a "HERE" exists at all

Forth keeps "the next byte to allocate" in a **sysvar** (system
variable), a cell in memory, and calls it `HERE`.  The reason is
structural: Forth's compiler is written in Forth.  When
`: foo ... ;` compiles a new word, it does not call a linker or a
loader.  It writes bytes into memory starting at `HERE` and advances
`HERE` past whatever it wrote.  Every defining word in the system
(`constant`, `create`, `variable`, the control-flow combinators of
Ch 11) works the same way.  If you understand `HERE` and the one word
that advances it, you understand how the whole compiler builds itself.

## 2. `here-addr` — a one-line preview of the [lit] convention

The HERE variable lives at a fixed address on the sysvar page.  To
update it, the code needs that address on the stack.

```forth
: here-addr  [lit] 4272144 ;            \ &HERE = 0x413010
```

`4272144` is the decimal form of `0x413010`, the address of the HERE
cell on the sysvar page.  The definition simply pushes that address
and returns.  There is no shuffling, no arithmetic, no lookup; it is
the simplest possible colon definition.

This is the `[lit]` convention from Ch 1 at work.  In a normal Forth
you would write `4272144` and the parser would push it.  This seed
does not auto-parse numbers in interpret mode (Ch 20 walks its
parser), so `[lit]` marks "the next token is a decimal literal; emit
code to push it."  Keep reading every `[lit] N` as "the number N".

The address itself is baked in.  The sysvar page layout is fixed in
`000-seed.hex0` and this literal must change if the layout ever moves.
That is the price of building a compiler before you have a symbol
table; Ch 13 shows the full map.

## 3. `c,` and the workhorse pattern

`c,` (pronounced "c-comma") stores one byte at HERE and bumps the
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
| 2    | `here-addr @` fetches the sysvar cell | stack: `A`                |
| 2    | `[lit] 1 +` adds one                 | stack: `A+1`              |
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
knowing where the cell lives, which is exactly what `here-addr`
encodes.

## 4. The big picture

`c,` emits one byte.  Almost every byte that `010-lib.fth` builds by
hand travels through it: every opcode in a `constant` or `create`
body, every `CALL` and rel32 that `comma-call` lays down in Ch 11.
The multi-byte cousins `,4` and `,8` just call `c,` four or eight
times.  The seed's own machine-code words are the
exception: `:` builds each dictionary header, the REPL lays down each
compiled `CALL`, `;` appends the `RET`, and `,` and `[lit]` store
their 8-byte cells, all by writing through the HERE cell directly.
They follow the same read-write-advance pattern; they just don't
call `c,`.  Part III's C compiler has its own emitter,
`cc-emit-byte`, which writes into an arena buffer rather than HERE,
but the idea is the same: one one-byte primitive at the bottom.

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

### The fast path: gforth

The snippet below uses only standard Forth words (`c!`, `create`,
`allot`, `variable`, `!`, `@`, `+`, `type`), so plain gforth runs it
without the playground shim.

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

`my-c,` mirrors the seed's `c,`: it reads a private pointer, stores
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
recognise) so `010-lib.fth` loads cleanly.  The first `echo` stores
three bytes with `c,`; the second reads each back with `c@` and
prints it with `emit`.  The seed should print `ABC`.

Three bytes just went into memory, one after another, through a word
the seed never had.  Every
constant, CALL, and branch slot in the chapters ahead is laid down
the same way.

## Exercises

1. **★ Trace.** After `[lit] 65 c, [lit] 66 c,`, what's at `here-addr @ - 2` and
   `here-addr @ - 1`?  Answer in two ASCII characters.

2. **★★ Trace.** Why does `c,` re-fetch `here-addr @` *after* the `c!` instead of
   reusing the value pushed by `here` on the first line?  (Hint:
   `here` is a primitive that pushes the *contents* of the HERE cell;
   `here-addr` pushes the address.)

3. **★★ Extend.** Write `2c,` ( w -- ) that stores the low *two* bytes of TOS at HERE
   in little-endian order.  Compare yours to `,4` when we meet it in
   Chapter 9.

4. **★★ Trace.** The expression `[lit] 4272144` is 0x413010.  What sits at 0x413000,
   0x413008, 0x413018, 0x413020, 0x413028?  (You can answer from the
   memory map in [Appendix A2](A2-memory-map.md); the full breakdown is
   Ch 13.)

## Takeaways

- `c,` stores a byte at HERE and advances HERE, and every byte the
  library emits by hand passes through it (the seed's own `:`, `;`,
  `,`, and `[lit]` write HERE directly).
- `here-addr` hard-codes the HERE cell's address on the sysvar page,
  so it must change in lockstep with any layout change in
  `000-seed.hex0`.
- Forth's compiler is not a separate program but a chain of words
  that write at HERE, a shape the Part III C compiler repeats with
  its own emitter.

**Part I tally.**  Built so far: **byte emission** (`c,`).  Still
missing: `and`, `-`, `<`, `if,`, `variable`.

Next: Chapter 3 — Logic from One Primitive.  The seed's only logic
operation is `nand`: no `and`, no `or`, no `not`.  Ch 3 asks whether
one operation is enough, and builds `and` from it in three words.