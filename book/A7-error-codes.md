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
| 20  | `030-cc-io.fth:84` | `cc-load-stdin`: the source fills the selected input buffer (default 1 MiB, direct GCC 3 MiB), or its workspace mapping fails. |
| 21  | `030-cc-io.fth:128` | `cc-emit-byte`: the output fills its selected buffer (default 1 MiB, direct GCC 4 MiB). |
| 22  | `030-cc-io.fth:188` | `cc-write-output`: `open(2)` on the output path returned an error. |
| 30  | `040-cc-prep.fth:867,1786,1791,1796,1843` | Include not found: the legacy direct/`tests/cc/` search or the native source-relative/configured-directory search. |
| 31  | `040-cc-prep.fth:855` | Include depth exceeds its profile limit: four legacy slots or thirty-two direct levels. |
| 32  | `040-cc-prep.fth:873,877` | Included file fills its legacy 256 KiB slot, or the live include stack fills the selected direct pool (default 1 MiB; the direct-GCC workspace maps 7 MiB, the same bound as its expanded source). The raw reader keeps one byte free, so the largest live stack is the capacity minus one. A failed mapping of the direct pool uses this code too. |
| 33  | `040-cc-prep.fth:683,773,783` | `#include` path (with the `tests/cc/` prefix) longer than the 1,024-byte path buffer. |
| 34  | `040-cc-prep.fth:271` | Macro count exceeds 1,024 in legacy mode (11 built in) or 4,096 in native/direct mode with default storage; the direct-GCC workspace permits 4,608. Mapping failure uses this code too. |
| 35  | `040-cc-prep.fth:271` | Macro pool (64 KiB legacy, 256 KiB direct) full: `cc-pp-to-pool` makes it the sink with this code, and `cc-prep-emit-byte` dies when a macro name or body would overflow it. |
| 36  | `040-cc-prep.fth:2145` | `cc-prep-emit-byte`: preprocessed source fills the selected source buffer (default 2 MiB, direct GCC 7 MiB) (the sink `cc-preprocess` sets up with this code). |
| 37  | `040-cc-prep.fth:179` | A temporary buffer fills: a macro argument, or a replacement with its arguments put in, longer than 64 KiB (the sink `cc-pp-temp-begin` sets up with this code). |
| 38  | `040-cc-prep.fth:1665` | `cc-pp-cond-push`: `#if` / `#ifdef` / `#ifndef` nested more than 64 deep. |
| 39  | `040-cc-prep.fth:2297` | `cc-preprocess`: an `#if` still open at the end of the program. |
| 40  | `040-cc-prep.fth:2199` | `#error` in a group that is not dropped. |
| 41  | `040-cc-prep.fth:1680` | `cc-pp-need-group`: `#elif`, `#else` or `#endif` with no `#if` open. |
| 42  | `040-cc-prep.fth:586` | `cc-pp-need-name`: `#ifdef`, `#ifndef` or `defined` with no name after it. |
| 43  | `040-cc-prep.fth:153,173` | `cc-pp-scratch-alloc`: the 2 MiB macro scratch area is used up (about 32 macro calls nested in each other's arguments), the direct suppression-shadow mapping fails, or the selected source capacity exceeds its fixed shadow. |
| 44  | `040-cc-prep.fth:978` | `cc-pp-collect-args`: a function-like macro call whose `)` never comes before the end of its region (the file, or the macro text it is in). |
| 45  | `040-cc-prep.fth:1334` | `cc-pp-expand-call`: a function-like macro called with more arguments than it has parameters. |
| 46  | `040-cc-prep.fth:963` | `cc-pp-ca-record`: a macro call with more than 16 arguments. |
| 47  | `040-cc-prep.fth:165,593,2028,2031,2039,2051,2122` | `cc-pp-need-rparen`: no `)` to close `defined(NAME` or a malformed `#define` parameter list; direct token pasting also rejects any unavailable byte in either raw operand. |
| 48  | `040-cc-prep.fth:1973,2029` | `cc-pp-read-params`: a function-like `#define` with more than 16 parameters. |
| 49  | `040-cc-prep.fth` | Invalid or unsupported direct-profile directive syntax, including malformed `#line`, GNU numeric markers, unterminated comments in directives, splices splitting a directive name, and source-text continuations that would join two tokens (continuations inside or splitting comments follow phase two). See [C line control](22-the-preprocessor.md#c-line-control-for-generated-parser-sources). |
| 50  | `060-cc-types.fth:313` | `cc-sd-field-rec`: a struct or union with more members than the target allows: 1023 in LP64 modes (C99 §5.2.4.1; anonymous members counted once flattened), 16 in the legacy subset. |
| 60  | `070-cc-sym.fth:75` | `cc-sym-add`: more than 8,192 live symbols. |
| 61  | `070-cc-sym.fth:155` | `cc-scope-push`: scopes nested more than 64 deep. |
| 62  | `070-cc-sym.fth:164` | `cc-scope-pop` with no push to match (a parser bug; no C program reaches it). |
| 80  | `090-cc-emit.fth:1186` | `cc-globals-alloc`: the data area of file-scope scalars (64 KiB) is full. |
| 81  | `090-cc-emit.fth:1215` | `cc-gfixup-add`: selected global-fixup table full (default 16,384, direct GCC 17,920), or its mapping fails. |
| 82  | `090-cc-emit.fth:1194` | `cc-bss-alloc`: global arrays need more than the 256 MiB bss. |
| 90  | `100-cc-expr.fth:345` | Field name not found in the struct descriptor. |
| 91  | `100-cc-expr.fth:384` | `name[`: array base isn't a local or a global. |
| 92  | `100-cc-expr.fth:434` | Subscript `name[i]`: missing `]`. |
| 93  | `100-cc-expr.fth:892` | Primary expression: identifier not in the symbol table. |
| 94  | `100-cc-expr.fth:909` | `name(...)` where `name` is neither a function nor a function-pointer local. |
| 95  | `100-cc-expr.fth:935` | Primary expression: identifier names something that isn't a variable, function or enum constant (a typedef name or struct tag used as a value). |
| 96  | `100-cc-expr.fth:944` | Parenthesised expression: missing `)`. |
| 97  | `100-cc-expr.fth:975` | Primary expression: token can't start one (not a literal, identifier or `(`). |
| 98  | `100-cc-expr.fth:1050` | Postfix `++`/`--`: operand isn't an lvalue. |
| 99  | `100-cc-expr.fth:1095,1118` | Postfix `[` on any expression: missing `]`. |
| 100 | `100-cc-expr.fth:1136` | `.` / `->` on an expression with no known struct descriptor. |
| 101 | `100-cc-expr.fth:1148` | `.` / `->` not followed by an identifier (field name). |
| 102 | `100-cc-expr.fth:1320` | `sizeof`: missing `(`. |
| 103 | `100-cc-expr.fth:1328` | `sizeof(struct`: tag isn't an identifier. |
| 104 | `100-cc-expr.fth:1332` | `sizeof(struct TAG`: tag not found. |
| 105 | `100-cc-expr.fth:1335` | `sizeof(struct TAG`: name isn't a struct tag. |
| 106 | `100-cc-expr.fth:1349` | `sizeof(`: keyword other than `struct`, `int`, `char` or `void`. |
| 107 | `100-cc-expr.fth:1359` | `sizeof(`: identifier not found. |
| 108 | `100-cc-expr.fth:1388` | `sizeof(`: identifier found but neither a typedef nor a local. |
| 109 | `100-cc-expr.fth:1392` | `sizeof(`: token is neither a keyword nor an identifier. |
| 110 | `100-cc-expr.fth:1294,1297,1397` | `sizeof(...`: missing `)`. |
| 113 | `100-cc-expr.fth:1012,1448` | Prefix `++`/`--`: operand isn't an lvalue. |
| 114 | `100-cc-expr.fth:1501` | Unary `&`: operand isn't an identifier. |
| 115 | `100-cc-expr.fth:1506` | Unary `&`: identifier not found. |
| 116 | `100-cc-expr.fth:1477,1485,1510` | Unary `&`: identifier isn't a local. |
| 117 | `100-cc-expr.fth:2163` | Ternary `?`: missing `:`. |
| 118 | `100-cc-expr.fth:2236` | Compound-assignment dispatcher saw an operator it doesn't know (internal; not reachable from valid tokens). |
| 120 | `100-cc-expr.fth:2257,2265,2286,2411` | Assignment: left-hand side isn't an lvalue. |
| 121 | `100-cc-expr.fth:533,619` | Call: argument list not closed by `)`. |
| 122 | `100-cc-expr.fth:627` | Call: more than six arguments (the register-only calling convention). |
| 123 | `100-cc-expr.fth:667` | Call target is neither a function nor a function-pointer local (internal: `cc-parse-primary` already checks, with 94). |
| 124 | `100-cc-expr.fth:1595` | `cc-divisor`: a constant expression divides by zero (`/` or `%`). |
| 125 | `100-cc-expr.fth:2530` | Constant expression: a name that isn't an enum constant (a variable, say, in an array size). |
| 126 | `100-cc-expr.fth:2539` | Constant expression: a token that can't start an operand. |
| 127 | `100-cc-expr.fth:2536` | Constant expression: `(` not closed by `)`. |
| 128 | `100-cc-expr.fth:2615` | Constant expression: `?` without its `:`. |
| 129 | `100-cc-expr.fth:2646` | `cc-pp-eval-text`: an `#if` or `#elif` expression followed by more text. |
| 140 | `110-cc-decl.fth:67` | `cc-expect-kw-id`: next token wasn't a keyword. |
| 141 | `110-cc-decl.fth:70` | `cc-expect-kw-id`: keyword id mismatch. |
| 142 | `110-cc-decl.fth:78` | `cc-expect-punct-c`: next token wasn't punctuation. |
| 143 | `110-cc-decl.fth:81` | `cc-expect-punct-c`: punctuation char mismatch. |
| 144 | `110-cc-decl.fth:88` | `cc-expect-ident`: next token wasn't an identifier. |
| 145 | `110-cc-decl.fth:238` | `struct` (in a local, parameter, typedef, field or global) not followed by a tag identifier (`cc-lookup-struct-tag`). |
| 146 | `110-cc-decl.fth:243` | `struct TAG`: tag not found (strict lookup: locals, parameters, typedefs). |
| 147 | `110-cc-decl.fth:247` | `struct TAG`: name isn't a struct tag (strict lookup). |
| 148 | `110-cc-decl.fth:258` | `struct` (in a local, parameter, typedef, field or global) not followed by a tag identifier (`cc-lookup-struct-tag-soft`). |
| 149 | `110-cc-decl.fth:275` | `struct` definition: tag isn't an identifier. |
| 150 | `110-cc-decl.fth:325` | Struct definition: field type is a keyword other than `int`, `char`, `void` or `struct`. |
| 151 | `110-cc-decl.fth:331` | Struct definition: field type is neither a keyword nor an identifier. |
| 152 | `110-cc-decl.fth:343` | Struct definition: field name missing. |
| 153 | `110-cc-decl.fth:420` | Function-pointer declarator: expected name. |
| 154 | `110-cc-decl.fth:444` | Function-pointer declarator: expected `=` or `;`. |
| 156 | `110-cc-decl.fth:471` | Local array declaration: size is zero or negative. |
| 157 | `110-cc-decl.fth:473` | Local array declaration: missing `]`. |
| 159 | `110-cc-decl.fth:528` | Local declaration: a declarator followed by neither `,` nor `;`. |
| 160 | `110-cc-decl.fth:700` | Struct local declaration: variable name missing. |
| 161 | `110-cc-decl.fth:735` | Struct-pointer local not followed by `=` or `;`. |
| 162 | `110-cc-decl.fth:45` | `cc-fn-add-slots`: a function's parameters and locals need more than the 32 slots of its 256-byte frame. |
| 170 | `112-cc-stmt.fth:466,870,874` | `case` label not followed by `:` (`cc-switch-case`, every nesting depth), or under LP64 a `case` or `default` outside any switch. |
| 171 | `112-cc-stmt.fth:698` | `cc-label-create`: selected per-function label table full (default 64, direct GCC 1,024), or its mapping fails. |
| 172 | `112-cc-stmt.fth:728` | Label defined twice in one function. |
| 173 | `112-cc-stmt.fth:773` | `goto` not followed by an identifier. |
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
| 58 | `115-cc-native.fth:474` | Aggregate field declaration missing its semicolon. |
| 174 | `112-cc-stmt.fth:760` | Native function ends with a `goto` target still undefined. |
| 184 | `110-cc-decl.fth:394`, `117-cc-native-program.fth:27` | Parameter list reaches EOF or native parameter list is not closed by `)`. |
| 190 | `115-cc-native.fth:120` | Native enumerator is not an identifier. |
| 192 | `115-cc-native.fth:128` | Native enumerator followed by neither `,` nor `}`. |
| 194 | `115-cc-native.fth:214` | Native type identifier not found. |
| 195 | `115-cc-native.fth:215` | Native type identifier is not a typedef. |
| 203 | `115-cc-native.fth:314,317,331,624` | Native declarator is missing its name, or a parenthesized inner name is not an identifier or names a typedef. |
| 205 | `115-cc-native.fth:639` | Native declaration missing its final semicolon. |
| 210 | `115-cc-native.fth:56` | Aggregate object size requested without a descriptor. |
| 211 | `117-cc-native-program.fth:46` | Function already has a definition. |
| 212 | `100-cc-expr.fth:528`, `117-cc-native-program.fth:20,33` | Native aggregate-by-value argument, parameter, or return, outside the private call ABI. |
| 213 | `060-cc-types.fth:336` | Nested array field, outside the legacy/native field profile; the explicit SysV target retains checked ranked dimensions. |
| 214 | `110-cc-decl.fth:396`, `115-cc-native.fth:230` | Floating type used in normal native mode; only the explicit bootstrap bit-transport profile accepts these type spellings. |
| 219 | `100-cc-expr.fth:54`, `118-cc-native-init.fth:155` | Static initializer needs an evaluated nonconstant operation or a static aggregate copy. |
| 220 | `118-cc-native-init.fth:79,80,91,99` | Invalid or empty inferred array initializer. |
| 221 | `118-cc-native-init.fth:96,103,123` | Malformed or unterminated inferred initializer. |
| 222 | `118-cc-native-init.fth:109,114` | Inferred array's nested aggregate/row lacks required braces. |
| 223 | `118-cc-native-init.fth:88,143,236` | Character initializer too large or invalid braced-string close. |
| 224 | `118-cc-native-init.fth:162` | Aggregate copy has a mismatched type/descriptor. |
| 225 | `118-cc-native-init.fth:218,241,260` | Required initializer brace is missing. |
| 226 | `118-cc-native-init.fth:223` | Initializer has excess elements or lacks its closing brace. |
| 227 | `118-cc-native-init.fth:273` | Braced scalar initializer not closed by `}`. |

The restricted bootstrap runtime has a separate **execution** failure:
`localtime`, `ldexp`, and `longjmp` print
`seed-forth bootstrap: unsupported NAME` and exit 125. This is not the
compiler's constant-expression error 125. Without the bootstrap flag,
those names remain undefined and ordinary references produce error 206;
the usual floating declaration of `ldexp` is rejected first with 214.

### Optional direct-GCC components

These components have separate bounded interfaces, so their numeric ranges
overlap other programs. Read the phase and diagnostic prefix together with
the number. The object writer and standalone linker are described in
[chapter 35](35-direct-gcc-objects.md) and
[chapter 37](37-direct-gcc-linker.md); those chapters document their API
checks and output-publication failures.

In the direct-GCC target, preprocessor code 49 rejects a selected `#line`
directive or numeric line marker until logical source-location control is
implemented. It must not silently supply incorrect `__FILE__`/`__LINE__` values.

In the System V target, 233 rejects an invalid set of declaration
specifiers (`cc-sysv-spec-check` and its neighbours in `121-cc-sysv.fth`): a
type-keyword set C90 forbids, such as `long char` or a third `long`, or
`_Bool` with any other type keyword (`unsigned _Bool`); a second
storage class anywhere in one declaration, such as `static extern int x` or
`int static static x`; and a storage class in an aggregate member, a type name,
or a parameter other than its one `register`. A block-scope function
declaration admits only `extern` (`static int g();`, `auto` or `register`
inside a function body is 233), and its parameter list cannot be an
identifier list, nor can a function typedef's. Storage classes may otherwise
appear among the type specifiers in any order (`int static x`). See
[chapter 36](36-direct-gcc-calls.md).

In the System V target, 238 rejects an array shape the type system cannot
represent or that C forbids: a non-positive or excessive bound, a function
returning an array, and an implicit conversion that would discard a row's
qualifier, such as `long (*p)[3] = t` for a `const long t[2][3]` or
`volatile long (*p)[3] = t` for the same `t`
(`cc-sysv-row-qualifier-check` in `121-cc-sysv.fth`). Row qualifiers are
sets: a redeclaration or prototype whose row set differs, or a
pointer-to-pointer-to-row conversion that changes the set, is 237.
Grouped abstract object-pointer types such as `char *(*)` are representable
and must not report 238 merely because they have no array or function
suffix. Their total pointer depth is checked with 231. Qualified arrays
themselves decay normally; an explicit cast or a qualified destination
accepts the conversion. See [chapter 36](36-direct-gcc-calls.md).
Inside a grouped declarator, `cc-ngroup-name` (`115-cc-native.fth`) accepts
redundant parentheses around a name and its array suffixes but gives 238 for
a pointer group nested in a group, `int (*(*p))(void)`, and for array suffixes
split around the inner group, `int (*(s[2])[3])(void)`
([chapter 34](34-direct-tinycc.md)).
In the System V target, 238 also rejects a function definition nested inside
a block, which C does not have. A block-scope function declaration, such as
`extern char *getenv ();` in a function body, is accepted; one whose type
disagrees with another declaration of the same function is 237
([chapter 36](36-direct-gcc-calls.md)). A typedef of a function type, such
as `typedef int Function ();`, is accepted; 238 rejects an array or member
of that type, a function returning it, and a definition written through it,
`Function g { ... }`.

The compiler's typed constant evaluator reports 240 for an unsupported
constant form, 241 for an invalid shift count (negative, or at least the
left operand's promoted width), and 242 for signed arithmetic overflow; a
left shift by a valid count folds as two's complement, as GCC's does. 242 also rejects a floating constant whose truncated value does not
fit its integer destination, such as `int i = 1e10;` or `unsigned u = -1.0;`.
A floating operand of `%`, a shift or a bitwise operator is 240. Binary32 and
binary64 constant division by zero is 124; a result too large for either
format is 248 with the `cc-f64-literal: overflow` reason. Extended constants
instead produce infinity or a canonical quiet NaN
([chapter 41](41-direct-gcc-constants.md) §5). Under LP64, 240 also rejects a malformed integer suffix, such as
`1LLL`, `1lL`, `1LUL` or `1uu`, in every context: runtime expressions, constant
expressions and `#if` lines all read suffixes through `cc-integer-suffix` in
`060-cc-types.fth`. Integer division by zero retains 124. Constant evaluation never executes
generated target code; see [chapter 41](41-direct-gcc-constants.md).

The variadic parser prints a `varargs: ` prefix before the usual compiler
diagnostic. Code 246 means an invalid intrinsic invocation or a list whose
record layout does not match the public System V declaration. Code 247 means
an unsupported requested argument type. These are unrelated to the same
numbers in the object writer or assembler. [Chapter 42](42-direct-gcc-varargs.md)
states the supported argument classes and the public list representation.

In the System V target, 228 is a call to an undeclared function when the
driver was given `-Werror=implicit-function-declaration`; the diagnostic names
the function and its source file and line before the usual flattened line
([chapter 36](36-direct-gcc-calls.md)). Without that option such a call is
C90's implicit `extern int name ();`.

The System V target prints an `aggregate-abi: ` prefix before code 232 when
a record crosses a call, return or `va_arg` boundary with a class
[chapter 48](48-direct-gcc-aggregate-abi.md) does not implement, chiefly a
record with a `float` or `double` member, or when a record is used as a
scalar. Records with INTEGER, MEMORY or X87 classes cross prototyped,
unprototyped and variadic calls alike. An empty-parenthesis definition,
`long f() { ... }`, declares zero parameters, so a prior prototype with
parameters disagrees with it (237).

The System V target prints a `long-double: ` prefix before code 249 for
invalid integer-only uses of `long double`, including complement, array
subscripts and switch conditions, and for incompatible scalar conversions
such as a pointer or actual record. Arithmetic, comparisons, conditions,
compound assignments, updates, numeric conversions and exact static
initializers are supported;
[chapter 48](48-direct-gcc-aggregate-abi.md) §4 describes the x87 implementation.

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
