# Chapter 10 — Immediacy and Constants

```text
Missing capability: defining a constant requires compile-vs-runtime separation.
New pattern: the IMMEDIATE flag and STATE variable; constant as a 19-byte body plus a literal.
Artifact after this chapter: constant, call, and [char], plus the IMMEDIATE/STATE protocol Chs 11 and 12 lean on.
Proof link: every type tag, keyword ID, and libc shim address the C compiler reaches for is a constant.
```

So far every chapter has built one Forth word from a handful of
others.  This one builds a word that **builds words**.  Write
`[lit] 42 constant magic` and the dictionary gains an entry called
`magic` whose body is x86-64 machine code that nobody typed: 19
bytes that `constant` assembles on the spot, one `c,` at a time.
The C compiler's token kinds, type tags, and keyword IDs are all
defined this way.

`010-lib.fth` lines 180–263 do the job.  `immediate` sets a flag
that makes a word run at compile time, and `constant` lays down a
19-byte runtime body of x86-64 machine code, writing the value into
it with Ch 9's `,8`.  Both rest on two pieces of machinery that
haven't appeared yet: the **STATE** sysvar that distinguishes
interpret mode from compile mode, and the **IMMEDIATE flag** that
lets a word run at compile time anyway.  `create` and `variable`,
which reuse the same body, follow in Ch 12.  The chapter ends with
the first immediate word of the library, `[char]`, which lets the
compiler write `[char] ;` where it would otherwise write `[lit] 59`
and a comment saying what 59 is.

## 1. `STATE` and the two modes

Forth runs in one of two modes.  When `STATE == 0` (**interpret
mode**), every word you type is looked up and executed immediately.
When `STATE == 1` (**compile mode**), every word you type is looked
up and a CALL to it is *appended to the body of the word currently
being defined*.

Concretely:

| input         | STATE | what happens                                                         |
|---------------|-------|----------------------------------------------------------------------|
| `5 .`         | 0     | push `5` to the data stack, then call `.` (prints `5`)               |
| `: foo 5 . ;` | 0→1→0 | `:` flips STATE to 1; "5" and "." are compiled into foo's body; `;` flips STATE back to 0 |
| `foo`         | 0     | calls foo, which now executes its body (push 5, call `.`) and prints `5` |

The seed's STATE lives at `0x413000`, the first cell on the
sysvar page.  `state` is a seed primitive that pushes that address;
`state @` fetches the current mode; `state !` sets it.  `:` writes
`1` to STATE as part of its setup; `;` writes `0` as part of its
teardown.

## 2. The IMMEDIATE flag

Compile mode has a problem.  If *every* word gets compiled into the
body of the word-being-defined, how do you write `if`/`else`/`then`
or `;`?  Those words have to *do work at compile time*: `;` has to
finish off the current definition, not get compiled into it.

The answer is the **IMMEDIATE flag**.  Each dictionary entry has a
one-byte `flags` field, and bit 0 of that byte is the IMMEDIATE bit.
When the seed encounters a word with IMMEDIATE set, it runs the
word *now*, regardless of STATE.  That's how `;` works: it's an
immediate word whose body emits a `ret` instruction and resets STATE
to 0.

This is the seed's only metaprogramming hook, and it is enough.
Every control-flow construct in this codebase (`if,`, `then,`,
`else,`, `begin,`, `while,`, `repeat,`) works by being marked
IMMEDIATE and emitting branch instructions into the dictionary at
parse time.  Ch 11 walks through all of them.

## 3. Dictionary header layout

To toggle the IMMEDIATE flag, we need to know where it lives.  The
seed lays out a dictionary entry like this:

```
+0      link        (8 bytes)   pointer to previous entry, or 0 for the first
+8      flags       (1 byte)    bit 0 = IMMEDIATE, other bits unused
+9      name-len    (1 byte)    length of the name
+10     name        (N bytes)   the word's name, no terminator
+10+N   body        (M bytes)   the executable code
```

Total header size is `10 + N` bytes.  Following that is the body,
which for a primitive is hand-rolled machine code, for a colon
definition is a sequence of CALL rel32 instructions, and for a
constant is the 19-byte template in §5.

The seed maintains a **LATEST** sysvar pointing at the link cell of
the most recently defined entry.  Each new entry sets its own link
to the old LATEST and then overwrites LATEST to point at itself;
that's how the dictionary linked list grows.

`latest` is a seed primitive that pushes the *address* of the LATEST
sysvar cell (like `here-addr` from Ch 2: the address of the
sysvar, not its current value).  `latest @` fetches the current head
of the dictionary.  And since the link cell is at offset 0, `latest
@` is also the address of the link cell of the most-recent entry,
which means `latest @ + 8` is the address of its flags byte.

## 4. `immediate`: a one-liner

```forth
: immediate  latest @ [lit] 8 + [lit] 1 swap c! ;
```

Trace it:

| token         | stack                              |
|---------------|------------------------------------|
| (in)          | empty                              |
| `latest`      | `addr-of-LATEST`                   |
| `@`           | `addr-of-newest-entry`             |
| `[lit] 8`     | `addr-of-newest-entry 8`           |
| `+`           | `addr-of-flags-byte`               |
| `[lit] 1`     | `addr-of-flags-byte 1`             |
| `swap`        | `1 addr-of-flags-byte`             |
| `c!`          | empty (byte 1 written at the addr) |

So `immediate` writes `0x01` to the flags byte of the most-recently
defined word.  Conventional usage is:

```
: my-thing  ... ; immediate
```

That is, define a word with `: ... ;`, then call `immediate` to set
the IMMEDIATE bit on what we just defined.  After this, every call to
`my-thing` from within a colon definition runs *now*, not at the
defined word's runtime.

Two details.  First, the seed's manual `01` flags byte on the
`;` definition in `000-seed.hex0` (Ch 18) is exactly this byte:
`immediate` and the hand-rolled `01` in the seed hex write the same
byte in the same place by different mechanisms.  Second, `immediate`
writes the whole byte.  Storing `0x01` sets bit 0 and clears bits
1–7 rather than preserving them.  That is harmless here:
`:` always initialises the flags byte to `0`, and the REPL tests
only bit 0.  This codebase uses no other flag bits; a "fuller" Forth
might add `compile-only`, `hidden`, or `inline` here, but the seed
keeps it bare-bones.

## 5. `constant`'s runtime body

`constant` itself isn't IMMEDIATE.  It runs at interpret time,
builds a new dictionary entry, and exits.  What matters is the entry
it builds.

```forth
: ret,  [lit] 195 c, ;

: push-imm64,
  [lit] 72 c, [lit] 131 c, [lit] 237 c, [lit] 8 c,         \ 48 83 ED 08  sub rbp, 8
  [lit] 72 c, [lit] 137 c, [lit] 125 c, [lit] 0 c,         \ 48 89 7D 00  mov [rbp], rdi
  [lit] 72 c, [lit] 191 c,                                 \ 48 BF        movabs rdi, ...
  ,8 ;                                                     \ imm64 = v (consumes v)

: push-body,  push-imm64, ret, ;

: constant  : push-body, [lit] 0 state ! ;
```

The runtime body `push-body,` lays down is exactly 19 bytes:

| bytes          | x86-64 instruction       | what it does                          |
|----------------|--------------------------|---------------------------------------|
| `48 83 ED 08`  | `sub rbp, 8`             | grow the data-stack by one slot       |
| `48 89 7D 00`  | `mov [rbp+0], rdi`       | spill the old TOS into the new slot   |
| `48 BF <8 bytes>` | `movabs rdi, <imm64>`  | load the constant value as the new TOS |
| `C3`           | `ret`                    | return to the caller                  |

The seed's data stack lives in memory pointed at by `rbp`, with TOS
cached in `rdi` (Ch 14 reads the primitives that rely on this).  To push a new value: open a slot (`sub rbp, 8`),
write the old TOS into that slot (`mov [rbp+0], rdi`), and load the
new value into `rdi` (`movabs rdi, imm64`).  Then return.  Three
instructions plus a return.

`push-imm64,` writes the first 18 of those bytes using `c,` (Ch 2)
for the single-byte parts and `,8` (Ch 9) for the 8-byte `imm64`
immediate; `ret,` adds the `C3`.  The value being made-into-a-constant
is on the data stack when `constant` is called; `,8` consumes it and
writes its little-endian bytes into the imm64 slot.  The names end
in `,` by the same convention as `c,`: each one *emits* code at
HERE rather than doing the thing it names.  Ch 12's `create` and
`variable` call `push-body,` too, with a different value.

## 6. The role of `:` and `;` here

`constant` is a defining word that *uses other defining words to do
its work*.  Look at how the colon body opens and closes:

- The first token calls the seed primitive `:`.  It reads the next
  token from input, parses it as a name, builds the dictionary header for
  a new entry (link, flags=0, name-len, name), and sets STATE to 1.
- For the body, STATE is 1, so we're in "compile mode," but
  we don't *want* to compile CALL instructions; we want to write
  raw bytes.  We do that by calling `push-body,`, whose `c,` and
  `,8` bypass STATE entirely.
- `[lit] 0 state !` manually resets STATE to 0.  We can't use `;`
  here because `:` ... `;` is parsed by the seed as a single
  compile-mode bracket: the very first `;` the interpreter sees
  after the surrounding `:` closes *constant* itself, not the new
  word `constant` is building.  Two `;` tokens cannot share one
  outer colon definition.  So we exit compile mode by hand.

So two definitions are in play: the *outer* definition of
`constant` (a normal colon definition, closed with `;`) and the
*inner* definition of the new word (opened by calling `:`, closed
by the `C3` byte that `ret,` emits).

Keeping those two definitions apart is the hard part of this
chapter.  Every defining word in Ch 12 follows the same pattern.

## 7. `call,` and `[char]`: compiling by hand

Everything a colon definition contains is CALL instructions, and
the seed's `[lit]` is the one word that compiles anything else.
Two library words let Forth code do the same by hand.

**`call,` ( target -- )** emits a 5-byte x86-64 CALL to `target`.
CALL takes a 32-bit *relative* offset: the CPU computes
`rip = rip + rel32`, where `rip` already points past the CALL.  So

```
rel32 = target - (address-just-after-CALL)
      = target - (HERE_at_start_of_CALL + 5)
```

```forth
: call,
  [lit] 232 c,                 \ 0xE8 CALL opcode
  here [lit] 4 + - ,4 ;        \ rel32 = target - (HERE+4); emit 4 LE bytes
```

After `[lit] 232 c,` emits the opcode byte, HERE has *already
advanced by one* and points at the first byte of the rel32 field.
Adding 4 gives the address just past the whole 5-byte CALL, the
base the CPU will use.  So `target - (HERE_now + 4)` is right, and
`,4` (Ch 9) emits it little-endian.  Writing `here [lit] 5 + -`
instead would land one byte off.  Ch 11's combinators emit every
one of their branches with `call,`.

**`[char]`** compiles a character literal.  `[lit] 59` puts the
number 59 into a definition; `[char] ;` should put the same 59
there, spelled as the character.  It needs three pieces:

- `' lit constant lit-xt` captures the xt of the seed's `lit`
  primitive, the runtime half of `[lit]` that pushes the 8-byte
  cell following its CALL (Ch 18).
- `tib` is the address of the seed's token buffer, `0x412800`,
  where the reader leaves the last token it read.  `char` reads a
  token with `'` (tick, the one token reader Forth code can call),
  ignores tick's lookup answer, and takes the token's first byte
  from `tib`.  So `char A` pushes 65.
- `[char]` is `char lit-xt call, ,` marked `immediate`: at compile
  time it reads the next token and emits `CALL lit` plus the byte
  as an 8-byte cell.  Those are the same 13 bytes `[lit] 59` emits,
  so `: semi [char] ; ;` and `: semi [lit] 59 ;` compile to
  identical code.

`[char]` is this library's first immediate word, and it shows the
whole trick: an immediate word runs while its caller is being
compiled and emits whatever bytes it likes.

A few characters cannot be quoted this way.  The reader never makes
a token of a space, tab or newline, and a token that is exactly `\`
or `(` starts a comment.  Those five get constants instead: `tab`,
`nl`, `bl` (the traditional Forth name for a blank), `lparen` and
`backslash`.

## Canonical source

```forth file=010-lib.fth
\ ===== immediate flag toggle =====
\ immediate ( -- )  Set the IMMEDIATE bit in the flags byte of the most-recent
\ dict entry.  An immediate word executes at compile time even when STATE=1
\ (inside : ... ;).  Mirrors the manual `01` flags byte on `;` in 000-seed.hex0.
\
\ Layout reminder: a dict entry is  link(8) flags(1) name-len(1) name(N) body.
\ `latest` is a seed primitive — it pushes the address of the LATEST sysvar
\ cell; `latest @` fetches the current dict tail pointer; `+ 8` is the
\ flags-byte address.
: immediate  latest @ [lit] 8 + [lit] 1 swap c! ;

\ ===== the push body: constant (and create / variable in Ch 12) =====
\ constant is defined early so branch-xt/0branch-xt can use it: the
\ control-flow combinators below need the xts of branch/0branch, and
\ hard-coding them as numeric literals would break every time
\ 000-seed.hex0's dictionary layout changes; instead, resolve them at load
\ time via the seed's `'` (tick) primitive, captured into a constant.
\
\ A word that pushes one value has a 19-byte runtime body:
\   48 83 ED 08          sub rbp, 8       ; make data-stack room
\   48 89 7D 00          mov [rbp+0], rdi ; spill old TOS
\   48 BF <imm64>        movabs rdi, V    ; load the value as the new TOS
\   C3                   ret
\ constant, create and variable all lay it down; they differ only in V
\ and in what follows the ret.

\ ret, ( -- )  emit C3, the x86 `ret` instruction.
: ret,  [lit] 195 c, ;

\ push-imm64, ( v -- )  emit the 18 bytes that push v: the body minus ret.
: push-imm64,
  [lit] 72 c, [lit] 131 c, [lit] 237 c, [lit] 8 c,         \ 48 83 ED 08  sub rbp, 8
  [lit] 72 c, [lit] 137 c, [lit] 125 c, [lit] 0 c,         \ 48 89 7D 00  mov [rbp], rdi
  [lit] 72 c, [lit] 191 c,                                 \ 48 BF        movabs rdi, ...
  ,8 ;                                                     \ imm64 = v (consumes v)

\ push-body, ( v -- )  emit the whole 19-byte body of a word that pushes v.
: push-body,  push-imm64, ret, ;

\ constant ( v "name" -- )  define name as a word that pushes v.
\ `:` parses the name, builds the header and sets STATE=1; we emit the body
\ by hand and set STATE back to 0 (a `;` here would end constant itself).
: constant  : push-body, [lit] 0 state ! ;

\ ===== call, and character literals =====

\ call, ( target -- )  Emit a 5-byte x86-64 CALL to absolute `target`
\ at HERE.  rel32 = target - (HERE + 5).  After `[lit] 232 c,` advances
\ HERE by 1, HERE points at the rel32's first byte and HERE+4 points just
\ past the 5-byte CALL — so rel32 = target - (HERE_now + 4).
\ Kept here so [char] and the control-flow combinators do not need another
\ assembler layer.
: call,
  [lit] 232 c,                 \ 0xE8 CALL opcode
  here [lit] 4 + - ,4 ;        \ rel32 = target - (HERE+4); emit 4 LE bytes

\ lit-xt — the xt of the seed's `lit` primitive, which pushes the cell that
\ follows its CALL (the runtime half of [lit]).
' lit constant lit-xt

\ tib ( -- a )  the seed's token buffer, where its reader leaves the token
\ it read last.  It sits 2048 bytes below the sysvar page, which starts at
\ STATE's cell: 0x413000 - 2048 = 0x412800.
: tib  state [lit] 2048 - ;

\ char ( "tok" -- c )  read the next token and push its first byte.
\ The seed's one Forth-callable token reader is ' (tick): it reads a token
\ into the TIB and looks it up.  We drop its answer (an xt, or 0 when no word
\ has that name) and take the byte straight from the TIB.
: char  ' drop tib c@ ;

\ [char] ( "tok" -- )  IMMEDIATE, used inside : ... ;  Compile the next
\ token's first byte as a literal: CALL lit and the cell, the same 13 bytes
\ `[lit] N` lays down.  So `[char] ;` compiles exactly what `[lit] 59` does.
: [char]  char lit-xt call, , ;
immediate

\ Characters char cannot quote.  The reader never makes a token of
\ whitespace, and a token that is exactly \ or ( starts a comment.
[lit]  9 constant tab
[lit] 10 constant nl
[lit] 32 constant bl
[lit] 40 constant lparen                    \ (
[lit] 92 constant backslash

```

## Try it

`immediate`, `constant` and `[char]` lean on machinery (`latest`, `:`, `state`,
`c,` against the real seed dictionary) that gforth implements but
differently.  This is the first chapter where the playground
diverges meaningfully from the seed.  Use a built seed-forth:

```sh
./build.sh
echo '[lit] 42 constant magic  magic [lit] 48 + emit bye' \
  | cat 010-lib.fth - \
  | ./seed-forth
```

This defines `magic` as a constant pushing `42`, then calls it,
adds 48, and emits the resulting byte.  Expected output: `Z`
(ASCII 90 = 42 + 48).  That `42` came out of a `movabs` instruction
the library assembled a moment earlier.

To measure what `constant` wrote, capture HERE before and after
it and emit the difference:

```sh
./build.sh
echo 'here  [lit] 42 constant magic  here swap - [lit] 48 + emit bye' \
  | cat 010-lib.fth - \
  | ./seed-forth
```

Expected output: `R` (ASCII 82 = 48 + 34).  The 34 bytes are the
15-byte header for the five-letter name `magic` (`10 + N`) plus
the 19-byte runtime body.  Walking the individual bytes means
reading the dictionary header by hand, which Ch 17 makes easier.

`[char]` compiles the same bytes as `[lit]`, so these two words
print the same character:

```sh
./build.sh
echo ': a1 [char] Z emit ;  : a2 [lit] 90 emit ;  a1 a2 bye' \
  | cat 010-lib.fth - \
  | ./seed-forth
```

Expected output: `ZZ`.

## Exercises

1. **★★ Extend.** Define `2constant ( hi lo -- )` that defines a word pushing two
   cells.  How many bytes is its runtime body?

2. **★★ Trace.** `constant` is not immediate, so it can be compiled
   into another word.  Predict what `: k  [lit] 53 constant ;`
   followed by `k five  five emit` does on the seed, then run it.
   Where does `constant`'s `:` find the name `five`, and what is
   STATE before, during and after `k` runs?

3. **★★★ Trace.** The flags byte has eight bits.  What might the other seven be
   used for in a fuller Forth?  This seed uses only bit 0 — would
   you add `compile-only`, `hidden`, or `inline` bits?  Why or
   why not?

4. **★★ Trace.** Predict the bytes emitted by `[lit] 12345 constant n`.  Compare
   to the disassembly of a built seed-forth by hand-computing the
   `imm64` slot's contents.

## Takeaways

- `STATE` switches between interpret mode (0) and compile mode (1),
  and a word with the IMMEDIATE bit (bit 0 of the flags byte at
  `latest @ + 8`) runs at compile time regardless.
- `constant` calls `:` to build a header, writes a 19-byte body
  (`sub rbp,8 ; mov [rbp],rdi ; movabs rdi,V ; ret`) with
  `push-body,`, then resets STATE by hand; Ch 12's `create` and
  `variable` reuse that body with a different `V`.
- `call,` emits a rel32 CALL and the immediate `[char]` uses it to
  compile a character as the same 13 bytes `[lit]` would, so the
  compiler never has to spell an ASCII code in decimal.

**Part I tally.**  Built so far: byte emission, Boolean logic,
subtraction, file I/O, character tests, comparisons, shuffles,
multi-byte writes, **words that define words** (`constant`),
character literals.  Still missing: `if,`, loops, `variable`.

Next: Chapter 11 — Control-Flow Combinators (the climax).  Nothing
in the library but `[char]` has used `immediate` yet, and every word
written so far runs straight from its first token to its `ret`.  The seed's
parser knows nothing about `if`, and nobody will teach it, because
the parser is hex.  Ch 11 writes `if,` anyway, as an ordinary
immediate word.
