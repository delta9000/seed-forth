# Chapter 12 — `allot`, `create`, `variable`, `bytes-eq`

```text
Missing capability: the library lacks variable storage and byte-comparison helpers.
New pattern: create + allot for data areas; a flag-accumulating bytes-eq loop (the seed has no exit).
Artifact after this chapter: allot, create, variable, bytes-eq — 010-lib.fth is now complete.
Proof link: macro (Ch 22) and symbol (Ch 24) lookup compare names via bytes-eq; every fixed compiler table is a create/allot buffer.
```

Where does a compiler written in this library keep its line number?
`constant` names a value that never changes, and the data stack
forgets everything the moment a word returns.  The compiler needs
named *storage*: counters, buffers, tables.  And when it meets the
identifier `main`, it needs to ask whether those four bytes match a
name it has seen before, with no string type and no early `return`.

The last 90 lines of `010-lib.fth` (295–384) supply both.  `allot`
bumps HERE by a byte count.  `create` reuses Ch 10's 19-byte runtime
body but makes it push the address of a data area that follows the
body.  `variable` is `create` with one zero cell already in place.
Together they cover every static-memory pattern the C compiler
needs.  Finally, `bytes-eq` compares two byte ranges; because the
seed has no `exit` primitive, it cannot stop at the first mismatch.
Its callers are the macro and symbol lookups of Chs 22 and 24.  The
seed's `,` primitive, which `variable` uses to lay down its zero
cell, is Ch 17.

## 1. `allot` in one line

```forth
: allot  here-addr @ + here-addr ! ;
```

`allot ( n -- )` advances HERE by `n` bytes without writing
anything.  The body is the same read-modify-write idiom we met in
`c,` (Ch 2), but parameterised: fetch the HERE cell, add `n`, store
it back.

Trace it:

| token         | stack                       |
|---------------|-----------------------------|
| (in)          | `n`                         |
| `here-addr`   | `n addr-of-HERE`            |
| `@`           | `n current-HERE`            |
| `+`           | `current-HERE+n`            |
| `here-addr`   | `current-HERE+n addr-of-HERE` |
| `!`           | empty (HERE := current+n)   |

`allot` writes nothing, so the new region holds whatever was
already in memory.  After `create FOO`, `[lit] 16 allot` reserves a
16-byte data area you are expected to fill before reading.  In
practice the region is fresh memory the kernel zeroed, so the seed
never needs an explicit clear.

One more HERE move lives next to `allot`.  `skip-vm-pages` jumps
HERE forward past the seed's fixed pages (the data stack, the I/O
scratch byte, the token buffer and the sysvar page), so that the C
compiler's megabyte buffers (Ch 21) cannot overlap them:

```forth
: skip-vm-pages  state [lit] 4096 + here-addr ! ;
```

The sysvar page starts at STATE's cell, `0x413000`, so the page
above it starts 4096 bytes later, at `0x414000`.  Like `here-addr`
(Ch 2), it derives the address from what the seed exports instead
of typing it in.

## 2. `create`'s runtime body

`create` defines a word that, when later invoked, pushes the
address of the bytes immediately following its body.  Mechanically
it builds the same 19-byte template `constant` did (Ch 10), but the
`imm64` is a *computed* address: the address of the data area
itself.

```forth
: create
  :
  [lit] 72 c, [lit] 131 c, [lit] 237 c, [lit] 8 c,        \ sub rbp, 8
  [lit] 72 c, [lit] 137 c, [lit] 125 c, [lit] 0 c,        \ mov [rbp], rdi
  [lit] 72 c, [lit] 191 c,                                 \ movabs rdi prefix
  here [lit] 9 +                                           \ data-area starts 9 bytes ahead
  ,8                                                       \ imm64 = data-area address
  [lit] 195 c,                                             \ ret
  [lit] 0 state ! ;
```

The interesting line is **`here [lit] 9 +`**.  At the moment that
line runs, HERE has already advanced past the prologue's first 10
bytes (`4 + 4 + 2 = 10`).  Now it sits at the first byte of the
imm64 slot itself.

The `imm64` is 8 bytes wide, and after that we'll write 1 more byte
(the `ret`).  So the address of the byte *after* `ret`, which is
where the data area begins, is `HERE_now + 8 + 1 = HERE_now + 9`.

`here [lit] 9 +` computes that future address, and `,8` writes it
into the imm64 slot.  When the resulting word runs, it pushes its
own data-area address.

After `create FOO`, FOO's dictionary entry looks like:

```
[link][flags=0][name-len][name]
[19-byte runtime body, imm64 = data-area-addr]
[data area: empty, sized by subsequent allot/c,/,/,8 calls]
```

The data area sits in the dictionary, contiguous with the body, so
there is no separate allocator, no fixup, and no pointer
indirection.  You name a thing, then you fill in its bytes.

## 3. `variable` = `create` + a cell

```forth
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
```

Compare line by line to `create`: identical, except for one extra
line just before resetting STATE, **`[lit] 0 ,`**, which pre-fills
the first 8 bytes of the data area with a zero cell.  After
`variable COUNTER`, COUNTER is a word that pushes the address of a
zero-initialised 8-byte cell.

In principle you could implement `variable` as `: variable  create
[lit] 0 , ;`, calling `create` and then appending the zero cell
with `,`.  The library inlines the body for two reasons.  First, it
avoids depending on dispatch through `create`'s execution token
(`create` is defined just a few lines earlier, but
forward-referencing makes the layout fragile).  Second, the inlined
form is *exactly* what `constant` and `create` already do, so the
reader sees the same template three times in a row and understands
the shared shape.

Read side by side, Ch 10's `constant` and this chapter's `create`
and `variable` are variations on one 19-byte template, differing
only in (a) which 64-bit value goes into the `movabs` slot, and (b)
what (if anything) follows the `ret`.

| Word       | imm64                | post-body data         |
|------------|----------------------|------------------------|
| `constant` | the user's value     | nothing                |
| `create`   | the data-area addr   | nothing (user fills via `allot`/`c,`/`,`) |
| `variable` | the data-area addr   | one 8-byte zero cell   |

## 4. `bytes-eq`: comparison without `exit`

The last word in `010-lib.fth` is a byte-by-byte memory comparator.

```forth
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

`bytes-eq ( a1 a2 u -- f )` returns `-1` if the first `u` bytes at
`a1` equal those at `a2`, else `0`.  The structure is a standard
counted loop, with two unusual details.

**Initialisation.**  `[lit] 0 0= bytes-eq-flag !` is "set the flag
to `-1`."  `[lit] 0` pushes zero; `0=` converts it to `-1`; `!`
stores that into the flag variable.  The roundabout `0 0=` instead
of writing `-1` directly is because the seed's decimal-literal
parser is unsigned-only (you can't write `-1` as a literal), so we
fabricate it via zero-test.

**Per-iteration accumulation.**  Inside the loop:

| token                     | stack          | what happens                                |
|---------------------------|----------------|---------------------------------------------|
| `>r`                      | `a1 a2`        | park `u` on the return stack                |
| `over c@`                 | `a1 a2 *a1`   | fetch byte at `a1`                         |
| `over c@`                 | `a1 a2 *a1 *a2` | fetch byte at `a2`                        |
| `=`                       | `a1 a2 byte-eq` | compare the two bytes                     |
| `bytes-eq-flag @`         | `a1 a2 byte-eq prev-flag` | fetch running flag             |
| `and`                     | `a1 a2 new-flag` | AND in the per-byte equality            |
| `bytes-eq-flag !`         | `a1 a2`        | store the running flag back                |
| `[lit] 1 + swap [lit] 1 +` | `a2+1 a1+1`   | advance both pointers                       |
| `swap`                    | `a1+1 a2+1`   | restore order                              |
| `r>`                      | `a1+1 a2+1 u` | recover `u` from return stack              |
| `[lit] 1 -`               | `a1+1 a2+1 u-1` | decrement                                 |

When the loop exits (`u` reaches zero), `bytes-eq-flag` holds the
AND of all per-byte equality flags.  If any byte mismatched, that
iteration produced `0`; ANDing zero into the accumulator zeros it
permanently.  If all bytes matched, the accumulator stays `-1`.

After the loop, `drop drop drop` clears the loop residue (`a1+u`,
`a2+u`, and the final zero `u`), and `bytes-eq-flag @` returns the
result.

## 5. Why no early exit?

With `break` or `return`, this loop would stop at the first
mismatch.  Forth's equivalent is `exit`, and the seed doesn't have
it.  Adding it would cost a primitive slot, roughly 15 bytes of
machine code, and a dictionary entry, to speed up exactly one word.
The C compiler calls `bytes-eq` thousands of times, but on short
identifiers (typically 1–12 bytes), so reading every byte costs
microseconds per compilation.  Ch 3's trade again: save a primitive,
pay a small constant cost.

A side effect: `bytes-eq` takes the same time wherever the mismatch
falls.  In a security context that is a constant-time compare; here
it is incidental.

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

\ skip-vm-pages ( -- )  Jump HERE to the first page above the seed's fixed VM
\ pages: data stack (below 0x411000), I/O scratch byte (0x412000), token
\ buffer (0x412800) and the sysvar page, which starts at STATE's cell.  So
\ HERE becomes STATE + 4096 = 0x414000.  030-cc-io.fth and 130-asm.fth call
\ it before creating their megabyte buffers, which then cannot overlap VM
\ state.  HERE must still be below the data stack (0x410000) when it runs.
: skip-vm-pages  state [lit] 4096 + here-addr ! ;

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

### `create`/`allot`: gforth works

`create` and `allot` are standard.  In gforth:

```forth
create buf  16 allot
65 buf c!   66 buf 1 + c!   67 buf 2 + c!
buf 3 type     \ prints "ABC"
```

`type ( c-addr u -- )` is gforth's built-in "print `u` bytes from
`c-addr`."  The seed has no `type`; it has `emit` for one byte at a
time.  See the seed test below for the equivalent.

### `create`/`allot` and `bytes-eq` in the seed

```sh
./build.sh
{ cat 010-lib.fth
  echo 'create buf  [lit] 65 c, [lit] 66 c, [lit] 67 c,'
  echo 'buf c@ emit  buf [lit] 1 + c@ emit  buf [lit] 2 + c@ emit'
} | ./seed-forth
```

Expected: `ABC`.  `create buf` defines a word; the three `c,` calls
write `A`, `B`, `C` into its data area.  Then we read each byte
back and emit.

For `bytes-eq`:

```sh
{ cat 010-lib.fth
  echo 'create a  [lit] 72 c, [lit] 73 c, [lit] 0 c,'
  echo 'create b  [lit] 72 c, [lit] 73 c, [lit] 0 c,'
  echo 'create c  [lit] 72 c, [lit] 88 c, [lit] 0 c,'
  echo 'a b [lit] 3 bytes-eq  0= [lit] 49 + emit'    # a vs b: equal  -> "1"
  echo 'a c [lit] 3 bytes-eq  0= [lit] 49 + emit'    # a vs c: differ -> "0"
} | ./seed-forth
```

Expected output: `10`.  `a` and `b` are identical 3-byte buffers
(`HI\0`); `a` and `c` differ at byte 2 (`HI\0` vs `HX\0`).

### The finale: every Part I word at once

One last run, using nothing but words Part I built.  `src` holds the
nine bytes of the C fragment `int x=42;`.  `kind` classifies one byte
with nested `if,`s over Ch 6's predicates, and `scan` walks the
buffer with a `begin,` loop:

```sh
{ cat 010-lib.fth
  echo 'create src  [lit] 105 c, [lit] 110 c, [lit] 116 c, [lit] 32 c, [lit] 120 c,'
  echo '            [lit] 61 c, [lit] 52 c, [lit] 50 c, [lit] 59 c,'
  echo ': kind  dup alpha? if, drop [lit] 97 else,'
  echo '        dup digit? if, drop [lit] 100 else,'
  echo '        dup space? if, drop [lit] 95 then, then, then, emit ;'
  echo ': scan  begin, dup [lit] 0 > while,'
  echo '        over c@ kind  [lit] 1 - swap [lit] 1 + swap  repeat, 2drop ;'
  echo 'src [lit] 9 scan'
} | ./seed-forth
```

Expected output: `aaa_a=dd;`.  Letters became `a`, digits `d`, the
space `_`, and punctuation passed through.  That is the first step
of a C lexer, and most of its words (`create`, `if,`, `else,`,
`begin,`, `>`, `-`, `alpha?`, `2drop`) get a `?` from the bare
seed.

## Exercises

1. **★★ Trace.** Why is `bytes-eq-flag` a *variable* (a shared cell) rather than a
   local on the data stack?  Trace the loop and explain what would
   go wrong if you tried to keep the flag on the data stack.

2. **★★ Extend.** Define `2variable ( -- )` that defines a word pushing the address
   of a *two*-cell store.  Compare its emitted bytes to `variable`.

3. **★★ Extend.** Define `string, ( c-addr u -- )` that copies `u` bytes from
   `c-addr` to HERE and advances HERE.  The seed has no `"..."`
   string literals, so build a source buffer with `c,` (as in the
   Try-it's `create a`), then `create greeting` and use `string,` to
   copy those bytes into its data area as a named string blob.

4. **★★★ Trace.** The no-`exit` constraint forced O(n) compare even
   on mismatch.  How much extra work does that cost the C compiler
   in the worst case?  (Hint: longest identifier in the M2-Planet
   source; total `bytes-eq` calls per build.)

## Takeaways

- `create`, `variable`, and `constant` share one 19-byte runtime
  body and differ only in the `imm64` value and what follows the
  `ret`.
- `allot` bumps HERE by `n` bytes, and with `create` it reserves a
  named data area of any size.
- With no `exit` primitive, `bytes-eq` accumulates a flag in a
  variable and always reads every byte, which costs little on the
  short names the compiler compares.

**Part I tally, complete.**  Byte emission, Boolean logic,
subtraction, file I/O, character tests, comparisons, shuffles,
multi-byte writes, `constant`, branches and loops, **variables,
buffers, and string compare**.  `010-lib.fth` is complete.

## Bridge to Part II: what Part I bought us

In Ch 1 the bare seed answered `?` to `over - and < if, variable`.
You have now built all six, and every other line of `010-lib.fth`,
and run a byte classifier built from them.  Everything in Part I
was ordinary Forth.

And every line of it stands on 32 primitives you have taken on
faith.  `nand`, which gave you all of Boolean logic, is 12 bytes of
machine code at offset `0x1CE`.  `dup` is 9.  `/`, which gave you
`<` and every byte split, is 18.  What are those bytes?  How does 1,772 bytes of hex persuade a Linux kernel to run
a REPL at all?  Those bytes are the one layer of the chain a skeptic
cannot read as Forth, and Part I has not shown you one of them.

Part II opens that box.  Eight chapters read `000-seed.hex0` and
show the exact bytes behind every primitive you have called.
Ch 13 starts where the kernel does, at byte 0: the ELF header and
the entry point.  Chs 14–16 read the stack, arithmetic and I/O
primitives (`dup`, `nand`, `emit`, `syscall6`).  Chs 17–20 read the
machinery that runs everything else: the dictionary and `find`, the
colon compiler (`:`, `;`), `branch` and `0branch`, and the REPL.

Next: Chapter 13 — The ELF and the Entry Point, where the first 120
bytes of the file have one job: persuading the kernel to run the
rest.
