# Appendix A — The 32 seed primitives

The `000-seed.hex0` image contains 32 dictionary entries, one per
user-visible primitive, plus a few unnamed internal routines.  Each
primitive is one unit in the file: its dictionary header followed
directly by its hand-written x86-64 code, so the word's xt is the
address of that code.  Most are used again at the Forth level in
`010-lib.fth` and beyond.  Seven routines have no dictionary entry
of their own: the token reader `read_word` with its helpers
`read_char`, `report_token` and `fatal_token`; `compile_call`, which
lays down one `CALL`; `parse_decimal_code`, called by `[lit]`; and
the REPL loop itself.

The choice of 32 is not symbolic.  It is the minimum that lets
`010-lib.fth` be a normal Forth program: arithmetic, stack
shufflers, comparisons, memory writers, control-flow combinators,
defining words.  Everything else in the system is composed from
these.

## The table

Source order matches `000-seed.hex0` order, which is also the order
Chs 14–20 read them in; the dictionary chain runs the other way, from
`0branch` (the newest) back to `dup`.  "Code @" is the file offset of
the word's code, which is its xt (add `0x400000` for the address).
"Use site" is the first Part I chapter where the word appears in
user code or chapter prose; "Asm site" is the Part II chapter that
explains the hex.  `find` has no use in `010-lib.fth` (the REPL is
its caller), and `execute` appears there only as the xt that
`defer`'s bodies call (Ch 12), so for these two the Use-site column
points to the first chapter that mentions them in prose.

| # | Word | Stack effect | Code @ | Use site | Asm site |
|---|------|---|---|---|---|
| 1  | `dup`        | ( n -- n n )                      | `0x0C7` | Ch 1  | Ch 14 |
| 2  | `drop`       | ( n -- )                          | `0x0DE` | Ch 1  | Ch 14 |
| 3  | `swap`       | ( a b -- b a )                    | `0x0F5` | Ch 1  | Ch 14 |
| 4  | `>r`         | ( n -- ; R: -- n )                | `0x10D` | Ch 4  | Ch 14 |
| 5  | `r>`         | ( -- n ; R: n -- )                | `0x125` | Ch 4  | Ch 14 |
| 6  | `r@`         | ( -- n ; R: n -- n )              | `0x13D` | Ch 4  | Ch 14 |
| 7  | `@`          | ( addr -- v )                     | `0x159` | Ch 2  | Ch 14 |
| 8  | `!`          | ( v addr -- )                     | `0x168` | Ch 2  | Ch 14 |
| 9  | `c@`         | ( addr -- b )                     | `0x188` | Ch 2  | Ch 14 |
| 10 | `c!`         | ( b addr -- )                     | `0x199` | Ch 2  | Ch 14 |
| 11 | `+`          | ( a b -- a+b )                    | `0x1B7` | Ch 1  | Ch 15 |
| 12 | `nand`       | ( a b -- ~(a&b) )                 | `0x1CE` | Ch 1  | Ch 15 |
| 13 | `0=`         | ( n -- flag )                     | `0x1E6` | Ch 6  | Ch 15 |
| 14 | `/`          | ( a b -- a/b ) unsigned           | `0x200` | Ch 7  | Ch 15 |
| 15 | `*`          | ( a b -- a*b ) signed             | `0x21D` | Ch 7  | Ch 15 |
| 16 | `bye`        | ( -- )                            | `0x23A` | Ch 1  | Ch 16 |
| 17 | `emit`       | ( c -- )                          | `0x254` | Ch 1  | Ch 16 |
| 18 | `key`        | ( -- c )                          | `0x28F` | Ch 1  | Ch 16 |
| 19 | `syscall6`   | ( a b c d e f n -- rax )          | `0x2D0` | Ch 5  | Ch 16 |
| 20 | `find`       | ( c-addr u -- xt &#124; 0 )       | `0x303` | Ch 10 | Ch 17 |
| 21 | `here`       | ( -- addr )                       | `0x367` | Ch 2  | Ch 17 |
| 22 | `,`          | ( v -- ) write cell at HERE       | `0x383` | Ch 9  | Ch 17 |
| 23 | `execute`    | ( xt -- )                         | `0x3B4` | Ch 11 | Ch 17 |
| 24 | `state`      | ( -- addr ) STATE sysvar addr     | `0x497` | Ch 10 | Ch 17 |
| 25 | `latest`     | ( -- addr ) LATEST sysvar addr    | `0x4BA` | Ch 10 | Ch 17 |
| 26 | `'`          | ( -- xt &#124; 0 ) tick: read, find | `0x4D8` | Ch 11 | Ch 17 |
| 27 | `:`          | ( -- ) start colon definition     | `0x4ED` | Ch 10 | Ch 18 |
| 28 | `;`          | ( -- ) end colon definition (IMM) | `0x54A` | Ch 10 | Ch 18 |
| 29 | `lit`        | ( -- v ) read inline cell, push n | `0x5A0` | Ch 11 | Ch 18 |
| 30 | `[lit]`      | ( -- n ) parse word, push n (IMM)  | `0x5C1` | Ch 1  | Ch 18 |
| 31 | `branch`     | ( -- ) inline target              | `0x611` | Ch 11 | Ch 19 |
| 32 | `0branch`    | ( flag -- ) inline target         | `0x628` | Ch 11 | Ch 19 |

## Internal routines (not user-visible)

These exist in `000-seed.hex0` but have no dictionary entry, so the
REPL cannot call them by name.  They are reached only from other
routines.

| Routine | Stack effect | Code @ | Called by | Asm site |
|---|---|---|---|---|
| `read_word`          | ( -- c-addr u ); `u` = 0 at EOF, `u` also in `rbx` | `0x3C1` | REPL, `:`, `[lit]`, `'` | Ch 17 |
| `read_char`          | ( -- ); next byte in `rdx`, ZF = whitespace | `0x436` | `read_word` | Ch 17 |
| `report_token`       | ( -- ); prints the last token and `?`        | `0x459` | REPL (miss), `fatal_token` | Ch 17 |
| `fatal_token`        | ( -- ); `report_token`, then exit status 2   | `0x477` | `read_word` (token too long), `[lit]` (not a number) | Ch 17 |
| `compile_call`       | ( xt -- ); `CALL xt` at HERE                 | `0x56D` | REPL (compile mode), `[lit]` | Ch 18 |
| `parse_decimal_code` | ( c-addr u -- n true &#124; 0 false )        | `0x644` | `[lit]`, at parse time | Ch 20 |
| `repl`               | never returns                                | `0x699` | `_start` (jump) | Ch 20 |

`bracket_lit_code` at `0x5C1` is not a helper: it is the code of
primitive #30, `[lit]`, and its address is `[lit]`'s xt.

## What is *not* a primitive

These look like primitives but are colon definitions in
`010-lib.fth`:

- `over`, `nip`, `rot`, `2dup`, `2drop`: stack shufflers, Ch 8.
- `-`, `=`, `<>`, `<`, `>`, `<=`, `>=`: derived from `+`, `nand`,
  `/`, `0=`.  Chs 4, 7.
- `and`, `or`, `not`: derived from `nand`.  Ch 3.
- `digit?`, `alpha?`, `space?`: Ch 6.
- `+!`, `-!`, `,4`, `,8`: Ch 9.
- `immediate`, `ret,`, `push-imm64,`, `push-body,`, `constant`, `call,`,
  `char`, `[char]`: Ch 10.
- `if,`, `then,`, `else,`, `begin,`, `while,`, `repeat,`, `until,`,
  `again,`, `exit,`, `branch-xt`, `0branch-xt`: Ch 11.
- `allot`, `skip-vm-pages`, `create`, `variable`, `token`, `bytes,`, `s,`,
  `bytes-eq`: Ch 12.

The boundary between "primitive" and "library word" is exactly the
boundary between `000-seed.hex0` and `010-lib.fth`.  Once `010-lib.fth`
loads, the dictionary contains both, indistinguishable to user code.

## Total byte budget

The 32 primitives' code comes to 760 bytes, and the six helpers
(`read_word` 117, `read_char` 35, `report_token` 30, `fatal_token`
17, `compile_call` 38, `parse_decimal_code` 85) to another 322, about
1.0 KiB in all of the 1,772-byte seed.  The remainder is the ELF
and program headers (120 bytes), `_start` (13), the sysvar init
(48), the `jmp repl` (5), the REPL (83 bytes; Ch 20), and the 32
dictionary headers (421 bytes).  Each header is `link(8) flags(1)
name-len(1) name(N)`, or `10 + len(name)` bytes, and sits directly
in front of its word's code.  Appendix B gives the full memory map.

## A note on the sysvar page

The seed keeps four sysvars, consecutive 8-byte cells from
`0x413000`: `STATE`, `LATEST`, `HERE` and `LAST_FOUND`.  The rest of
the 4 KiB page is unused.  Only two addresses are exported, by the
`state` and `latest` primitives; `010-lib.fth` finds `HERE`'s cell
as `latest [lit] 8 +` and the first free page above the seed's fixed
pages as `state [lit] 4096 +` (`skip-vm-pages`), so no Forth file
types in a seed address, and that cell order is the contract between
the seed and the library.
