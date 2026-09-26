# Appendix F — The C subset

This appendix is the reference card for *what subset of C* the
compiler in `020-cc-arena.fth` through `120-cc-main.fth` actually
accepts.  The compiler is *not* an ANSI / ISO C compiler.  It is
"enough C to compile M2-Planet," which is a real but specific
corner of the language.  Use this appendix when you want to know
whether a construct will work without running it.

Sources of truth, in case this appendix drifts:

- Keyword set: `050-cc-lex.fth` lines 125–155 (`kw-*` constants).
- Expression grammar: `100-cc-expr.fth` lines 1–22 (header
  comment) and the `cc-parse-*` ladder.
- Type encoding: `060-cc-types.fth`.
- Statement forms: `110-cc-decl.fth` `cc-parse-stmt`
  (lines 1326–1393).

If you discover a construct the compiler accepts that isn't listed
below, or rejects one that is, this appendix is wrong and the
source wins.

## Types

The compiler models a single integer width (64 bits) plus pointers
and one byte-addressable case for `char`.  Every value is stored
in an 8-byte slot at runtime; the only place width matters is in
load / store instructions (qword vs byte) and in pointer
arithmetic stride.

| Type form | Accepted | Width / slot | Notes |
|---|---|---|---|
| `int`                  | yes | 8 bytes | The default integer.  Signed. |
| `char`                 | yes | 1 byte (load/store); 8-byte slot in locals | Signed for arithmetic via `<`. |
| `void`                 | yes (functions and pointers) | — | `void` as a function parameter list is treated as "no parameters." |
| `T*` (pointer)         | yes | 8 bytes | Any depth (`int**`, `char***`). |
| `struct T`             | yes (by-pointer only) | descriptor; values not passed | See §"Structs" below. |
| `enum T`               | yes | 8 bytes | Members are integer constants; the tag is accepted but discarded. |
| `typedef` names        | yes | resolves to the aliased type | Registered in the symbol table. |
| `T[N]` (array of T)    | yes (locals + globals) | `N * 8` (N slots, each 8 bytes) | Decays to `T*` in expressions. |
| `T (*fp)(args)` (function pointer) | yes (in `cc_globals.c` and friends) | 8 bytes | Only the forms M2-Planet uses are exercised. |
| `short`, `long`, `unsigned`, `signed` | recognised as basic-type keywords (`cc-tok-is-basic-type-kw?` in `110-cc-decl.fth:462`) | 8 bytes | The keywords let headers parse, but the resulting type is always 8-byte signed regardless of which modifier appeared. |
| `const`, `volatile`, `restrict`, `static`, `extern`, `auto`, `register` | parsed; ignored | — | `cc-skip-storage-quals` (`110-cc-decl.fth:97`) consumes and discards.  `static` locals behave like ordinary locals. |
| `float`, `double`, `long double` | **rejected** | — | No floating-point support at any layer. |
| bitfields              | **rejected** | — | The parser does not accept `int x : 3;`. |
| `union`                | **rejected** | — | Not a keyword in the table. |
| variable-length arrays | **rejected** | — | Array sizes must be integer literals. |

The width collapse to 8 bytes is the single biggest deviation from
ISO C and the reason the byte-identity proof is against M2-Planet
(also an 8-byte-slot compiler) and not against GCC.

## Operators

In `cc-parse-*` precedence order, lowest to highest:

| Precedence | Operators | Notes |
|---|---|---|
| assign (right-assoc) | `=`, `+= -= *= /= %= <<= >>= &= \|= ^=` | LHS must be an identifier, `*p`, `arr[i]`, or `obj.field` / `p->field`.  Compound assignments are supported when the LHS is a simple local variable; on a dereferenced, indexed, or field target only plain `=` is allowed. |
| ternary (right-assoc) | `?:` | Both arms parsed via `cc-parse-assign`; standard short-circuit shape. |
| logical or          | <code>&#124;&#124;</code> | Short-circuit; result is 0/1. |
| logical and         | `&&`   | Short-circuit; result is 0/1. |
| bitwise or          | <code>&#124;</code> | |
| bitwise xor         | `^`   | |
| bitwise and         | `&`   | Also the address-of operator at prefix position. |
| equality            | `==`, `!=` | |
| relational          | `<`, `<=`, `>`, `>=` | **Signed only.**  No unsigned compare. |
| shift               | `<<`, `>>` | `>>` is arithmetic (signed) on this signed-only subset. |
| additive            | `+`, `-` | Pointer arithmetic scaled by 8 (or 1 for `char*`). |
| multiplicative      | `*`, `/`, `%` | Signed `IDIV` semantics. |
| prefix unary        | `&`, `*`, `-`, `!`, `~`, `++`, `--`, `sizeof` | `sizeof` accepts types and expressions. |
| postfix             | `()`, `[]`, `.`, `->`, `++`, `--` | `++` / `--` lvalue forms only. |

**Comma operator** (`a, b` as an expression) is **not** supported
outside of argument lists and `for`-loop headers.

## Statements

`cc-parse-stmt` in `110-cc-decl.fth:1326` dispatches the following
forms.  Anything not listed here is rejected by the parser with one
of `110-cc-decl.fth`'s or `100-cc-expr.fth`'s codes (Appendix G).

| Form | Accepted | Notes |
|---|---|---|
| `expr ';'`                                                | yes | The catch-all path. |
| `'{' stmt* '}'`                                           | yes | Compound statement; introduces a scope. |
| `if (expr) stmt`                                          | yes | |
| `if (expr) stmt else stmt`                                | yes | |
| `while (expr) stmt`                                       | yes | |
| `do stmt while (expr) ';'`                                | yes | |
| `for (init? ; cond? ; step?) stmt`                        | yes | All three clauses optional. |
| `switch (expr) '{' (case INT ':' / default ':' / stmt)* '}'` | yes | Case labels are integer literals only — no constant expressions. |
| `break ';'`                                               | yes | Innermost loop or switch.  No "break outside loop" detection. |
| `continue ';'`                                            | yes | Innermost loop. |
| `goto LABEL ';'`                                          | yes | Function-local labels; max 64 labels per function; the target label must not be inside a `switch`. |
| `LABEL ':' stmt`                                          | yes | |
| `return ';'` / `return expr ';'`                          | yes | |
| local declaration                                         | yes | Any C declaration form recognised at file scope, plus initialisers. |
| `;` (null statement)                                      | yes | |

## Declarations

Top-level forms accepted by the top-level loop, `cc-parse-function-list`
(Ch 31):

| Form | Notes |
|---|---|
| `T name '(' params ')' '{' body '}'` (function definition) | The main case. |
| `T name '(' params ')' ';'` (function prototype)           | Registered as an `sk-func` with vaddr 0 so forward calls resolve; not emitted. |
| `T name [ = init ] ';'` (global scalar / pointer)          | Initialiser must be an integer literal, possibly negated. |
| `T name '[' INT ']' ';'`                                   | Global arrays start zeroed; no initialiser list.  Sizes are integer literals. |
| `struct TAG '{' field-decl* '}' ';'`                       | Up to 16 fields per struct; each field is a full 8-byte slot. |
| `enum [TAG] '{' name [= INT] (',' …)* '}' ';'`             | Tag optional. |
| `typedef T name ';'`                                       | Stored in the symbol table with kind `sk-typedef`. |

Parameter lists accept the same type forms as locals, plus `void`
as a single sentinel meaning "no parameters."  Variadic parameter
lists (`...`) are **rejected** — every function in this subset has
a fixed arity.

Function-pointer parameters use the `T (*name)(args)` form (see
`cc-parse-fnptr-decl` in `110-cc-decl.fth:334`).

## Preprocessor

`040-cc-prep.fth` is the entire preprocessor.  It runs once in
place over the source buffer before the lexer starts, splicing in
`#include`d files, recording `#define`s in a table, and deleting
every directive line.  It does *not* substitute macros: that
happens at lex time, when `cc-lex-ident-or-kw` (`050-cc-lex.fth`)
looks each identifier up with `cc-macro-find-int` and emits a
number token on a match.

| Directive | Accepted | Notes |
|---|---|---|
| `#include "path"`  | yes | Path tried verbatim, then under `tests/cc/`.  Nested up to four deep. |
| `#include <path>`  | elided | Accepted and dropped — the compiler's built-in shims stand in for the system headers. |
| `#define NAME body` | yes | Object-like macros only, and the body must be an integer — a decimal literal or another integer macro.  Any other body registers nothing, silently.  No function-like macros, no general text substitution. |
| `#define NAME` (empty) | elided | Registers nothing; `NAME` stays an ordinary identifier. |
| `#ifdef`, `#ifndef`, `#if`, `#endif`, `#elif`, `#else` | elided | Silently dropped, so *every* branch is compiled.  The build scripts strip the include guards that depend on these. |
| `#pragma`, `#error`, `#line`, anything else | elided | Silently dropped. |

The lack of `#ifndef` / `#endif` is the reason
`build-m2planet-monolith.sh` exists: it pre-strips the
`#include "..."` cycles that conditional compilation would
otherwise handle.

A handful of built-in macros are predefined: `NULL`, `EOF`,
`EXIT_SUCCESS`, `EXIT_FAILURE`, `stdin`, `stdout`, and `stderr`.  See
`cc-prep-builtins` in `040-cc-prep.fth`.

## Structs

Structs are storage and field-naming only.

- Up to **16 fields** per struct (Ch 24 §1; descriptors are 656
  bytes each).
- Every field occupies an **8-byte slot**, regardless of declared
  type.  `char` and `int` fields are equally 8 bytes wide inside a
  struct.
- Structs are passed and returned **by pointer only**.  Pass-by-
  value of struct values is not supported (the calling convention
  cannot express it).  Struct-typed locals and globals are fine
  (Ch 29 §5, Ch 31 §7); only crossing a call boundary needs a
  pointer.
- `sizeof(struct T)` returns `8 * field-count`.
- Nested struct *types* are allowed via tag references (`struct
  inner *next;`); inlined nested structs are not.
- Anonymous structs and unions: not supported.
- Bitfields: not supported.

## What an ISO C programmer should expect *not* to find

The set below is exhaustive of the categories that ISO C
guarantees but this compiler omits.  Items already covered in the
tables above are not repeated.

- **Floating point.** No `float`, `double`, FPU code generation,
  or `<math.h>` linkage.
- **Unsigned integer arithmetic.** Comparisons are signed; there
  is no `unsigned int` / `size_t` distinction at codegen time.
- **64-bit literals beyond `int` range** are accepted as
  integers but not range-checked.
- **Variadic functions.** No `...`, no `va_list`, no `va_arg`.
  Calls to `printf` rely on M2-Planet's libc shim, which itself
  uses fixed-arity tricks.
- **`union`.** Not implemented; absent from `kw-table`.
- **Compound literals**, **designated initialisers**,
  **statement expressions** (`({ ... })`), and other C99/GNU
  extensions.
- **Function pointers in arbitrary positions.** Function-pointer
  *variables* and *parameters* work; complex declarators like
  arrays of function pointers are not exercised.
- **Multiple translation units.** The compiler reads stdin once
  and emits one ELF.  There is no linker step, so multi-file
  builds are handled by the monolith concatenation in
  `build-m2planet-monolith.sh`.
- **Standard library.** The compiler emits 11 libc shims
  (`putchar`, `exit`, `getchar`, `fputs`, `fputc`, `fopen`,
  `fclose`, `fwrite`, `fread`, `calloc`, `free`) directly into
  the output ELF.  Everything else must be provided by the C
  source under compilation.

## Coverage in practice

The operational definition of "supported" is Stage A.  If M2-Planet
uses a construct and Stage A still produces byte-identical `.M1`,
the construct works.  If you write something not in the subset, the
likely outcome is the compiler stopping with one of the codes in
Appendix G, after printing the source line it had reached.
