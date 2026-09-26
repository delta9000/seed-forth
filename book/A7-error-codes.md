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
| `110-cc-decl.fth`   | 140–169 | Declarations and the frame's slot limit. |
| `112-cc-stmt.fth`   | 170–179 | Statements: `case`, labels, `goto`. |
| `114-cc-func.fth`   | 180–189 | Parameters and function definitions. |
| `116-cc-prog.fth`   | 190–219 | Enums, typedefs, prototypes, globals, and the whole-program check. |
| `120-cc-main.fth`   | 220–229 | Driver (no failures yet). |
| `130-asm.fth`       | 230–249 | The M1 assembler, a separate program. |
| tests               | 255     | A `test-*.fth` file's final `0= die`: some check failed. |

Each code is used at one place, for one failure.  A file's codes
were numbered in source order, and a check added since takes the
next free code in its range (162 for the frame limit, 206–207 for
the whole-program check).  The call parser's three codes are
121–123, in `100-cc-expr.fth`'s range, where it lives.  Two
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
| 90  | `100-cc-expr.fth:177` | Field name not found in the struct descriptor. |
| 91  | `100-cc-expr.fth:216` | `name[`: array base isn't a local or a global. |
| 92  | `100-cc-expr.fth:266` | Subscript `name[i]`: missing `]`. |
| 93  | `100-cc-expr.fth:535` | Primary expression: identifier not in the symbol table. |
| 94  | `100-cc-expr.fth:552` | `name(...)` where `name` is neither a function nor a function-pointer local. |
| 95  | `100-cc-expr.fth:571` | Primary expression: identifier names something that isn't a variable, function or enum constant (a typedef name or struct tag used as a value). |
| 96  | `100-cc-expr.fth:582` | Parenthesised expression: missing `)`. |
| 97  | `100-cc-expr.fth:598` | Primary expression: token can't start one (not a literal, identifier or `(`). |
| 98  | `100-cc-expr.fth:607` | Postfix `++`/`--`: operand isn't a simple local. |
| 99  | `100-cc-expr.fth:639` | Postfix `[` on any expression: missing `]`. |
| 100 | `100-cc-expr.fth:653` | `.` / `->` on an expression with no known struct descriptor. |
| 101 | `100-cc-expr.fth:665` | `.` / `->` not followed by an identifier (field name). |
| 102 | `100-cc-expr.fth:764` | `sizeof`: missing `(`. |
| 103 | `100-cc-expr.fth:772` | `sizeof(struct`: tag isn't an identifier. |
| 104 | `100-cc-expr.fth:776` | `sizeof(struct TAG`: tag not found. |
| 105 | `100-cc-expr.fth:779` | `sizeof(struct TAG`: name isn't a struct tag. |
| 106 | `100-cc-expr.fth:793` | `sizeof(`: keyword other than `struct`, `int`, `char` or `void`. |
| 107 | `100-cc-expr.fth:803` | `sizeof(`: identifier not found. |
| 108 | `100-cc-expr.fth:832` | `sizeof(`: identifier found but neither a typedef nor a local. |
| 109 | `100-cc-expr.fth:836` | `sizeof(`: token is neither a keyword nor an identifier. |
| 110 | `100-cc-expr.fth:841` | `sizeof(...`: missing `)`. |
| 111 | `100-cc-expr.fth:856` | Prefix `++`/`--`: operand isn't an identifier. |
| 112 | `100-cc-expr.fth:861` | Prefix `++`/`--`: identifier not found. |
| 113 | `100-cc-expr.fth:865` | Prefix `++`/`--`: identifier isn't a local. |
| 114 | `100-cc-expr.fth:888` | Unary `&`: operand isn't an identifier. |
| 115 | `100-cc-expr.fth:893` | Unary `&`: identifier not found. |
| 116 | `100-cc-expr.fth:897` | Unary `&`: identifier isn't a local. |
| 117 | `100-cc-expr.fth:1295` | Ternary `?`: missing `:`. |
| 118 | `100-cc-expr.fth:1339` | Compound-assignment dispatcher saw an operator it doesn't know (internal; not reachable from valid tokens). |
| 119 | `100-cc-expr.fth:1387` | Compound assignment (`+=` etc.) through a pointer, subscript or member lvalue — only plain `=` is supported there. |
| 120 | `100-cc-expr.fth:1413` | Assignment: left-hand side isn't an lvalue. |
| 121 | `100-cc-expr.fth:352` | Call: argument list not closed by `)`. |
| 122 | `100-cc-expr.fth:360` | Call: more than six arguments (the register-only calling convention). |
| 123 | `100-cc-expr.fth:400` | Call target is neither a function nor a function-pointer local (internal: `cc-parse-primary` already checks, with 94). |
| 140 | `110-cc-decl.fth:50` | `cc-expect-kw-id`: next token wasn't a keyword. |
| 141 | `110-cc-decl.fth:53` | `cc-expect-kw-id`: keyword id mismatch. |
| 142 | `110-cc-decl.fth:61` | `cc-expect-punct-c`: next token wasn't punctuation. |
| 143 | `110-cc-decl.fth:64` | `cc-expect-punct-c`: punctuation char mismatch. |
| 144 | `110-cc-decl.fth:71` | `cc-expect-ident`: next token wasn't an identifier. |
| 145 | `110-cc-decl.fth:162` | `struct` (in a local, parameter, typedef, field or global) not followed by a tag identifier (`cc-lookup-struct-tag`). |
| 146 | `110-cc-decl.fth:167` | `struct TAG`: tag not found (strict lookup: locals, parameters, typedefs). |
| 147 | `110-cc-decl.fth:171` | `struct TAG`: name isn't a struct tag (strict lookup). |
| 148 | `110-cc-decl.fth:182` | `struct` (in a local, parameter, typedef, field or global) not followed by a tag identifier (`cc-lookup-struct-tag-soft`). |
| 149 | `110-cc-decl.fth:199` | `struct` definition: tag isn't an identifier. |
| 150 | `110-cc-decl.fth:249` | Struct definition: field type is a keyword other than `int`, `char`, `void` or `struct`. |
| 151 | `110-cc-decl.fth:255` | Struct definition: field type is neither a keyword nor an identifier. |
| 152 | `110-cc-decl.fth:267` | Struct definition: field name missing. |
| 153 | `110-cc-decl.fth:344` | Function-pointer declarator: expected name. |
| 154 | `110-cc-decl.fth:368` | Function-pointer declarator: expected `=` or `;`. |
| 155 | `110-cc-decl.fth:402` | Local array declaration: size inside `[` `]` isn't an integer literal. |
| 156 | `110-cc-decl.fth:406` | Local array declaration: size is zero or negative. |
| 157 | `110-cc-decl.fth:410` | Local array declaration: missing `]`. |
| 158 | `110-cc-decl.fth:414` | Local array declaration: missing `;` after `]`. |
| 159 | `110-cc-decl.fth:441` | Local scalar declaration (`T x;` / `T x = e;`) not ended by `;`. |
| 160 | `110-cc-decl.fth:503` | Struct local declaration: variable name missing. |
| 161 | `110-cc-decl.fth:538` | Struct-pointer local not followed by `=` or `;`. |
| 162 | `110-cc-decl.fth:28` | `cc-fn-add-slots`: a function's parameters and locals need more than the 32 slots of its 256-byte frame. |
| 170 | `112-cc-stmt.fth:504` | `case` label isn't an integer literal. |
| 171 | `112-cc-stmt.fth:615` | `cc-label-create`: more than 64 labels in one function. |
| 172 | `112-cc-stmt.fth:644` | Label defined twice in one function. |
| 173 | `112-cc-stmt.fth:660` | `goto` not followed by an identifier. |
| 180 | `114-cc-func.fth:74` | Parameter type is an identifier that isn't in the symbol table. |
| 181 | `114-cc-func.fth:77` | Parameter type is an identifier that isn't a typedef. |
| 182 | `114-cc-func.fth:83` | Parameter type is neither a keyword nor an identifier. |
| 183 | `114-cc-func.fth:94` | Parameter name missing. |
| 184 | `114-cc-func.fth:114` | Parameter list not closed by `)`. |
| 185 | `114-cc-func.fth:182` | Function return type: `struct` not followed by a tag identifier. |
| 186 | `114-cc-func.fth:187` | Function return type: neither a keyword nor an identifier. |
| 187 | `114-cc-func.fth:217` | Function definition: name after the return type isn't an identifier. |
| 190 | `116-cc-prog.fth:53` | `enum`: enumerator isn't an identifier. |
| 191 | `116-cc-prog.fth:62` | `enum`: `=` not followed by an integer literal. |
| 192 | `116-cc-prog.fth:95` | `enum`: enumerator followed by neither `,` nor `}`. |
| 193 | `116-cc-prog.fth:126` | `typedef`: base keyword other than `int`, `char`, `void` or `struct`. |
| 194 | `116-cc-prog.fth:132` | `typedef`: base identifier not found. |
| 195 | `116-cc-prog.fth:135` | `typedef`: base identifier isn't itself a typedef. |
| 196 | `116-cc-prog.fth:139` | `typedef`: base is neither a keyword nor an identifier. |
| 197 | `116-cc-prog.fth:163` | Function-pointer `typedef T (*NAME)(...)`: name missing. |
| 198 | `116-cc-prog.fth:187` | `typedef`: new name isn't an identifier. |
| 199 | `116-cc-prog.fth:295` | Prototype: name after the return type isn't an identifier. |
| 200 | `116-cc-prog.fth:357` | Global initialiser: `-` not followed by an integer literal. |
| 201 | `116-cc-prog.fth:362` | Global initialiser: not an integer literal. |
| 202 | `116-cc-prog.fth:413` | Top-level declaration: base type is neither a keyword nor an identifier. |
| 203 | `116-cc-prog.fth:423` | Top-level declaration: expected variable name. |
| 204 | `116-cc-prog.fth:437` | Top-level array decl: bracket without integer literal size. |
| 205 | `116-cc-prog.fth:457` | Top-level declaration: name followed by neither `[`, `=` nor `;`. |
| 206 | `116-cc-prog.fth:764` | `cc-check-fns-defined`: at the end of the program, a function that was called or used as a value was never defined (its call or address fixups are still pending).  `memset` is declared but has no body, so a program that uses it lands here. |
| 207 | `116-cc-prog.fth:769` | `cc-check-fns-defined`: at the end of the program, there is no `main`. |

Every buffer and table the compiler fills is bounds-checked with
`cc-check-cap` (or `cc-read-all` for input), and
`tests/cc/run-gates.sh` has a die gate (`tests/cc/die-NN-*`) that
overflows each one and checks the code and the line; so do the three
whole-program checks, 162 (a function that needs more than its
frame's 32 slots, Ch 31), 206 and 207.  The gates cannot reach 22
(the output file won't open) or 62 (a parser bug).

When you add a new error site, take the next free code in its file's
range, so the code keeps naming one failure.

### The assembler's codes

`130-asm.fth`, the M1 assembler, is a separate program: it loads
none of the compiler's files, so it has its own `asm-check-cap`
(the same test as `cc-check-cap`, dying with a bare `die`) and prints
no line number.  A sigil token naming an undefined label goes
through `asm-tok-err`, which writes the offending token to stderr
before exiting; `asm-process-token` hands each sigil's code to
`asm-do-ref`.  `tests/asm/die-gates.sh` overflows each buffer and
table and feeds each sigil an undefined label.  Ch 33 walks every
site below (§13 groups them), and names what the assembler does
*not* check.

| Code | File:line(s) | Triggered by |
|---:|---|---|
| 230 | `130-asm.fth:138` | `asm-write-output`: `open(2)` on `/tmp/asm-out` returned an error. |
| 231 | `130-asm.fth:497` | `&label` (4-byte absolute) undefined. |
| 232 | `130-asm.fth:459` | `%target>base`: base label undefined. |
| 233 | `130-asm.fth:453` | `%target>base`: target label undefined. |
| 234 | `130-asm.fth:465` | `%label` (4-byte relative) undefined. |
| 235 | `130-asm.fth:492` | `!label` (1-byte relative) undefined. |
| 236 | `130-asm.fth:493` | `@label` (2-byte relative) undefined. |
| 237 | `130-asm.fth:494` | `~label` (3-byte relative) undefined. |
| 238 | `130-asm.fth:496` | `$label` (2-byte absolute) undefined. |
| 239 | `130-asm.fth:88` | `asm-load-stdin`: the M1 source fills the 4 MiB source buffer. |
| 240 | `130-asm.fth:110` | `asm-exp-emit-byte`: macro expansion fills the 4 MiB expansion buffer. |
| 241 | `130-asm.fth:125` | `asm-emit-byte`: the output fills the 1 MiB output buffer. |
| 242 | `130-asm.fth:174` | `asm-store-label`: more than 8,192 labels. |
| 243 | `130-asm.fth:535` | `asm-def-store`: more than 4,096 `DEFINE`s. |

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
