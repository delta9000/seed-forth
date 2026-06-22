# Appendix G — Compiler exit codes

The compiler has no string diagnostics.  When something goes wrong
it prints nothing, calls `die`, and the process exits with a
numeric status that you read from the shell with `echo $?`.

This appendix maps the status codes to the categories of failure
they represent, so you can shortcut "the compiler died with exit
74; grep for `74 die` in the source" into "expected a struct tag
after `->`."  Each row points to the file where that code lives;
the source is the final authority.

## How the codes are organised

There is no single grand scheme — codes were assigned in the order
helpers were added, and the ranges drift.  But there is a rough
correspondence between the *range* and the *file*:

| Range | Mostly from | What broke |
|------:|---|---|
|  1    | `030-cc-io.fth`     | I/O on the output file (open / write). |
|  7    | `020-cc-arena.fth`  | Arena allocator out of memory (32 KiB cap). |
| 11–15 | `110-cc-decl.fth`   | A token-expectation helper saw the wrong kind. |
| 22–26 | `110-cc-decl.fth`   | A struct-local declaration was malformed. |
| 30–44 | `100-cc-expr.fth`   | Expression parser: unexpected token, lookup miss, wrong arity. |
| 50–53 | `100-cc-expr.fth`   | Address-of / dereference applied to a non-lvalue. |
| 70–79 | `040-cc-prep.fth`, `090-cc-emit.fth`, `100-cc-expr.fth` | Preprocessor I/O, codegen capacity, or struct/sizeof path. |
| 80–92 | `100-cc-expr.fth`, `110-cc-decl.fth` | Assignment / lvalue / struct-field paths. |
| 93–99 | `110-cc-decl.fth`   | Struct definition: wrong syntax, too many fields. |
| 100–116 | `110-cc-decl.fth` | Function-definition and parameter parsing. |
| 140–141 | `110-cc-decl.fth` | Function-pointer declarator (`T (*name)(args)`). |
| 160–164 | `110-cc-decl.fth` | Top-level global declaration. |

## Codes in detail

Every code that actually fires on a malformed input, traced to
the `die` call site that produces it.  The table is not strictly
exhaustive — a few rare paths are summarised by range rather than
listed individually — but a `grep -n "\[lit\] CODE die" *-cc-*.fth`
with the missing number will find any code this table doesn't:

| Exit | File:line(s) | Triggered by |
|---:|---|---|
|  1  | `030-cc-io.fth:147`   | `cc-write-output`: `write(2)` returned an error. |
|  7  | `020-cc-arena.fth:39` | `cc-alloc` past the 32 KiB arena cap. |
| 11  | `110-cc-decl.fth:48`  | `cc-expect-kw-id`: next token wasn't a keyword. |
| 12  | `110-cc-decl.fth:51`  | `cc-expect-kw-id`: keyword id mismatch. |
| 13  | `110-cc-decl.fth:59`  | `cc-expect-punct-c`: next token wasn't punctuation. |
| 14  | `110-cc-decl.fth:62`  | `cc-expect-punct-c`: punctuation char mismatch. |
| 15  | `110-cc-decl.fth:69`  | `cc-expect-ident`: next token wasn't an identifier. |
| 30  | `100-cc-expr.fth:364` | Primary expression: identifier not in symbol table. |
| 31  | `100-cc-expr.fth:460` | Postfix `[`: indexed identifier isn't a local. |
| 32  | `100-cc-expr.fth:518` | Postfix `[`: missing `]`. |
| 33  | `100-cc-expr.fth:521` | Postfix `[`: index expression malformed. |
| 34  | `100-cc-expr.fth:390` | Function call on a non-function symbol. |
| 50  | `100-cc-expr.fth:796` | Unary `&`: operand was not an lvalue. |
| 51  | `100-cc-expr.fth:801` | Unary `*`: operand was not a pointer-typed rvalue. |
| 53  | `100-cc-expr.fth:554` | Postfix `++` / `--`: operand not an lvalue. |
| 70  | `040-cc-prep.fth:320`, `090-cc-emit.fth:1010`, `100-cc-expr.fth:828` | Preprocessor `#include` open failed, or codegen output capacity exceeded, or sizeof path miss. |
| 71  | `040-cc-prep.fth:304`, `090-cc-emit.fth:1032`, `100-cc-expr.fth:833` | Preprocessor read failed, or codegen literal pool full, or sizeof on unknown type. |
| 72  | `040-cc-prep.fth:73`, `100-cc-expr.fth:837`  | Preprocessor close failed, or sizeof argument malformed. |
| 73  | `100-cc-expr.fth:743,772,776` | `sizeof IDENT`: identifier not found / wrong kind. |
| 74  | `100-cc-expr.fth:733` | `sizeof` argument couldn't be sized. |
| 75–79 | `100-cc-expr.fth`   | `sizeof(type)` parse: missing `(`, missing `)`, unknown tag, wrong tag kind. |
| 80  | `100-cc-expr.fth:254`, `110-cc-decl.fth:1309` | Assignment LHS isn't an assignable kind. |
| 82  | `100-cc-expr.fth:304,590`, `110-cc-decl.fth:1263` | Missing `]` after array-index assignment, or postfix `[`/`.` shape. |
| 90  | `100-cc-expr.fth:608` | `.` / `->` used without a known struct descriptor. |
| 91  | `100-cc-expr.fth:625` | `.` / `->` expected an identifier (field name). |
| 92  | `100-cc-expr.fth:213`, `110-cc-decl.fth` | Field name not found in the struct descriptor. |
| 93–99 | `110-cc-decl.fth`   | Struct definition: too many fields, malformed field, missing `}` or `;`. |
| 100–102 | `110-cc-decl.fth` | Function definition: bad return type, bad parameter list. |
| 110–116 | `110-cc-decl.fth` | Function call site: arity mismatch, malformed argument list. |
| 140 | `110-cc-decl.fth:371` | Function-pointer declarator: expected name. |
| 141 | `110-cc-decl.fth:395` | Function-pointer declarator: expected `;`. |
| 160 | `110-cc-decl.fth:2419` | Top-level declaration: expected type identifier. |
| 161 | `110-cc-decl.fth:2429` | Top-level declaration: expected variable name. |
| 162 | `110-cc-decl.fth:2443` | Top-level array decl: bracket without integer literal size. |
| 163 | `110-cc-decl.fth:2363,2368` | Global initialiser: expected integer literal (optionally signed). |
| 164 | `110-cc-decl.fth:2463` | Top-level declaration: trailing form not recognised. |

When you add a new error site, pick the next free code at the
end of the file's existing range; assignments are file-local, not
project-global, and the ranges in the first table are the
convention.

## Why no diagnostic text?

The seed has no `printf`.  Adding a string-emitting `die` would
mean shipping a per-call message constant, which the 2,040-byte
budget cannot afford and which the literate-program rule (every
byte argued for) would force into the book.  The trade is honest:
a debugged build loses two minutes to grepping the source, but the
seed stays small enough to read.

For richer diagnostics, the canonical workflow is:

```sh
echo $?                              # see the exit status
grep -nB3 "\[lit\] <code> die" *.fth  # find the call site
```

The few lines of context above the `die` show which token the
parser expected.  In nearly every case the answer is "the lexer
saw something other than `T`, `;`, `}`, an identifier, or an
integer literal."
