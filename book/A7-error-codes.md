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

Each compiler file owns a range, so a code names one file, and one
failure in it:

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

Each code is used at one place, for one failure.  A file's codes
were numbered in source order, and a check added since takes the
next free code in its range (193–195 in `110-cc-decl.fth`).  Two
sites that fail the same way still get a code each (145 and 148, for
instance), so a code always names one line.

## Codes in detail

Every die site in `020-cc-arena.fth` through `120-cc-main.fth`, traced
to its call site.

| Code | File:line(s) | Triggered by |
|---:|---|---|
| 10  | `020-cc-arena.fth:96` | `cc-alloc` past the 32 KiB arena cap. |
| 20  | `030-cc-io.fth:72` | `cc-load-stdin`: the source fills the 1 MiB input buffer. |
| 21  | `030-cc-io.fth:110` | `cc-emit-byte`: the output fills the 1 MiB output buffer. |
| 22  | `030-cc-io.fth:170` | `cc-write-output`: `open(2)` on the output path returned an error. |
| 30  | `040-cc-prep.fth:270` | `#include "…"`: file opens neither as given nor under `tests/cc/`. |
| 31  | `040-cc-prep.fth:255` | `#include` nested deeper than the four include-pool slots. |
| 32  | `040-cc-prep.fth:276` | `#include`d file fills its 64 KiB include-pool slot. |
| 33  | `040-cc-prep.fth:216` | `#include` path (with the `tests/cc/` prefix) longer than the 1,024-byte path buffer. |
| 34  | `040-cc-prep.fth:94`  | `cc-macro-add`: more than 256 macros (7 are built in). |
| 35  | `040-cc-prep.fth:75`  | `cc-macro-name-pool-copy`: macro-name pool (16 KiB) full. |
| 36  | `040-cc-prep.fth:44`  | `cc-prep-emit-byte`: preprocessed source fills the 2 MiB source buffer. |
| 50  | `060-cc-types.fth:83` | `cc-sd-field-rec`: a struct with more than 16 fields. |
| 60  | `070-cc-sym.fth:59`   | `cc-sym-add`: more than 4,096 symbols. |
| 61  | `070-cc-sym.fth:119`  | `cc-scope-push`: scopes nested more than 64 deep. |
| 62  | `070-cc-sym.fth:128`  | `cc-scope-pop` with no push to match (a parser bug; no C program reaches it). |
| 80  | `090-cc-emit.fth:1000` | `cc-globals-alloc`: globals buffer (4,096 bytes) full. |
| 81  | `090-cc-emit.fth:1022` | `cc-gfixup-add`: global-fixup table (4,096 entries) full. |
| 90  | `100-cc-expr.fth:187` | Field name not found in the struct descriptor. |
| 91  | `100-cc-expr.fth:226` | `name[`: array base isn't a local or a global. |
| 92  | `100-cc-expr.fth:276` | Subscript `name[i]`: missing `]`. |
| 93  | `100-cc-expr.fth:331` | Primary expression: identifier not in the symbol table. |
| 94  | `100-cc-expr.fth:357` | `name(...)` where `name` is neither a function nor a function-pointer local. |
| 95  | `100-cc-expr.fth:427` | Primary expression: identifier names something that isn't a variable, function or enum constant (a typedef name or struct tag used as a value). |
| 96  | `100-cc-expr.fth:485` | Parenthesised expression: missing `)`. |
| 97  | `100-cc-expr.fth:488` | Primary expression: token can't start one (not a literal, identifier or `(`). |
| 98  | `100-cc-expr.fth:521` | Postfix `++`/`--`: operand isn't a simple local. |
| 99  | `100-cc-expr.fth:554` | Postfix `[` on any expression: missing `]`. |
| 100 | `100-cc-expr.fth:567` | `.` / `->` on an expression with no known struct descriptor. |
| 101 | `100-cc-expr.fth:579` | `.` / `->` not followed by an identifier (field name). |
| 102 | `100-cc-expr.fth:658` | `sizeof`: missing `(`. |
| 103 | `100-cc-expr.fth:666` | `sizeof(struct`: tag isn't an identifier. |
| 104 | `100-cc-expr.fth:670` | `sizeof(struct TAG`: tag not found. |
| 105 | `100-cc-expr.fth:673` | `sizeof(struct TAG`: name isn't a struct tag. |
| 106 | `100-cc-expr.fth:687` | `sizeof(`: keyword other than `struct`, `int`, `char` or `void`. |
| 107 | `100-cc-expr.fth:697` | `sizeof(`: identifier not found. |
| 108 | `100-cc-expr.fth:726` | `sizeof(`: identifier found but neither a typedef nor a local. |
| 109 | `100-cc-expr.fth:730` | `sizeof(`: token is neither a keyword nor an identifier. |
| 110 | `100-cc-expr.fth:735` | `sizeof(...`: missing `)`. |
| 111 | `100-cc-expr.fth:750` | Prefix `++`/`--`: operand isn't an identifier. |
| 112 | `100-cc-expr.fth:755` | Prefix `++`/`--`: identifier not found. |
| 113 | `100-cc-expr.fth:759` | Prefix `++`/`--`: identifier isn't a local. |
| 114 | `100-cc-expr.fth:782` | Unary `&`: operand isn't an identifier. |
| 115 | `100-cc-expr.fth:787` | Unary `&`: identifier not found. |
| 116 | `100-cc-expr.fth:791` | Unary `&`: identifier isn't a local. |
| 117 | `100-cc-expr.fth:1229` | Ternary `?`: missing `:`. |
| 118 | `100-cc-expr.fth:1311` | Compound-assignment dispatcher saw an operator it doesn't know (internal; not reachable from valid tokens). |
| 119 | `100-cc-expr.fth:1367` | Compound assignment (`+=` etc.) through a pointer, subscript or member lvalue — only plain `=` is supported there. |
| 120 | `100-cc-expr.fth:1393` | Assignment: left-hand side isn't an lvalue. |
| 140 | `110-cc-decl.fth:58` | `cc-expect-kw-id`: next token wasn't a keyword. |
| 141 | `110-cc-decl.fth:61` | `cc-expect-kw-id`: keyword id mismatch. |
| 142 | `110-cc-decl.fth:69` | `cc-expect-punct-c`: next token wasn't punctuation. |
| 143 | `110-cc-decl.fth:72` | `cc-expect-punct-c`: punctuation char mismatch. |
| 144 | `110-cc-decl.fth:79` | `cc-expect-ident`: next token wasn't an identifier. |
| 145 | `110-cc-decl.fth:170` | `struct` (in a local, parameter, typedef, field or global) not followed by a tag identifier (`cc-lookup-struct-tag`). |
| 146 | `110-cc-decl.fth:175` | `struct TAG`: tag not found (strict lookup: locals, parameters, typedefs). |
| 147 | `110-cc-decl.fth:179` | `struct TAG`: name isn't a struct tag (strict lookup). |
| 148 | `110-cc-decl.fth:190` | `struct` (in a local, parameter, typedef, field or global) not followed by a tag identifier (`cc-lookup-struct-tag-soft`). |
| 149 | `110-cc-decl.fth:207` | `struct` definition: tag isn't an identifier. |
| 150 | `110-cc-decl.fth:257` | Struct definition: field type is a keyword other than `int`, `char`, `void` or `struct`. |
| 151 | `110-cc-decl.fth:263` | Struct definition: field type is neither a keyword nor an identifier. |
| 152 | `110-cc-decl.fth:275` | Struct definition: field name missing. |
| 153 | `110-cc-decl.fth:352` | Function-pointer declarator: expected name. |
| 154 | `110-cc-decl.fth:376` | Function-pointer declarator: expected `=` or `;`. |
| 155 | `110-cc-decl.fth:410` | Local array declaration: size inside `[` `]` isn't an integer literal. |
| 156 | `110-cc-decl.fth:414` | Local array declaration: size is zero or negative. |
| 157 | `110-cc-decl.fth:418` | Local array declaration: missing `]`. |
| 158 | `110-cc-decl.fth:422` | Local array declaration: missing `;` after `]`. |
| 159 | `110-cc-decl.fth:449` | Local scalar declaration (`T x;` / `T x = e;`) not ended by `;`. |
| 160 | `110-cc-decl.fth:511` | Struct local declaration: variable name missing. |
| 161 | `110-cc-decl.fth:546` | Struct-pointer local not followed by `=` or `;`. |
| 162 | `110-cc-decl.fth:1100` | `case` label isn't an integer literal. |
| 163 | `110-cc-decl.fth:1211` | `cc-label-create`: more than 64 labels in one function. |
| 164 | `110-cc-decl.fth:1240` | Label defined twice in one function. |
| 165 | `110-cc-decl.fth:1256` | `goto` not followed by an identifier. |
| 166 | `110-cc-decl.fth:1512` | Call: argument list not closed by `)`. |
| 167 | `110-cc-decl.fth:1520` | Call: more than six arguments (the register-only calling convention). |
| 168 | `110-cc-decl.fth:1560` | Call target is neither a function nor a function-pointer local (internal: `cc-parse-primary` already checks, with 94). |
| 169 | `110-cc-decl.fth:1606` | Parameter type is an identifier that isn't in the symbol table. |
| 170 | `110-cc-decl.fth:1609` | Parameter type is an identifier that isn't a typedef. |
| 171 | `110-cc-decl.fth:1615` | Parameter type is neither a keyword nor an identifier. |
| 172 | `110-cc-decl.fth:1626` | Parameter name missing. |
| 173 | `110-cc-decl.fth:1646` | Parameter list not closed by `)`. |
| 174 | `110-cc-decl.fth:1714` | Function return type: `struct` not followed by a tag identifier. |
| 175 | `110-cc-decl.fth:1719` | Function return type: neither a keyword nor an identifier. |
| 176 | `110-cc-decl.fth:1749` | Function definition: name after the return type isn't an identifier. |
| 177 | `110-cc-decl.fth:1868` | `enum`: enumerator isn't an identifier. |
| 178 | `110-cc-decl.fth:1877` | `enum`: `=` not followed by an integer literal. |
| 179 | `110-cc-decl.fth:1910` | `enum`: enumerator followed by neither `,` nor `}`. |
| 180 | `110-cc-decl.fth:1941` | `typedef`: base keyword other than `int`, `char`, `void` or `struct`. |
| 181 | `110-cc-decl.fth:1947` | `typedef`: base identifier not found. |
| 182 | `110-cc-decl.fth:1950` | `typedef`: base identifier isn't itself a typedef. |
| 183 | `110-cc-decl.fth:1954` | `typedef`: base is neither a keyword nor an identifier. |
| 184 | `110-cc-decl.fth:1978` | Function-pointer `typedef T (*NAME)(...)`: name missing. |
| 185 | `110-cc-decl.fth:2002` | `typedef`: new name isn't an identifier. |
| 186 | `110-cc-decl.fth:2110` | Prototype: name after the return type isn't an identifier. |
| 187 | `110-cc-decl.fth:2172` | Global initialiser: `-` not followed by an integer literal. |
| 188 | `110-cc-decl.fth:2177` | Global initialiser: not an integer literal. |
| 189 | `110-cc-decl.fth:2228` | Top-level declaration: base type is neither a keyword nor an identifier. |
| 190 | `110-cc-decl.fth:2238` | Top-level declaration: expected variable name. |
| 191 | `110-cc-decl.fth:2252` | Top-level array decl: bracket without integer literal size. |
| 192 | `110-cc-decl.fth:2272` | Top-level declaration: name followed by neither `[`, `=` nor `;`. |
| 193 | `110-cc-decl.fth:37` | `cc-fn-add-slots`: a function's parameters and locals need more than the 32 slots of its 256-byte frame. |
| 194 | `110-cc-decl.fth:2579` | `cc-check-fns-defined`: at the end of the program, a function that was called or used as a value was never defined (its call or address fixups are still pending).  `memset` is declared but has no body, so a program that uses it lands here. |
| 195 | `110-cc-decl.fth:2584` | `cc-check-fns-defined`: at the end of the program, there is no `main`. |

Every buffer and table the compiler fills is bounds-checked with
`cc-check-cap` (or `cc-read-all` for input), and
`tests/cc/run-gates.sh` has a die gate (`tests/cc/die-NN-*`) that
overflows each one and checks the code and the line; so do the three
whole-program checks, 193 (a function that needs more than its
frame's 32 slots, Ch 31), 194 and 195.  The gates cannot reach 22
(the output file won't open) or 62 (a parser bug).

When you add a new error site, take the next free code in its file's
range, so the code keeps naming one failure.

### The assembler's codes

`130-asm.fth`, the M1 assembler, is a separate program: it loads
none of the compiler's files, so it has its own `asm-check-cap`
(the same test as `cc-check-cap`, dying with a bare `die`) and prints
no line number.  An undefined label goes through `asm-tok-err`, which
writes the offending token to stderr before exiting.
`tests/asm/die-gates.sh` overflows each buffer and table and feeds
one undefined label.

| Code | File:line(s) | Triggered by |
|---:|---|---|
| 230 | `130-asm.fth:145` | `asm-write-output`: `open(2)` on `/tmp/asm-out` returned an error. |
| 231 | `130-asm.fth:434` | `&label` (4-byte absolute) undefined. |
| 232 | `130-asm.fth:462` | `%target>base`: base label undefined. |
| 233 | `130-asm.fth:465` | `%target>base`: target label undefined. |
| 234 | `130-asm.fth:475` | `%label` (4-byte relative) undefined. |
| 235 | `130-asm.fth:499` | `!label` (1-byte relative) undefined. |
| 236 | `130-asm.fth:522` | `@label` (2-byte relative) undefined. |
| 237 | `130-asm.fth:545` | `~label` (3-byte relative) undefined. |
| 238 | `130-asm.fth:567` | `$label` (2-byte absolute) undefined. |
| 239 | `130-asm.fth:88` | `asm-load-stdin`: the M1 source fills the 4 MiB source buffer. |
| 240 | `130-asm.fth:110` | `asm-exp-emit-byte`: macro expansion fills the 4 MiB expansion buffer. |
| 241 | `130-asm.fth:125` | `asm-emit-byte`: the output fills the 1 MiB output buffer. |
| 242 | `130-asm.fth:181` | `asm-store-label`: more than 8,192 labels. |
| 243 | `130-asm.fth:660` | `asm-def-store`: more than 4,096 `DEFINE`s. |

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
