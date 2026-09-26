# Appendix G — Compiler exit codes

The compiler has no string diagnostics.  When something goes wrong
it prints nothing, calls `die`, and the process exits with a
numeric status that you read from the shell with `echo $?`.

This appendix maps every status code to the `die` call site that
produces it, so you can shortcut "the compiler died with exit 37;
grep for `37 die` in the source" into "a call passed more than six
arguments."  Each row points to the file and line where that code
lives; the source is the final authority.

## How the codes are organised

There is no single grand scheme.  Codes were assigned in the order
helpers were added, each file picked its own, and several numbers
are reused across files and, in a few places, twice inside one
file.  So an exit code alone does not name a failure; the code plus
the phase you were in does.  This is where each file's codes live:

| File | Codes | What broke |
|---|---|---|
| `020-cc-arena.fth`  | 7 | Arena allocator out of memory (32 KiB cap). |
| `030-cc-io.fth`     | 1 | Opening the output file failed. |
| `040-cc-prep.fth`   | 70–72 | Preprocessor: `#include` open failure, include depth, macro-name pool. |
| `090-cc-emit.fth`   | 70–71 | Codegen capacity: globals buffer, global-fixup table. |
| `100-cc-expr.fth`   | 30–35, 41–43, 50–53, 70–80, 82, 90–92 | Expression parser: primaries, calls, ternary, assignment, prefix/postfix `++`/`--`, unary `&`, `sizeof`, subscripts, `.`/`->`. |
| `110-cc-decl.fth`   | 11–15, 22–26, 36–39, 41–44, 80–82, 90–102, 110–116, 140–141, 160–164 | Token-expectation helpers, local declarations, call arguments, parameters, function headers, labels and `goto`, `switch`, structs, enums, typedefs, function-pointer declarators, globals. |

## Codes in detail

Every `[lit] N die` in `020-cc-arena.fth` through `120-cc-main.fth`,
traced to its call site.  Where one code has several meanings,
the row lists all of them, one per cited line.

| Exit | File:line(s) | Triggered by |
|---:|---|---|
|  1  | `030-cc-io.fth:147`   | `cc-write-output`: `open(2)` on the output path returned an error. |
|  7  | `020-cc-arena.fth:39` | `cc-alloc` past the 32 KiB arena cap. |
| 11  | `110-cc-decl.fth:48`  | `cc-expect-kw-id`: next token wasn't a keyword. |
| 12  | `110-cc-decl.fth:51`  | `cc-expect-kw-id`: keyword id mismatch. |
| 13  | `110-cc-decl.fth:59`  | `cc-expect-punct-c`: next token wasn't punctuation. |
| 14  | `110-cc-decl.fth:62`  | `cc-expect-punct-c`: punctuation char mismatch. |
| 15  | `110-cc-decl.fth:69`  | `cc-expect-ident`: next token wasn't an identifier. |
| 22  | `110-cc-decl.fth:468` | Local scalar declaration (`T x;` / `T x = e;`) not ended by `;`. |
| 23  | `110-cc-decl.fth:429` | Local array declaration: size inside `[` `]` isn't an integer literal. |
| 24  | `110-cc-decl.fth:433` | Local array declaration: size is zero or negative. |
| 25  | `110-cc-decl.fth:437` | Local array declaration: missing `]`. |
| 26  | `110-cc-decl.fth:441` | Local array declaration: missing `;` after `]`. |
| 30  | `100-cc-expr.fth:364` | Primary expression: identifier not in the symbol table. |
| 31  | `100-cc-expr.fth:460` | Primary expression: identifier names something that isn't a variable, function or enum constant (a typedef name or struct tag used as a value). |
| 32  | `100-cc-expr.fth:518` | Parenthesised expression: missing `)`. |
| 33  | `100-cc-expr.fth:521` | Primary expression: token can't start one (not a literal, identifier or `(`). |
| 34  | `100-cc-expr.fth:390` | `name(...)` where `name` is neither a function nor a function-pointer local. |
| 35  | `100-cc-expr.fth:1279` | Ternary `?`: missing `:`. |
| 36  | `110-cc-decl.fth:1611` | Call: argument list not closed by `)`. |
| 37  | `110-cc-decl.fth:1619` | Call: more than six arguments (the register-only calling convention). |
| 38  | `110-cc-decl.fth:1659,1709,1712,1718,1729` | 1659: call target is neither a function nor a function-pointer local.  1709/1712: parameter type is an identifier that isn't a known typedef.  1718: parameter type is neither a keyword nor an identifier.  1729: parameter name missing. |
| 39  | `110-cc-decl.fth:1754` | Parameter list not closed by `)`. |
| 41  | `100-cc-expr.fth:1443` | Assignment: left-hand side isn't an lvalue. |
| 41  | `110-cc-decl.fth:1887` | Function definition: name after the return type isn't an identifier. |
| 42  | `100-cc-expr.fth:1416` | Compound assignment (`+=` etc.) through a pointer, subscript or member lvalue — only plain `=` is supported there. |
| 42  | `110-cc-decl.fth:1853` | Function return type: `struct` not followed by a tag identifier. |
| 43  | `100-cc-expr.fth:1361` | Compound-assignment dispatcher saw an operator it doesn't know (internal; not reachable from valid tokens). |
| 43  | `110-cc-decl.fth:1858` | Function return type: neither a keyword nor an identifier. |
| 44  | `110-cc-decl.fth:2300` | Prototype: name after the return type isn't an identifier. |
| 50  | `100-cc-expr.fth:796` | Prefix `++`/`--`: operand isn't an identifier. |
| 51  | `100-cc-expr.fth:801` | Prefix `++`/`--`: identifier not found. |
| 52  | `100-cc-expr.fth:805` | Prefix `++`/`--`: identifier isn't a local. |
| 53  | `100-cc-expr.fth:554` | Postfix `++`/`--`: operand isn't a simple local. |
| 70  | `040-cc-prep.fth:320` | `#include`: file opens neither as given nor under `tests/cc/`. |
| 70  | `090-cc-emit.fth:1010` | `cc-globals-alloc`: globals buffer (4,096 bytes) full. |
| 70  | `100-cc-expr.fth:828` | Unary `&`: operand isn't an identifier. |
| 71  | `040-cc-prep.fth:304` | `#include` nested deeper than the four include-pool slots. |
| 71  | `090-cc-emit.fth:1032` | `cc-gfixup-add`: global-fixup table (4,096 entries) full. |
| 71  | `100-cc-expr.fth:833` | Unary `&`: identifier not found. |
| 72  | `040-cc-prep.fth:73`  | `cc-macro-name-pool-copy`: macro-name pool (16 KiB) full. |
| 72  | `100-cc-expr.fth:837` | Unary `&`: identifier isn't a local. |
| 73  | `100-cc-expr.fth:743,772,776` | `sizeof(`: identifier not found (743), found but neither a typedef nor a local (772), or the token is neither a keyword nor an identifier (776). |
| 74  | `100-cc-expr.fth:733` | `sizeof(`: keyword other than `struct`, `int`, `char` or `void`. |
| 75  | `100-cc-expr.fth:781` | `sizeof(...`: missing `)`. |
| 76  | `100-cc-expr.fth:704` | `sizeof`: missing `(`. |
| 77  | `100-cc-expr.fth:712` | `sizeof(struct`: tag isn't an identifier. |
| 78  | `100-cc-expr.fth:716` | `sizeof(struct TAG`: tag not found. |
| 79  | `100-cc-expr.fth:719` | `sizeof(struct TAG`: name isn't a struct tag. |
| 80  | `100-cc-expr.fth:254` | `name[`: array base isn't a local or a global. |
| 80  | `110-cc-decl.fth:1309` | `goto` not followed by an identifier. |
| 81  | `110-cc-decl.fth:1293` | Label defined twice in one function. |
| 82  | `100-cc-expr.fth:304,590` | Subscript: missing `]` (304: `name[i]`; 590: postfix `[` on any expression). |
| 82  | `110-cc-decl.fth:1263` | Label table (64 labels) full. |
| 90  | `100-cc-expr.fth:608` | `.` / `->` on an expression with no known struct descriptor. |
| 90  | `110-cc-decl.fth:1122` | `case` label isn't an integer literal. |
| 91  | `100-cc-expr.fth:625` | `.` / `->` not followed by an identifier (field name). |
| 91  | `110-cc-decl.fth:250` | Struct definition: field type is a keyword other than `int`, `char`, `void` or `struct`. |
| 92  | `100-cc-expr.fth:213` | Field name not found in the struct descriptor. |
| 92  | `110-cc-decl.fth:256` | Struct definition: field type is neither a keyword nor an identifier. |
| 93  | `110-cc-decl.fth:200` | `struct` definition: tag isn't an identifier. |
| 94  | `110-cc-decl.fth:268` | Struct definition: field name missing. |
| 95  | `110-cc-decl.fth:163,183` | `struct` (in a local, parameter, typedef, field or global) not followed by a tag identifier. |
| 96  | `110-cc-decl.fth:168` | `struct TAG`: tag not found (strict lookup: locals, parameters, typedefs). |
| 97  | `110-cc-decl.fth:172` | `struct TAG`: name isn't a struct tag (strict lookup). |
| 98  | `110-cc-decl.fth:533` | Struct local declaration: variable name missing. |
| 99  | `110-cc-decl.fth:568` | Struct-pointer local not followed by `=` or `;`. |
| 100 | `110-cc-decl.fth:2010` | `enum`: enumerator isn't an identifier. |
| 101 | `110-cc-decl.fth:2052` | `enum`: enumerator followed by neither `,` nor `}`. |
| 102 | `110-cc-decl.fth:2019` | `enum`: `=` not followed by an integer literal. |
| 110 | `110-cc-decl.fth:2083` | `typedef`: base keyword other than `int`, `char`, `void` or `struct`. |
| 111 | `110-cc-decl.fth:2089` | `typedef`: base identifier not found. |
| 112 | `110-cc-decl.fth:2092` | `typedef`: base identifier isn't itself a typedef. |
| 113 | `110-cc-decl.fth:2096` | `typedef`: base is neither a keyword nor an identifier. |
| 114 | `110-cc-decl.fth:2144` | `typedef`: new name isn't an identifier. |
| 116 | `110-cc-decl.fth:2120` | Function-pointer `typedef T (*NAME)(...)`: name missing. |
| 140 | `110-cc-decl.fth:371` | Function-pointer declarator: expected name. |
| 141 | `110-cc-decl.fth:395` | Function-pointer declarator: expected `=` or `;`. |
| 160 | `110-cc-decl.fth:2419` | Top-level declaration: base type is neither a keyword nor an identifier. |
| 161 | `110-cc-decl.fth:2429` | Top-level declaration: expected variable name. |
| 162 | `110-cc-decl.fth:2443` | Top-level array decl: bracket without integer literal size. |
| 163 | `110-cc-decl.fth:2363,2368` | Global initialiser: expected integer literal (optionally signed). |
| 164 | `110-cc-decl.fth:2463` | Top-level declaration: name followed by neither `[`, `=` nor `;`. |

Code 115 is unused.  Some capacity limits have no code at all: a
struct descriptor has room for 16 fields and the macro table for
256 macros, and neither is bounds-checked — overflowing them
corrupts memory instead of exiting.

When you add a new error site, pick a code that is free in that
file; assignments are file-local, not project-global.

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

## Why no diagnostic text?

Nothing in the seed forbids it.  `die` is an ordinary Forth word in
`010-lib.fth`, and the assembler above shows a message costs two
`write` calls.  The compiler simply never needed one: its one real
input is M2-Planet, and a failure there is a compiler bug you debug
with the source open anyway.  A numeric code keeps each of the
90-odd error sites to a single `[lit] N die` line, so the parse
code stays short enough to read in the book.  The price is two
minutes of grepping and, because codes are reused, reading the
few lines around each hit.

For richer diagnostics, the canonical workflow is:

```sh
echo $?                              # see the exit status
grep -nB3 "\[lit\] <code> die" *.fth  # find the call site
```

The few lines of context above the `die` show which token the
parser expected.  In nearly every case the answer is "the lexer
saw something other than `T`, `;`, `}`, an identifier, or an
integer literal."
