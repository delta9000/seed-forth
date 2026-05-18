# Chapter 10 — Immediacy and Constants

> **Status:** stub.  Canonical blocks below cover `010-lib.fth`
> lines 162–193.  Prose goes between them.

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

## Section plan

1. **`STATE` and the two modes.**  Show what happens when you type
   `5 .` at the prompt (interpret: push 5, then call `.`) vs inside
   `: foo  5 . ;` (compile: append "push 5, call ." into foo's body).
2. **The IMMEDIATE flag.**  An IMMEDIATE word breaks the compile-mode
   rule: it runs *now*, at compile time.  This is the seed's only
   metaprogramming hook.
3. **Dictionary header layout.**  Draw the picture: `[link:8][flags:1]
   [name-len:1][name:N][body:M]`.  Total header size = `10 + N`.
   `latest @` points at the link cell of the most recent entry.
4. **`immediate`: a one-liner.**  `latest @ [lit] 8 + [lit] 1 swap c!`.
   That's `addr-of-flags 1 swap c!` = write `1` to the flags byte.
   Trace the stack precisely.
5. **`constant`'s runtime body.**  Read each of the seven `[lit] N c,`
   lines and identify the x86-64 instruction it builds.  Walk through
   what happens when the defined word runs: `rbp -= 8` (open a slot),
   `[rbp] = rdi` (save old TOS), `rdi = V` (load the value), `ret`.
6. **The role of `:` and `;` here.**  `constant` *calls* `:` to do
   the dirty work of parsing the name and building the header.  After
   `:`, STATE=1 (the seed is now in compile mode for our new word).
   We emit the body bytes manually with `c,` and `,8`.  Finally we
   set STATE=0 to leave compile mode (since we never typed `;`).

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

`immediate` and `constant` need machinery (`latest`, `:`, `state`,
`c,` against the real seed dictionary) that gforth implements but
differently.  This is the first chapter where the playground
diverges meaningfully from the seed.  Use a built seed-forth:

```sh
./build.sh
echo '[lit] 42 constant magic  magic [lit] 48 + emit bye' | ./seed-forth
\ should print 'Z' (ASCII 90 = 42 + 48)
```

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
