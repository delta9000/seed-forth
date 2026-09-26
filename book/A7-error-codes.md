# Appendix G — Compiler error codes

When the compiler cannot go on, it stops in `cc-die` (Ch 21), which
writes one line to stderr and exits:

```text
cc: line 2: error 30
```

The number after `error` is also the process's exit status, so a
script can read it with `echo $?`.  This appendix maps every code to
the call site that produces it: grep the owning file for
`[lit] 30 cc-die` (or `cc-check-cap` / `cc-read-all`, which die with
the code they are given) and read the few lines above it.

**The line** is `cc-src-line`, the line the reader had reached, in
the *preprocessed* source: the text the lexer reads, with
`#include "..."` files spliced in (Ch 22).  Directive lines keep their
newline, so for a program with no `#include` it is the line in your
file.  After an include it is a line of the flattened program; to map
it back, subtract the included files' lines.  A failure inside the
preprocessor reports the line of its output it had reached, and one
before any source is read reports line 1.

## How the codes are organised

Each compiler file owns a range, so a code names one file, and, for
the files that follow the plan, one failure:

| File | Range | What breaks there |
|---|---|---|
| `000-seed.hex0`     | 2       | The seed rejects a token while loading the Forth (below). |
| `020-cc-arena.fth`  | 10–19   | Arena allocator out of memory. |
| `030-cc-io.fth`     | 20–29   | Input, output buffer, output file. |
| `040-cc-prep.fth`   | 30–39   | Preprocessor: includes, macros, preprocessed size. |
| `050-cc-lex.fth`    | 40–49   | Lexer (no failures yet). |
| `060-cc-types.fth`  | 50–59   | Struct descriptors. |
| `070-cc-sym.fth`    | 60–69   | Symbol table and scope stack. |
| `080-cc-elf.fth`    | 70–79   | ELF header (no failures yet). |
| `090-cc-emit.fth`   | 80–89   | Codegen capacity. |
| `100-cc-expr.fth`   | 90–139  | Expression parser. |
| `110-cc-decl.fth`   | 140–219 | Declarations, statements, functions. |
| `120-cc-main.fth`   | 220–229 | Driver (no failures yet). |
| `130-asm.fth`       | 230–249 | The M1 assembler, a separate program. |
| tests               | 255     | A `test-*.fth` file's final `0= die`: some check failed. |

`020-cc-arena.fth` through `070-cc-sym.fth` follow this plan: each of
their codes is used at one place, for one failure.
`090-cc-emit.fth`, `100-cc-expr.fth`, `110-cc-decl.fth` and
`130-asm.fth` still carry older numbers that are being moved into
their ranges.  Among those, a code can be shared by two files (41–43,
70, 71, 80, 82, 90–92) or used at several places in one file (38, 73,
82, 95, 163); the table lists every site, and the line `cc-die`
prints tells them apart.  Codes above 100 in `100-cc-expr.fth` and
140–143 in `110-cc-decl.fth` were moved there so as not to collide
with the ranges of 030 and 040.

## Codes in detail

Every die site in `020-cc-arena.fth` through `120-cc-main.fth`, traced
to its call site.  Where one code has several sites, the row lists
all of them, one per cited line.

| Code | File:line(s) | Triggered by |
|---:|---|---|
| 10  | `020-cc-arena.fth:96` | `cc-alloc` past the 32 KiB arena cap. |
| 11  | `110-cc-decl.fth:48`  | `cc-expect-kw-id`: next token wasn't a keyword. |
| 12  | `110-cc-decl.fth:51`  | `cc-expect-kw-id`: keyword id mismatch. |
| 13  | `110-cc-decl.fth:59`  | `cc-expect-punct-c`: next token wasn't punctuation. |
| 14  | `110-cc-decl.fth:62`  | `cc-expect-punct-c`: punctuation char mismatch. |
| 15  | `110-cc-decl.fth:69`  | `cc-expect-ident`: next token wasn't an identifier. |
| 20  | `030-cc-io.fth:72` | `cc-load-stdin`: the source fills the 1 MiB input buffer. |
| 21  | `030-cc-io.fth:110` | `cc-emit-byte`: the output fills the 1 MiB output buffer. |
| 22  | `030-cc-io.fth:170` | `cc-write-output`: `open(2)` on the output path returned an error. |
| 23  | `110-cc-decl.fth:400` | Local array declaration: size inside `[` `]` isn't an integer literal. |
| 24  | `110-cc-decl.fth:404` | Local array declaration: size is zero or negative. |
| 25  | `110-cc-decl.fth:408` | Local array declaration: missing `]`. |
| 26  | `110-cc-decl.fth:412` | Local array declaration: missing `;` after `]`. |
| 30  | `040-cc-prep.fth:270` | `#include "…"`: file opens neither as given nor under `tests/cc/`. |
| 31  | `040-cc-prep.fth:255` | `#include` nested deeper than the four include-pool slots. |
| 32  | `040-cc-prep.fth:276` | `#include`d file fills its 64 KiB include-pool slot. |
| 33  | `040-cc-prep.fth:216` | `#include` path (with the `tests/cc/` prefix) longer than the 1,024-byte path buffer. |
| 34  | `040-cc-prep.fth:94`  | `cc-macro-add`: more than 256 macros (7 are built in). |
| 35  | `040-cc-prep.fth:75`  | `cc-macro-name-pool-copy`: macro-name pool (16 KiB) full. |
| 36  | `040-cc-prep.fth:44`  | `cc-prep-emit-byte`: preprocessed source fills the 2 MiB source buffer. |
| 37  | `110-cc-decl.fth:1542` | Call: more than six arguments (the register-only calling convention). |
| 38  | `110-cc-decl.fth:1582,1628,1631,1637,1648` | 1582: call target is neither a function nor a function-pointer local.  1628/1631: parameter type is an identifier that isn't a known typedef.  1637: parameter type is neither a keyword nor an identifier.  1648: parameter name missing. |
| 39  | `110-cc-decl.fth:1668` | Parameter list not closed by `)`. |
| 41  | `100-cc-expr.fth:1409` | Assignment: left-hand side isn't an lvalue. |
| 41  | `110-cc-decl.fth:1770` | Function definition: name after the return type isn't an identifier. |
| 42  | `100-cc-expr.fth:1382` | Compound assignment (`+=` etc.) through a pointer, subscript or member lvalue — only plain `=` is supported there. |
| 42  | `110-cc-decl.fth:1736` | Function return type: `struct` not followed by a tag identifier. |
| 43  | `100-cc-expr.fth:1327` | Compound-assignment dispatcher saw an operator it doesn't know (internal; not reachable from valid tokens). |
| 43  | `110-cc-decl.fth:1741` | Function return type: neither a keyword nor an identifier. |
| 44  | `110-cc-decl.fth:2143` | Prototype: name after the return type isn't an identifier. |
| 50  | `060-cc-types.fth:83` | `cc-sd-field-rec`: a struct with more than 16 fields. |
| 51  | `100-cc-expr.fth:767` | Prefix `++`/`--`: identifier not found. |
| 52  | `100-cc-expr.fth:771` | Prefix `++`/`--`: identifier isn't a local. |
| 53  | `100-cc-expr.fth:520` | Postfix `++`/`--`: operand isn't a simple local. |
| 60  | `070-cc-sym.fth:59`   | `cc-sym-add`: more than 4,096 symbols. |
| 61  | `070-cc-sym.fth:119`  | `cc-scope-push`: scopes nested more than 64 deep. |
| 62  | `070-cc-sym.fth:128`  | `cc-scope-pop` with no push to match (a parser bug; no C program reaches it). |
| 70  | `090-cc-emit.fth:1010` | `cc-globals-alloc`: globals buffer (4,096 bytes) full. |
| 70  | `100-cc-expr.fth:794` | Unary `&`: operand isn't an identifier. |
| 71  | `090-cc-emit.fth:1031` | `cc-gfixup-add`: global-fixup table (4,096 entries) full. |
| 71  | `100-cc-expr.fth:799` | Unary `&`: identifier not found. |
| 72  | `100-cc-expr.fth:803` | Unary `&`: identifier isn't a local. |
| 73  | `100-cc-expr.fth:709,738,742` | `sizeof(`: identifier not found (709), found but neither a typedef nor a local (738), or the token is neither a keyword nor an identifier (742). |
| 74  | `100-cc-expr.fth:699` | `sizeof(`: keyword other than `struct`, `int`, `char` or `void`. |
| 75  | `100-cc-expr.fth:747` | `sizeof(...`: missing `)`. |
| 76  | `100-cc-expr.fth:670` | `sizeof`: missing `(`. |
| 77  | `100-cc-expr.fth:678` | `sizeof(struct`: tag isn't an identifier. |
| 78  | `100-cc-expr.fth:682` | `sizeof(struct TAG`: tag not found. |
| 79  | `100-cc-expr.fth:685` | `sizeof(struct TAG`: name isn't a struct tag. |
| 80  | `100-cc-expr.fth:221` | `name[`: array base isn't a local or a global. |
| 80  | `110-cc-decl.fth:1270` | `goto` not followed by an identifier. |
| 81  | `110-cc-decl.fth:1254` | Label defined twice in one function. |
| 82  | `100-cc-expr.fth:271,556` | Subscript: missing `]` (271: `name[i]`; 556: postfix `[` on any expression). |
| 82  | `110-cc-decl.fth:1224` | Label table (64 labels) full. |
| 90  | `100-cc-expr.fth:574` | `.` / `->` on an expression with no known struct descriptor. |
| 90  | `110-cc-decl.fth:1090` | `case` label isn't an integer literal. |
| 91  | `100-cc-expr.fth:591` | `.` / `->` not followed by an identifier (field name). |
| 91  | `110-cc-decl.fth:247` | Struct definition: field type is a keyword other than `int`, `char`, `void` or `struct`. |
| 92  | `100-cc-expr.fth:182` | Field name not found in the struct descriptor. |
| 92  | `110-cc-decl.fth:253` | Struct definition: field type is neither a keyword nor an identifier. |
| 93  | `110-cc-decl.fth:197` | `struct` definition: tag isn't an identifier. |
| 94  | `110-cc-decl.fth:265` | Struct definition: field name missing. |
| 95  | `110-cc-decl.fth:160,180` | `struct` (in a local, parameter, typedef, field or global) not followed by a tag identifier. |
| 96  | `110-cc-decl.fth:165` | `struct TAG`: tag not found (strict lookup: locals, parameters, typedefs). |
| 97  | `110-cc-decl.fth:169` | `struct TAG`: name isn't a struct tag (strict lookup). |
| 98  | `110-cc-decl.fth:501` | Struct local declaration: variable name missing. |
| 99  | `110-cc-decl.fth:536` | Struct-pointer local not followed by `=` or `;`. |
| 100 | `110-cc-decl.fth:1889` | `enum`: enumerator isn't an identifier. |
| 101 | `110-cc-decl.fth:1931` | `enum`: enumerator followed by neither `,` nor `}`. |
| 102 | `110-cc-decl.fth:1898` | `enum`: `=` not followed by an integer literal. |
| 103 | `100-cc-expr.fth:330` | Primary expression: identifier not in the symbol table. |
| 104 | `100-cc-expr.fth:426` | Primary expression: identifier names something that isn't a variable, function or enum constant (a typedef name or struct tag used as a value). |
| 105 | `100-cc-expr.fth:484` | Parenthesised expression: missing `)`. |
| 106 | `100-cc-expr.fth:487` | Primary expression: token can't start one (not a literal, identifier or `(`). |
| 107 | `100-cc-expr.fth:356` | `name(...)` where `name` is neither a function nor a function-pointer local. |
| 108 | `100-cc-expr.fth:1245` | Ternary `?`: missing `:`. |
| 109 | `100-cc-expr.fth:762` | Prefix `++`/`--`: operand isn't an identifier. |
| 110 | `110-cc-decl.fth:1962` | `typedef`: base keyword other than `int`, `char`, `void` or `struct`. |
| 111 | `110-cc-decl.fth:1968` | `typedef`: base identifier not found. |
| 112 | `110-cc-decl.fth:1971` | `typedef`: base identifier isn't itself a typedef. |
| 113 | `110-cc-decl.fth:1975` | `typedef`: base is neither a keyword nor an identifier. |
| 114 | `110-cc-decl.fth:2023` | `typedef`: new name isn't an identifier. |
| 116 | `110-cc-decl.fth:1999` | Function-pointer `typedef T (*NAME)(...)`: name missing. |
| 140 | `110-cc-decl.fth:342` | Function-pointer declarator: expected name. |
| 141 | `110-cc-decl.fth:366` | Function-pointer declarator: expected `=` or `;`. |
| 142 | `110-cc-decl.fth:439` | Local scalar declaration (`T x;` / `T x = e;`) not ended by `;`. |
| 143 | `110-cc-decl.fth:1534` | Call: argument list not closed by `)`. |
| 160 | `110-cc-decl.fth:2262` | Top-level declaration: base type is neither a keyword nor an identifier. |
| 161 | `110-cc-decl.fth:2272` | Top-level declaration: expected variable name. |
| 162 | `110-cc-decl.fth:2286` | Top-level array decl: bracket without integer literal size. |
| 163 | `110-cc-decl.fth:2206,2211` | Global initialiser: expected integer literal (optionally signed). |
| 164 | `110-cc-decl.fth:2306` | Top-level declaration: name followed by neither `[`, `=` nor `;`. |

Code 115 is unused.  Every buffer and table in `020-cc-arena.fth`
through `070-cc-sym.fth` is bounds-checked with `cc-check-cap`, and
`tests/cc/run-gates.sh` has a die gate (`tests/cc/die-NN-*`) that
overflows each one and checks the code and the line.  Not every limit
in the later files is checked yet: Ch 31's 256-byte stack frame, for
one, silently overlaps its neighbour past 32 locals.

When you add a new error site, take the next free code in its file's
range, so the code keeps naming one failure.

### The assembler's codes

`130-asm.fth`, the M1 assembler, is a separate program with its
own codes.  It exits 1 if it can't open its output file
(`130-asm.fth:132`).
Its other failures go through `asm-tok-err`, which, unlike the
compiler, writes the offending token to stderr
before exiting: 91 (`&label` undefined), 92/93 (`%target>base`:
base / target undefined), 94 (`%label`), 95 (`!label`),
96 (`@label`), 97 (`~label`), 98 (`$label`).

### The seed's own code

Before the compiler exists there is one more source of failure: the
seed rejecting a token while it loads the Forth.  A `[lit]` whose
token is not an unsigned decimal number, or any token longer than
255 bytes, makes the seed print the token followed by `?` and exit
with status **2** (`fatal_token`, Ch 17).  No `[lit] 2 die` exists
in the compiler, so a 2 always means the seed gave up, and the last
line on stdout is the token it could not use.  An unknown word is
not fatal: the seed prints it with `?` (`wibble?`) and reads on.

## Why a number and a line, not a message?

A message per site would cost a string per site.  A code keeps each
of the 100-odd error sites to a single `[lit] N cc-die` line, so the
parse code stays short enough to read in the book, and `cc-die`
alone knows how to report.  The line says where in your program to
look; the code says which check fired.  To see what that check
expected:

```sh
grep -nB3 "\[lit\] <code> cc-" *.fth  # find the call site
```

The few lines of context above the `cc-die` show which token the
parser expected.  In nearly every case the answer is "the lexer
saw something other than `T`, `;`, `}`, an identifier, or an
integer literal."
