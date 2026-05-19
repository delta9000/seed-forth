# Chapter 10 — Immediacy and Constants

> **Status:** ✅ complete.  Prose covers every section-plan beat; the
> seed-forth Try-it path is verified.  (The gforth playground
> diverges meaningfully from the seed here, so only the seed path
> exercises real `immediate`/`constant`.)  Canonical blocks cover
> `010-lib.fth` lines 162–193.

## Goal

By the end of this chapter the reader can:

- explain the IMMEDIATE flag in a dictionary header and how
  `immediate` toggles it on the most-recent definition;
- name the four fields of a dictionary entry in this codebase
  (`link`, `flags`, `name-len`, `name`, followed by body);
- read `constant`'s 19-byte runtime body and explain each byte;
- write a new defining word that emits its own custom runtime body.

## Source coverage

`010-lib.fth` lines 162–193.  Two definitions: `immediate`, `constant`.

## Concepts introduced

- **`STATE`.**  The sysvar at `0x413000`.  `0` = interpret mode
  (execute parsed words immediately); `1` = compile mode (append a
  CALL to the parsed word into the body of the word being defined).
  Set to `1` by `:`, reset to `0` by `;`.
- **The IMMEDIATE flag.**  A bit in the `flags` byte of a dictionary
  header.  An immediate word *always* runs at parse time, even when
  `STATE=1`.  This is what makes `if,`, `;`, and the rest of the
  control-flow combinators work.
- **`latest`.**  Seed primitive: pushes the *address* of the `LATEST`
  sysvar cell (not its contents).  `latest @` is the head of the
  dictionary; `latest @ + 8` is its flags byte.
- **The 19-byte runtime body shared by `constant`, `variable`,
  `create`.**  Three x86-64 instructions: `sub rbp,8` (open data-stack
  slot), `mov [rbp+0], rdi` (spill old TOS), `movabs rdi, imm64`
  (load the value as new TOS), `ret`.  Always exactly 19 bytes.

## Concepts carried in

- `c,` (Ch 2), `,8` (Ch 9) — for emitting the body bytes.
- `latest`, `@`, `+`, `swap`, `c!`, `state`, `!` — seed primitives.
- `:` and `;` — seed primitives that we begin to use *programmatically*
  here, not just as syntax.

## Concepts deferred

- `;` itself as a word, with its own IMMEDIATE flag in the seed —
  Part II, Ch 18.
- `create` and `variable` — Ch 12, where they round out the
  defining-word family.
- The full x86-64 instruction encoding for `movabs` and `mov` —
  Part II, Chs 14 and 18.

---

So far every chapter has built one Forth word from a handful of
others.  This chapter does something different: we build a word that
**builds words**.  `constant` is a *defining word* — when you write
`[lit] 42 constant magic`, you don't just call a function; you
extend the dictionary with a brand-new entry called `magic` whose
behaviour, when later invoked, pushes `42`.  To pull that off, the
seed needs two pieces of infrastructure that haven't shown up yet:
the **STATE** sysvar that distinguishes interpret mode from compile
mode, and the **IMMEDIATE flag** that lets a word break the rules
and run at compile time anyway.

## 1. `STATE` and the two modes

Forth runs in one of two modes.  When `STATE == 0` — **interpret
mode** — every word you type is looked up and executed immediately.
When `STATE == 1` — **compile mode** — every word you type is looked
up and a CALL to it is *appended to the body of the word currently
being defined*.

Concretely:

| input         | STATE | what happens                                                         |
|---------------|-------|----------------------------------------------------------------------|
| `5 .`         | 0     | push `5` to the data stack, then call `.` (prints `5`)               |
| `: foo 5 . ;` | 0→1→0 | `:` flips STATE to 1; "5" and "." are compiled into foo's body; `;` flips STATE back to 0 |
| `foo`         | 0     | calls foo, which now executes its body (push 5, call `.`) and prints `5` |

The seed's STATE lives at `0x413000` — the very first cell on the
sysvar page.  `state` is a seed primitive that pushes that address;
`state @` fetches the current mode; `state !` sets it.  `:` writes
`1` to STATE as part of its setup; `;` writes `0` as part of its
teardown.

## 2. The IMMEDIATE flag

Compile mode has a problem.  If *every* word gets compiled into the
body of the word-being-defined, how do you write `if`/`else`/`then`
or `;`?  Those words have to *do work at compile time* — `;` has to
finish off the current definition, not get compiled into it.

The answer is the **IMMEDIATE flag**.  Each dictionary entry has a
one-byte `flags` field, and bit 0 of that byte is the IMMEDIATE bit.
When the seed encounters a word with IMMEDIATE set, it runs the
word *now*, regardless of STATE.  That's how `;` works: it's an
immediate word whose body emits a `ret` instruction and resets STATE
to 0.

This is the seed's only metaprogramming hook.  It is also enough.
Every control-flow construct in this codebase — `if,`, `then,`,
`else,`, `begin,`, `while,`, `repeat,` — works by being marked
IMMEDIATE and emitting branch instructions into the dictionary at
parse time.  Ch 11 walks through all of them; this chapter prepares
the ground by giving us a way to set the IMMEDIATE flag from Forth.

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
constant is the 19-byte template we'll meet in section 5.

The seed maintains a **LATEST** sysvar pointing at the link cell of
the most recently defined entry.  Each new entry sets its own link
to the old LATEST and then overwrites LATEST to point at itself —
that's how the dictionary linked list grows.

`latest` is a seed primitive that pushes the *address* of the LATEST
sysvar cell (analogous to `here-addr` from Ch 2 — address of the
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

— define a word with `: ... ;`, then call `immediate` to flip the
IMMEDIATE bit on what we just defined.  After this, every call to
`my-thing` from within a colon definition runs *now*, not at the
defined word's runtime.

Two subtle points.  First, the seed's manual `01` flags byte on the
`;` definition in `000-seed.hex0` (Ch 18) is exactly this byte —
`immediate` from `010-lib.fth` and the hand-rolled `01` in the seed
hex are the same byte in the same place, written by different
mechanisms.  Second, `immediate` only writes bit 0; bits 1–7 are
ignored.  This codebase uses no other flag bits; a "fuller" Forth
might add `compile-only`, `hidden`, or `inline` here, but the seed
keeps it bare-bones.

## 5. `constant`'s runtime body

`constant` is where the IMMEDIATE machinery is going to pay off
(through its sibling control-flow words in Ch 11), but `constant`
itself isn't IMMEDIATE — it runs at interpret time, builds a new
dictionary entry, and exits.  What's interesting is the entry it
builds.

```forth
: constant
  :                                                        \ parse name, build header, STATE=1
  [lit] 72 c, [lit] 131 c, [lit] 237 c, [lit] 8 c,         \ 48 83 ED 08  sub rbp, 8
  [lit] 72 c, [lit] 137 c, [lit] 125 c, [lit] 0 c,         \ 48 89 7D 00  mov [rbp], rdi
  [lit] 72 c, [lit] 191 c,                                 \ 48 BF        movabs rdi, ...
  ,8                                                       \ imm64 = v (consumes v)
  [lit] 195 c,                                             \ C3          ret
  [lit] 0 state ! ;                                        \ STATE=0 (back to interpret)
```

The runtime body is exactly 19 bytes:

| bytes          | x86-64 instruction       | what it does                          |
|----------------|--------------------------|---------------------------------------|
| `48 83 ED 08`  | `sub rbp, 8`             | grow the data-stack by one slot       |
| `48 89 7D 00`  | `mov [rbp+0], rdi`       | spill the old TOS into the new slot   |
| `48 BF <8 bytes>` | `movabs rdi, <imm64>`  | load the constant value as the new TOS |
| `C3`           | `ret`                    | return to the caller                  |

The seed's data stack lives in memory pointed at by `rbp`, with TOS
cached in `rdi`.  To push a new value: open a slot (`sub rbp, 8`),
write the old TOS into that slot (`mov [rbp+0], rdi`), and load the
new value into `rdi` (`movabs rdi, imm64`).  Then return.  Three
instructions plus a return.

`constant` writes those bytes by hand using `c,` (Ch 2) for the
single-byte parts and `,8` (Ch 9) for the 8-byte `imm64`
immediate.  The value being made-into-a-constant is on the data
stack when `constant` is called; `,8` consumes it and writes its
little-endian bytes into the imm64 slot.

## 6. The role of `:` and `;` here

`constant` is a defining word that *uses other defining words to do
its work*.  Look at how the colon body opens and closes:

- `:`  — this is the seed primitive `:`.  It reads the next token
  from input, parses it as a name, builds the dictionary header for
  a new entry (link, flags=0, name-len, name), and sets STATE to 1.
- (body emission) — with STATE=1, we're now in "compile mode," but
  we don't *want* to compile CALL instructions; we want to write
  raw bytes.  We do that by calling `c,` and `,8` directly, which
  bypass STATE entirely.
- `[lit] 0 state !` — manually reset STATE to 0.  We can't use `;`
  here because `;` would compile a final `ret` and exit *constant
  itself*, not the word constant just defined.  So we exit compile
  mode by hand.

Notice that `constant` ends in `;`, which closes *constant*'s own
definition.  Inside constant's body, we manually call `:` and
manually reset STATE — that's two separate definitions running:
the *outer* definition of `constant` (a normal colon definition,
closed with `;`) and the *inner* definition of the new word the
user is creating (opened by calling `:`, closed by emitting the
`C3` ret byte by hand).

This is the trickiest part of Part I.  Re-read this section if it
feels like word-salad — the trick is to keep two definitions in
mind at once.  Once you internalise it, every defining word in Ch
12 follows the same pattern.

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

\ ===== constant (defined early so branch-xt/0branch-xt can use it) =====
\ The control-flow combinators below need to know branch/0branch's xts.
\ Hardcoding them as numeric literals would break every time 000-seed.hex0's
\ dictionary layout changes; instead, resolve them at load time via the
\ seed's `'` (tick) primitive, captured into a constant.  This requires
\ `constant` to be defined before the combinators — hence its position here.
\
\ Runtime body is 19 bytes:
\   48 83 ED 08          sub rbp, 8       ; make data-stack room
\   48 89 7D 00          mov [rbp+0], rdi ; spill old TOS
\   48 BF <imm64>        movabs rdi, V    ; load the value as the new TOS
\   C3                   ret
: constant
  :                                                        \ parse name, build header, STATE=1
  [lit] 72 c, [lit] 131 c, [lit] 237 c, [lit] 8 c,         \ 48 83 ED 08  sub rbp, 8
  [lit] 72 c, [lit] 137 c, [lit] 125 c, [lit] 0 c,         \ 48 89 7D 00  mov [rbp], rdi
  [lit] 72 c, [lit] 191 c,                                 \ 48 BF        movabs rdi, ...
  ,8                                                       \ imm64 = v (consumes v)
  [lit] 195 c,                                             \ C3          ret
  [lit] 0 state ! ;                                        \ STATE=0 (back to interpret)

```

## Try it

`immediate` and `constant` lean on machinery (`latest`, `:`, `state`,
`c,` against the real seed dictionary) that gforth implements but
differently.  This is the first chapter where the playground
diverges meaningfully from the seed.  Use a built seed-forth:

```sh
./build.sh
echo '[lit] 42 constant magic  magic [lit] 48 + emit bye' \
  | { sed -e 's/\\.*$//' -e 's/([^)]*)//g' 010-lib.fth; cat; } \
  | ./seed-forth
```

This defines `magic` as a constant pushing `42`, then calls it,
adds 48, and emits the resulting byte.  Expected output: `Z`
(ASCII 90 = 42 + 48).

If you want to inspect the runtime body, capture HERE before and
after the call to `constant`:

```sh
./build.sh
echo 'here  [lit] 42 constant magic  here swap [lit] 48 + emit drop'  \
  | { sed -e 's/\\.*$//' -e 's/([^)]*)//g' 010-lib.fth; cat; } \
  | ./seed-forth
```

(This is a sketch; precise byte-inspection requires walking back
through the dictionary header by hand, which Ch 17 makes easier.)

## Exercises

1. Define `2constant ( hi lo -- )` that defines a word pushing two
   cells.  How many bytes is its runtime body?

2. Why does `constant` end with `[lit] 0 state !` instead of just
   `;`?  (Hint: trace what STATE is at each point.  Can `constant`
   even *use* `;` directly?)

3. The flags byte has eight bits.  What might the other seven be
   used for in a fuller Forth?  This seed uses only bit 0 — would
   you add `compile-only`, `hidden`, or `inline` bits?  Why or
   why not?

4. Predict the bytes emitted by `[lit] 12345 constant n`.  Compare
   to the disassembly of a built seed-forth by hand-computing the
   `imm64` slot's contents.

## Takeaways

- `STATE` toggles between interpret and compile mode; `:` flips it
  to 1, `;` flips it to 0.  An IMMEDIATE word ignores STATE.
- A dictionary entry is `link(8) flags(1) name-len(1) name(N)
  body(M)`.  `latest @` points at the link cell; `+ 8` is the
  flags byte.
- `constant` is the template defining word.  Its 19-byte runtime
  body — `sub rbp,8 ; mov [rbp],rdi ; movabs rdi,V ; ret` — is
  copy-pasted (with different `V`) into `variable` (Ch 12) and
  `create` (Ch 12).

Next: Chapter 11 — Control-Flow Combinators (the climax).
