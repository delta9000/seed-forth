# Appendix A — The 32 seed primitives

The `000-seed.hex0` image contains 32 dictionary entries (32 user-
visible primitives) plus a small number of unnamed internal helpers.
Each primitive has a hand-written x86-64 body, a dictionary entry in
the seed, and (usually) further Forth-level use in `010-lib.fth` and
beyond.  Two `_code` blocks have no dictionary entry of their own:
`read_word` (used by the REPL and by `:`, `[lit]`, and `'`) and
`parse_decimal_code` (used by `[lit]`'s runtime path).

The choice of 32 is not symbolic.  It is the minimum that lets
`010-lib.fth` be a normal Forth program: arithmetic, stack
shufflers, comparisons, memory writers, control-flow combinators,
defining words.  Everything else in the system is composed from
these.

## The table

Source order matches `000-seed.hex0` order.  "Use site" is the
first Part I chapter where the word appears in user code or
chapter prose; "Asm site" is the Part II chapter that explains
the hex body.  `find`, `execute`, and `read_word` are REPL-
internal — they have no user-code uses in `010-lib.fth`, so
their Use-site column points to the first chapter that mentions
them in prose.

| # | Word | Stack effect | Body @ | Use site | Asm site |
|---|------|---|---|---|---|
| 1  | `bye`        | ( -- )                            | `0x0D2` | Ch 1  | Ch 16 |
| 2  | `emit`       | ( c -- )                          | `0x0DE` | Ch 1  | Ch 16 |
| 3  | `key`        | ( -- c )                          | `0x10C` | Ch 1  | Ch 16 |
| 4  | `dup`        | ( n -- n n )                      | `0x13B` | Ch 1  | Ch 14 |
| 5  | `drop`       | ( n -- )                          | `0x144` | Ch 1  | Ch 14 |
| 6  | `swap`       | ( a b -- b a )                    | `0x14D` | Ch 1  | Ch 14 |
| 7  | `>r`         | ( n -- ; R: -- n )                | `0x159` | Ch 4  | Ch 14 |
| 8  | `r>`         | ( -- n ; R: n -- )                | `0x165` | Ch 4  | Ch 14 |
| 9  | `@`          | ( addr -- v )                     | `0x171` | Ch 2  | Ch 14 |
| 10 | `!`          | ( v addr -- )                     | `0x175` | Ch 2  | Ch 14 |
| 11 | `c@`         | ( addr -- b )                     | `0x189` | Ch 2  | Ch 14 |
| 12 | `c!`         | ( b addr -- )                     | `0x18E` | Ch 2  | Ch 14 |
| 13 | `+`          | ( a b -- a+b )                    | `0x1A1` | Ch 1  | Ch 15 |
| 14 | `nand`       | ( a b -- ~(a&b) )                 | `0x1AA` | Ch 1  | Ch 15 |
| 15 | `0=`         | ( n -- flag )                     | `0x1B6` | Ch 6  | Ch 15 |
| 16 | `find`       | ( c-addr u -- xt &#124; 0 )       | `0x1C5` | Ch 10 | Ch 17 |
| 17 | `here`       | ( -- addr )                       | `0x21B` | Ch 2  | Ch 17 |
| 18 | `,`          | ( v -- ) write cell at HERE       | `0x22C` | Ch 9  | Ch 17 |
| 19 | `execute`    | ( xt -- )                         | `0x24C` | Ch 11 | Ch 17 |
| 20 | `:`          | ( -- ) start colon definition     | `0x2D4` | Ch 10 | Ch 18 |
| 21 | `;`          | ( -- ) end colon definition (IMM) | `0x33B` | Ch 10 | Ch 18 |
| 22 | `lit`        | ( -- v ) read inline cell, push n | `0x419` | Ch 11 | Ch 18 |
| 23 | `branch`     | ( -- ) inline target              | `0x42B` | Ch 11 | Ch 19 |
| 24 | `0branch`    | ( flag -- ) inline target         | `0x431` | Ch 11 | Ch 19 |
| 25 | `[lit]`      | ( -- ) parse word, push n (IMM)   | `0x652` | Ch 1  | Ch 18 |
| 26 | `syscall6`   | ( a b c d e f n -- rax )          | `0x6D4` | Ch 5  | Ch 16 |
| 27 | `/`          | ( a b -- a/b ) unsigned           | `0x710` | Ch 7  | Ch 15 |
| 28 | `r@`         | ( -- n ; R: n -- n )              | `0x732` | Ch 3  | Ch 14 |
| 29 | `*`          | ( a b -- a*b ) signed             | `0x743` | Ch 7  | Ch 15 |
| 30 | `state`      | ( -- addr ) STATE sysvar addr     | `0x753` | Ch 10 | Ch 17 |
| 31 | `latest`     | ( -- addr ) LATEST sysvar addr    | `0x766` | Ch 10 | Ch 17 |
| 32 | `'`          | ( -- xt ) tick: read word, find   | `0x779` | Ch 11 | Ch 17 |

## Internal helpers (not user-visible)

These exist in `000-seed.hex0` but have no dictionary entry, so the
REPL cannot call them by name.  They are reached only from compiled
code or from other primitives.

| Helper | Stack effect | Body @ | Called by | Asm site |
|---|---|---|---|---|
| `read_word`         | ( -- ; len in `rax`, 0 on EOF )                  | `0x259` | REPL, `:`, `[lit]`, `'` | Ch 17 |
| `parse_decimal_code`| ( c-addr u -- n true &#124; 0 false )            | `0x5FD` | compiled `[lit]`        | Ch 20 |
| `bracket_lit_code`  | ( -- ) IMMEDIATE: parse, push, or compile `lit` | `0x652` | the `[lit]` dict entry  | Ch 18 |

## What is *not* a primitive

These look like primitives but are colon definitions in
`010-lib.fth`:

- `over`, `nip`, `rot`, `2dup`, `2drop` — stack shufflers, Ch 8.
- `-`, `=`, `<>`, `<`, `>`, `<=`, `>=` — derived from `+`, `nand`,
  `/`, `0=`.  Chs 4, 7.
- `and`, `or`, `not` — derived from `nand`.  Ch 3.
- `digit?`, `alpha?`, `space?` — Ch 6.
- `+!`, `-!`, `,4`, `,8` — Ch 9.
- `immediate`, `constant`, `variable`, `create`, `allot` — Chs 10, 12.
- `if,`, `then,`, `else,`, `begin,`, `while,`, `repeat,` — Ch 11.
- `branch-xt`, `0branch-xt`, `comma-call`, `bytes-eq` — Chs 11, 12.

The boundary between "primitive" and "library word" is exactly the
boundary between `000-seed.hex0` and `010-lib.fth`.  Once `010-lib.fth`
loads, the dictionary contains both, indistinguishable to user code.

## Total byte budget

The hand-encoded bodies above sum to roughly 1.3 KiB of the
2,040-byte seed.  The remainder is the ELF header (120 bytes),
the sysvar init (72 bytes), the REPL (~95 bytes), and the
dictionary entries — each entry being `link(8) flags(1) name-len(1)
name(N) jmp(5)` = `15 + len(name)` bytes.  Appendix B gives the
full memory map.

## A note on `NUMBER_HOOK`

The sysvar at `0x413020` — `NUMBER_HOOK` — is **initialised to 0
and never read by anything in this build.**  It exists as an
unwired extension point: a future REPL miss-handler could install
a Forth `xt` there (a hex-literal parser, a string-literal parser,
whatever) and the seed would call it after `find_code` misses.
But the seed itself never consults it, so an empty `NUMBER_HOOK`
is the steady-state.  See Ch 20 for the REPL loop that *would*
read it if the wiring were there, and Ch 20's Exercise 1 for what
it would take to install one.
