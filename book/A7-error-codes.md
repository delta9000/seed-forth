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

The original compiler assigned ranges by file. The native extension
reuses some equivalent diagnostics and adds its own sites below, so
a code can identify more than one source location:

| File | Range | What breaks there |
|---|---|---|
| `000-seed.hex0`     | 2       | The seed rejects a token while loading the Forth (below). |
| `020-cc-arena.fth`  | 10–19   | Arena allocator out of memory. |
| `030-cc-io.fth`     | 20–29   | Input, output buffer, output file. |
| `040-cc-prep.fth`   | 30–49   | Preprocessor: includes, macros and macro calls, conditionals, preprocessed size. |
| `050-cc-lex.fth`    | —       | Lexer (no failures; its old range, 40–49, went to the preprocessor). |
| `060-cc-types.fth`  | 50–59   | Struct descriptors. |
| `070-cc-sym.fth`    | 60–69   | Symbol table and scope stack. |
| `080-cc-elf.fth`    | 70–79   | ELF header (no failures yet). |
| `090-cc-emit.fth`   | 80–89   | Codegen capacity. |
| `100-cc-expr.fth`   | 90–139  | Expression parser. |
| `110-cc-decl.fth`   | 140–169 | Declarations and the frame's slot limit. |
| `112-cc-stmt.fth`   | 170–179 | Statements: `case`, labels, `goto`. |
| `114-cc-func.fth`   | 180–189 | Parameters and function definitions. |
| `116-cc-prog.fth`   | 190–219 | Enums, typedefs, prototypes, globals, and the whole-program check. |
| `115-cc-native.fth`, `117-cc-native-program.fth` | shared codes, 210–214 | Native declarations, layout, and function definitions. |
| `100-cc-expr.fth`, `118-cc-native-init.fth` | 219–227 | Native constant-category checks and bounded initializers. |
| `120-cc-main.fth`   | — | Default driver (no failures). |
| `130-asm.fth`       | 230–249 | The M1 assembler, a separate program. |
| tests               | 255     | A `test-*.fth` file's final `0= die`: some check failed. |

Some older error numbers have several equivalent failure sites. The
file-and-line column, kept current by `tools/check-numbers.py`, is the
precise lookup; use it together with the selected compiler profile.
Codes no longer used by the legacy parser are not a promise that a
new native form is accepted. The native table below includes reused
numbers and all new native-only diagnostics.

## Codes in detail

Every die site in `020-cc-arena.fth` through `120-cc-main.fth`, traced
to its call site.

| Code | File:line(s) | Triggered by |
|---:|---|---|
| 10  | `020-cc-arena.fth:87,106` | Arena allocation past its configured cap (32 KiB by default), or failure to map the opt-in larger workspace. |
| 20  | `030-cc-io.fth:72` | `cc-load-stdin`: the source fills the 1 MiB input buffer. |
| 21  | `030-cc-io.fth:110` | `cc-emit-byte`: the output fills the 1 MiB output buffer. |
| 22  | `030-cc-io.fth:170` | `cc-write-output`: `open(2)` on the output path returned an error. |
| 30  | `040-cc-prep.fth:584` | Include not found: the legacy direct/`tests/cc/` search or the native source-relative/configured-directory search. |
| 31  | `040-cc-prep.fth:572` | Include depth exceeds its profile limit: four legacy slots or thirty-two direct levels. |
| 32  | `040-cc-prep.fth:590,594` | Included file fills its legacy 256 KiB slot or direct input fills the shared 1 MiB pool. |
| 33  | `040-cc-prep.fth:449,490,500` | `#include` path (with the `tests/cc/` prefix) longer than the 1,024-byte path buffer. |
| 34  | `040-cc-prep.fth:185` | Macro count exceeds 1,024 in legacy mode (11 built in) or 4,096 in direct mode. |
| 35  | `040-cc-prep.fth:161` | Macro pool (64 KiB legacy, 256 KiB direct) full: `cc-pp-to-pool` makes it the sink with this code, and `cc-prep-emit-byte` dies when a macro name or body would overflow it. |
| 36  | `040-cc-prep.fth:1244` | `cc-prep-emit-byte`: preprocessed source fills the 2 MiB source buffer (the sink `cc-preprocess` sets up with this code). |
| 37  | `040-cc-prep.fth:119` | A temporary buffer fills: a macro argument, or a replacement with its arguments put in, longer than 64 KiB (the sink `cc-pp-temp-begin` sets up with this code). |
| 38  | `040-cc-prep.fth:1198` | `cc-pp-cond-push`: `#if` / `#ifdef` / `#ifndef` nested more than 64 deep. |
| 39  | `040-cc-prep.fth:1573` | `cc-preprocess`: an `#if` still open at the end of the program. |
| 40  | `040-cc-prep.fth:1497` | `#error` in a group that is not dropped. |
| 41  | `040-cc-prep.fth:1213` | `cc-pp-need-group`: `#elif`, `#else` or `#endif` with no `#if` open. |
| 42  | `040-cc-prep.fth:399` | `cc-pp-need-name`: `#ifdef`, `#ifndef` or `defined` with no name after it. |
| 43  | `040-cc-prep.fth:113` | `cc-pp-scratch-alloc`: the 2 MiB macro scratch area is used up (about 32 macro calls nested in each other's arguments). |
| 44  | `040-cc-prep.fth:691` | `cc-pp-collect-args`: a function-like macro call whose `)` never comes before the end of its region (the file, or the macro text it is in). |
| 45  | `040-cc-prep.fth:965` | `cc-pp-expand-call`: a function-like macro called with more arguments than it has parameters. |
| 46  | `040-cc-prep.fth:676` | `cc-pp-ca-record`: a macro call with more than 16 arguments. |
| 47  | `040-cc-prep.fth:406,1375` | `cc-pp-need-rparen`: no `)` to close `defined(NAME` or a `#define`'s parameter list (anything but names and commas in it). |
| 48  | `040-cc-prep.fth:1349` | `cc-pp-read-params`: a function-like `#define` with more than 16 parameters. |
| 50  | `060-cc-types.fth:192` | `cc-sd-field-rec`: a struct with more than 16 fields. |
| 60  | `070-cc-sym.fth:61` | `cc-sym-add`: more than 4,096 symbols. |
| 61  | `070-cc-sym.fth:129` | `cc-scope-push`: scopes nested more than 64 deep. |
| 62  | `070-cc-sym.fth:138` | `cc-scope-pop` with no push to match (a parser bug; no C program reaches it). |
| 80  | `090-cc-emit.fth:1148` | `cc-globals-alloc`: the data area of file-scope scalars (64 KiB) is full. |
| 81  | `090-cc-emit.fth:1177` | `cc-gfixup-add`: global-fixup table (16,384 entries) full. |
| 82  | `090-cc-emit.fth:1156` | `cc-bss-alloc`: global arrays need more than the 256 MiB bss. |
| 90  | `100-cc-expr.fth:263` | Field name not found in the struct descriptor. |
| 91  | `100-cc-expr.fth:302` | `name[`: array base isn't a local or a global. |
| 92  | `100-cc-expr.fth:352` | Subscript `name[i]`: missing `]`. |
| 93  | `100-cc-expr.fth:767` | Primary expression: identifier not in the symbol table. |
| 94  | `100-cc-expr.fth:784` | `name(...)` where `name` is neither a function nor a function-pointer local. |
| 95  | `100-cc-expr.fth:812` | Primary expression: identifier names something that isn't a variable, function or enum constant (a typedef name or struct tag used as a value). |
| 96  | `100-cc-expr.fth:821` | Parenthesised expression: missing `)`. |
| 97  | `100-cc-expr.fth:849` | Primary expression: token can't start one (not a literal, identifier or `(`). |
| 98  | `100-cc-expr.fth:905` | Postfix `++`/`--`: operand isn't an lvalue. |
| 99  | `100-cc-expr.fth:940,962` | Postfix `[` on any expression: missing `]`. |
| 100 | `100-cc-expr.fth:976` | `.` / `->` on an expression with no known struct descriptor. |
| 101 | `100-cc-expr.fth:988` | `.` / `->` not followed by an identifier (field name). |
| 102 | `100-cc-expr.fth:1140` | `sizeof`: missing `(`. |
| 103 | `100-cc-expr.fth:1148` | `sizeof(struct`: tag isn't an identifier. |
| 104 | `100-cc-expr.fth:1152` | `sizeof(struct TAG`: tag not found. |
| 105 | `100-cc-expr.fth:1155` | `sizeof(struct TAG`: name isn't a struct tag. |
| 106 | `100-cc-expr.fth:1169` | `sizeof(`: keyword other than `struct`, `int`, `char` or `void`. |
| 107 | `100-cc-expr.fth:1179` | `sizeof(`: identifier not found. |
| 108 | `100-cc-expr.fth:1208` | `sizeof(`: identifier found but neither a typedef nor a local. |
| 109 | `100-cc-expr.fth:1212` | `sizeof(`: token is neither a keyword nor an identifier. |
| 110 | `100-cc-expr.fth:1116,1124,1217` | `sizeof(...`: missing `)`. |
| 113 | `100-cc-expr.fth:865,1268` | Prefix `++`/`--`: operand isn't an lvalue. |
| 114 | `100-cc-expr.fth:1306` | Unary `&`: operand isn't an identifier. |
| 115 | `100-cc-expr.fth:1311` | Unary `&`: identifier not found. |
| 116 | `100-cc-expr.fth:1298,1315` | Unary `&`: identifier isn't a local. |
| 117 | `100-cc-expr.fth:1930` | Ternary `?`: missing `:`. |
| 118 | `100-cc-expr.fth:1987` | Compound-assignment dispatcher saw an operator it doesn't know (internal; not reachable from valid tokens). |
| 120 | `100-cc-expr.fth:2005,2016,2134` | Assignment: left-hand side isn't an lvalue. |
| 121 | `100-cc-expr.fth:451,522` | Call: argument list not closed by `)`. |
| 122 | `100-cc-expr.fth:530` | Call: more than six arguments (the register-only calling convention). |
| 123 | `100-cc-expr.fth:570` | Call target is neither a function nor a function-pointer local (internal: `cc-parse-primary` already checks, with 94). |
| 124 | `100-cc-expr.fth:1397` | `cc-divisor`: a constant expression divides by zero (`/` or `%`). |
| 125 | `100-cc-expr.fth:2190` | Constant expression: a name that isn't an enum constant (a variable, say, in an array size). |
| 126 | `100-cc-expr.fth:2199` | Constant expression: a token that can't start an operand. |
| 127 | `100-cc-expr.fth:2196` | Constant expression: `(` not closed by `)`. |
| 128 | `100-cc-expr.fth:2271` | Constant expression: `?` without its `:`. |
| 129 | `100-cc-expr.fth:2296` | `cc-pp-eval-text`: an `#if` or `#elif` expression followed by more text. |
| 140 | `110-cc-decl.fth:61` | `cc-expect-kw-id`: next token wasn't a keyword. |
| 141 | `110-cc-decl.fth:64` | `cc-expect-kw-id`: keyword id mismatch. |
| 142 | `110-cc-decl.fth:72` | `cc-expect-punct-c`: next token wasn't punctuation. |
| 143 | `110-cc-decl.fth:75` | `cc-expect-punct-c`: punctuation char mismatch. |
| 144 | `110-cc-decl.fth:82` | `cc-expect-ident`: next token wasn't an identifier. |
| 145 | `110-cc-decl.fth:206` | `struct` (in a local, parameter, typedef, field or global) not followed by a tag identifier (`cc-lookup-struct-tag`). |
| 146 | `110-cc-decl.fth:211` | `struct TAG`: tag not found (strict lookup: locals, parameters, typedefs). |
| 147 | `110-cc-decl.fth:215` | `struct TAG`: name isn't a struct tag (strict lookup). |
| 148 | `110-cc-decl.fth:226` | `struct` (in a local, parameter, typedef, field or global) not followed by a tag identifier (`cc-lookup-struct-tag-soft`). |
| 149 | `110-cc-decl.fth:243` | `struct` definition: tag isn't an identifier. |
| 150 | `110-cc-decl.fth:297` | Struct definition: field type is a keyword other than `int`, `char`, `void` or `struct`. |
| 151 | `110-cc-decl.fth:303` | Struct definition: field type is neither a keyword nor an identifier. |
| 152 | `110-cc-decl.fth:315` | Struct definition: field name missing. |
| 153 | `110-cc-decl.fth:392` | Function-pointer declarator: expected name. |
| 154 | `110-cc-decl.fth:416` | Function-pointer declarator: expected `=` or `;`. |
| 156 | `110-cc-decl.fth:443` | Local array declaration: size is zero or negative. |
| 157 | `110-cc-decl.fth:445` | Local array declaration: missing `]`. |
| 159 | `110-cc-decl.fth:500` | Local declaration: a declarator followed by neither `,` nor `;`. |
| 160 | `110-cc-decl.fth:653` | Struct local declaration: variable name missing. |
| 161 | `110-cc-decl.fth:688` | Struct-pointer local not followed by `=` or `;`. |
| 162 | `110-cc-decl.fth:39` | `cc-fn-add-slots`: a function's parameters and locals need more than the 32 slots of its 256-byte frame. |
| 170 | `112-cc-stmt.fth:506,789,794` | `case` label not followed by `:`. |
| 171 | `112-cc-stmt.fth:617` | `cc-label-create`: more than 64 labels in one function. |
| 172 | `112-cc-stmt.fth:647` | Label defined twice in one function. |
| 173 | `112-cc-stmt.fth:692` | `goto` not followed by an identifier. |
| 180 | `114-cc-func.fth:78` | Parameter type is an identifier that isn't in the symbol table. |
| 181 | `114-cc-func.fth:81` | Parameter type is an identifier that isn't a typedef. |
| 182 | `114-cc-func.fth:87` | Parameter type is neither a keyword nor an identifier. |
| 183 | `114-cc-func.fth:98` | Parameter name missing. |
| 184 | `114-cc-func.fth:118` | Parameter list not closed by `)`. |
| 185 | `114-cc-func.fth:188` | Function return type: `struct` not followed by a tag identifier. |
| 186 | `114-cc-func.fth:195` | Function return type: neither a keyword nor an identifier. |
| 187 | `114-cc-func.fth:225` | Function definition: name after the return type isn't an identifier. |
| 190 | `116-cc-prog.fth:54` | `enum`: enumerator isn't an identifier. |
| 192 | `116-cc-prog.fth:92` | `enum`: enumerator followed by neither `,` nor `}`. |
| 193 | `116-cc-prog.fth:127` | `typedef`: base keyword other than `int`, `char`, `void` or `struct`. |
| 194 | `116-cc-prog.fth:133` | `typedef`: base identifier not found. |
| 195 | `116-cc-prog.fth:136` | `typedef`: base identifier isn't itself a typedef. |
| 196 | `116-cc-prog.fth:140` | `typedef`: base is neither a keyword nor an identifier. |
| 197 | `116-cc-prog.fth:164` | Function-pointer `typedef T (*NAME)(...)`: name missing. |
| 198 | `116-cc-prog.fth:188` | `typedef`: new name isn't an identifier. |
| 199 | `116-cc-prog.fth:308` | Prototype: name after the return type isn't an identifier. |
| 202 | `116-cc-prog.fth:464` | Top-level declaration: base type is neither a keyword nor an identifier. |
| 203 | `116-cc-prog.fth:401` | Top-level declaration: expected variable name. |
| 205 | `116-cc-prog.fth:474` | Top-level declaration: a declarator followed by neither `,` nor `;`. |
| 206 | `116-cc-prog.fth:864` | `cc-check-fns-defined`: at the end of the program, a function that was called or used as a value was never defined (its call or address fixups are still pending).  `memset` is declared but has no body, so a program that uses it lands here. |
| 207 | `116-cc-prog.fth:869` | `cc-check-fns-defined`: at the end of the program, there is no `main`. |

Every buffer and table the compiler fills is bounds-checked with
`cc-check-cap` (or `cc-read-all` for input), and
`tests/cc/run-gates.sh` has a die gate (`tests/cc/die-NN-*`) that
overflows each one and checks the code and the line; so do the
whole-program checks, 162 (a function that needs more than its
frame's 32 slots, Ch 31), 206 and 207, and every preprocessor and
constant-expression code.  The gates cannot reach 22 (the output
file won't open) or 62 (a parser bug).  Codes 35, 36 and 37 are
given to a sink (Ch 22 §1) rather than to `cc-die`, so their line is
where the sink is set up; the check itself is in
`cc-prep-emit-byte`.

When you add an error site, update the relevant table and its rejection
test; preserve existing diagnostics unless the accepted profile changes.

### Native-profile diagnostics

These sites apply to the opt-in native profile (Ch 34). Common expression,
preprocessor, symbol, and undefined-function diagnostics above still
apply. A shared code describes the same kind of syntax failure in the
native parser; the file distinguishes its implementation.

| Code | File:line(s) | Triggered by |
|---|---|---|
| 58 | `115-cc-native.fth:252` | Aggregate field declaration missing its semicolon. |
| 174 | `112-cc-stmt.fth:679` | Native function ends with a `goto` target still undefined. |
| 184 | `110-cc-decl.fth:366`, `117-cc-native-program.fth:27` | Parameter list reaches EOF or native parameter list is not closed by `)`. |
| 190 | `115-cc-native.fth:89` | Native enumerator is not an identifier. |
| 192 | `115-cc-native.fth:97` | Native enumerator followed by neither `,` nor `}`. |
| 194 | `115-cc-native.fth:114` | Native type identifier not found. |
| 195 | `115-cc-native.fth:115` | Native type identifier is not a typedef. |
| 203 | `115-cc-native.fth:373` | Native declarator is missing its name. |
| 205 | `115-cc-native.fth:387` | Native declaration missing its final semicolon. |
| 210 | `115-cc-native.fth:42` | Aggregate object size requested without a descriptor. |
| 211 | `117-cc-native-program.fth:46` | Function already has a definition. |
| 212 | `100-cc-expr.fth:446`, `117-cc-native-program.fth:20,33` | Native aggregate-by-value argument, parameter, or return, outside the private call ABI. |
| 213 | `115-cc-native.fth:191` | Nested array field, outside the native field profile. |
| 214 | `110-cc-decl.fth:368`, `115-cc-native.fth:136` | Floating type used in normal native mode; only the explicit bootstrap bit-transport profile accepts these type spellings. |
| 219 | `100-cc-expr.fth:54`, `118-cc-native-init.fth:147` | Static initializer needs an evaluated nonconstant operation or a static aggregate copy. |
| 220 | `118-cc-native-init.fth:76,77,88,96` | Invalid or empty inferred array initializer. |
| 221 | `118-cc-native-init.fth:93,100,119` | Malformed or unterminated inferred initializer. |
| 222 | `118-cc-native-init.fth:105,110` | Inferred array's nested aggregate/row lacks required braces. |
| 223 | `118-cc-native-init.fth:85,139,214` | Character initializer too large or invalid braced-string close. |
| 224 | `118-cc-native-init.fth:153` | Aggregate copy has a mismatched type/descriptor. |
| 225 | `118-cc-native-init.fth:196,219,231` | Required initializer brace is missing. |
| 226 | `118-cc-native-init.fth:201` | Initializer has excess elements or lacks its closing brace. |
| 227 | `118-cc-native-init.fth:244` | Braced scalar initializer not closed by `}`. |

The restricted bootstrap runtime has a separate **execution** failure:
`localtime`, `ldexp`, and `longjmp` print
`seed-forth bootstrap: unsupported NAME` and exit 125. This is not the
compiler's constant-expression error 125. Without the bootstrap flag,
those names remain undefined and ordinary references produce error 206;
the usual floating declaration of `ldexp` is rejected first with 214.

### The assembler's codes

`130-asm.fth`, the M1 assembler, is a separate program: it loads
none of the compiler's files, so it has its own `asm-check-cap`
(the same test as `cc-check-cap`, dying with a bare `die`) and prints
no line number.  A sigil token naming an undefined label goes
through `asm-tok-err`, which writes the offending token to stderr
before exiting; `asm-process-token` hands each sigil's code to
`asm-do-ref`.  So do the checks copied from mescc-tools: a value that
does not fit its field (`asm-fit`, with `hex2`'s bounds for a label
and `M1`'s for a number) and a bare token that is not an even run of
hex digits.  `tests/asm/die-gates.sh` overflows each buffer and
table, feeds each sigil an undefined label, and has one input for
each of 244–247.  Ch 33 walks every site below (§13 groups them).

| Code | File:line(s) | Triggered by |
|---:|---|---|
| 230 | `130-asm.fth:145` | `asm-write-output`: `open(2)` on `/tmp/asm-out` returned an error. |
| 231 | `130-asm.fth:593` | `&label` (4-byte absolute) undefined. |
| 232 | `130-asm.fth:535` | `%target>base`: base label undefined. |
| 233 | `130-asm.fth:529` | `%target>base`: target label undefined. |
| 234 | `130-asm.fth:541` | `%label` (4-byte relative) undefined. |
| 235 | `130-asm.fth:588` | `!label` (1-byte relative) undefined. |
| 236 | `130-asm.fth:589` | `@label` (2-byte relative) undefined. |
| 237 | `130-asm.fth:590` | `~label` (3-byte relative) undefined. |
| 238 | `130-asm.fth:592` | `$label` (2-byte absolute) undefined. |
| 239 | `130-asm.fth:95` | `asm-load-stdin`: the M1 source fills the 4 MiB source buffer. |
| 240 | `130-asm.fth:117` | `asm-exp-emit-byte`: macro expansion fills the 4 MiB expansion buffer. |
| 241 | `130-asm.fth:132` | `asm-emit-byte`: the output fills the 1 MiB output buffer. |
| 242 | `130-asm.fth:181` | `asm-store-label`: more than 8,192 labels. |
| 243 | `130-asm.fth:631` | `asm-def-store`: more than 4,096 `DEFINE`s. |
| 244 | `130-asm.fth:513` | `asm-do-ref`: a label's value does not fit its field by `hex2`'s rule (`!` −128..127, `@` −32,768..32,767, `~` −8,388,608..8,388,607, `$` 0..65,535; `%` and `&` unchecked). |
| 245 | `130-asm.fth:504` | `asm-do-ref`: a number does not fit its field by `M1`'s rule (`!` −129..256, `@` −32,769..32,768, `~` −8,388,609..8,388,608, `$` −32,769..65,536; `%` and `&` unchecked). |
| 246 | `130-asm.fth:553` | `asm-check-hex`: a bare token is not hex digits, typically a misspelled or undefined macro name (`M1`'s "invalid other"). |
| 247 | `130-asm.fth:558` | `asm-check-hex`: a hex token has an odd number of digits. |

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
