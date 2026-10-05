# Appendix F — The C subset

This appendix is the reference card for *what subset of C* the
compiler in `020-cc-arena.fth` through `120-cc-main.fth` actually
accepts.  The compiler is *not* an ANSI / ISO C compiler.  It started
as "enough C to compile M2-Planet" and grew to "enough C to compile
pnut unmodified" (`tests/pnut/sf-pnut-check.sh`), which is still a
specific corner of the language. Its opt-in LP64 extension now compiles
the patched TinyCC/portable-libc bootstrap profile directly (Ch 34).
The tables through “Coverage in practice” describe the unchanged
**legacy default**; the final section records the **native profile**.
Use this appendix when you want to
know whether a construct will work without running it.  Every
statement below was checked against the compiler; the constructs the
compiler accepts but gets wrong are listed as such, not hidden.

Sources of truth, in case this appendix drifts:

- Keyword set: `050-cc-lex.fth` lines 93–122 (`kw-*` constants).
- Expression grammar: `100-cc-expr.fth` lines 1–22 (header
  comment) and the `cc-parse-*` ladder.
- Type encoding: `060-cc-types.fth`.
- Statement forms: `112-cc-stmt.fth` `cc-parse-stmt`
  (lines 856–895).
- The gates in `tests/cc/`, run by `tests/cc/run-gates.sh`: each
  `P*.c` file exercises one family of the features below, and each
  `die-*` file one of the rejections (Appendix G).

If you discover a construct the compiler accepts that isn't listed
below, or rejects one that is, this appendix is wrong and the
source wins.

## Types

The compiler models a single integer width (64 bits) plus pointers
and one byte-addressable case for `char`.  Every value is stored
in an 8-byte slot at runtime; the only place width matters is in
load / store instructions (qword vs byte) and in the stride of a
subscript.

| Type form | Accepted | Width / slot | Notes |
|---|---|---|---|
| `int`                  | yes | 8 bytes | The one integer.  Signed. |
| `char`                 | yes | 1 byte (load/store); 8-byte slot in locals, fields and array elements | Loads through a `char*` zero-extend, so a `char` read from memory is 0..255 (unsigned, unlike x86 C compilers).  A `char` local is an 8-byte slot and is not truncated: `char c = 300;` keeps 300.  `(char) x` keeps the low byte. |
| `void`                 | yes (functions and pointers) | — | `void` as a function parameter list is treated as "no parameters." |
| `T*` (pointer)         | yes | 8 bytes | Any depth (`int**`, `char***`). |
| `struct T`             | yes | 8 bytes per field | See §"Structs" below. |
| `enum T`               | yes | 8 bytes | Members are integer constants; `enum T` used as a type is `int`. |
| `typedef` names        | yes | resolves to the aliased type | Registered in the symbol table.  Built in: `FILE`, `size_t`, `ssize_t`, `intptr_t`, `int8_t`…`uint64_t`, all `int`. |
| `T[N]` (array of T)    | yes (locals + globals) | `N * 8` (N slots, each 8 bytes, also for `char`) | Decays to `T*` in expressions.  `N` is a constant expression. |
| `T (*fp)(args)` (function-pointer local) | yes | 8 bytes | As a *parameter* it is rejected (code 183); use a typedef such as M2-Planet's `FUNCTION`. |
| `short`, `long`, `unsigned`, `signed`, and combinations (`unsigned long`, `long long`) | parsed | 8 bytes | `cc-tok-is-basic-type-kw?` (`110-cc-decl.fth:490`) and `cc-more-type-kws`.  Every spelling is the one 8-byte *signed* integer (`short z = 70000;` keeps 70000); a `char` among the keywords makes `char`. |
| `const`, `volatile`, `restrict`, `extern`, `auto`, `register` | parsed; ignored | — | Anywhere a type is read, including after a `*` (`char * const p`) and in parameters.  `cc-skip-storage-quals` (`110-cc-decl.fth:122`) and `cc-skip-qualifiers`. |
| `static`               | yes | — | A `static` local keeps its value between calls: it gets file-scope storage (Ch 29 §4).  On a file-scope name it changes nothing. |
| `float`, `double`, `long double` | **rejected** | — | No general floating-point arithmetic in the Forth compiler. |
| bitfields              | **rejected** | — | The parser does not accept `int x : 3;`. |
| `union`                | **rejected** | — | The legacy type parser does not handle it (code 143). |
| multi-dimensional arrays (`int m[3][4]`) | **rejected** | — | Code 159. |

The width collapse to 8 bytes is the single biggest deviation from
ISO C.  It is why the byte-identity proof is against M2-Planet's
*output* and not against GCC's code, and why a program must not
depend on `int` overflowing at 32 bits.  (pnut does not: its own
code is written for such hosts.)

## Operators

In `cc-parse-*` precedence order, lowest to highest:

| Precedence | Operators | Notes |
|---|---|---|
| assign (right-assoc) | `=`, `+= -= *= /= %= <<= >>= &= \|= ^=` | LHS must be an lvalue: a local, a global, `*p`, `a[i]`, `obj.field`, `p->field`, or any of those in parentheses.  All forms take every compound operator. |
| ternary (right-assoc) | `?:` | Only the chosen arm is evaluated. |
| logical or          | <code>&#124;&#124;</code> | Short-circuit; result is 0/1. |
| logical and         | `&&`   | Short-circuit; result is 0/1. |
| bitwise or          | <code>&#124;</code> | |
| bitwise xor         | `^`   | |
| bitwise and         | `&`   | Also the address-of operator at prefix position. |
| equality            | `==`, `!=` | |
| relational          | `<`, `<=`, `>`, `>=` | **Signed only.**  No unsigned compare. |
| shift               | `<<`, `>>` | `>>` is arithmetic (signed). |
| additive            | `+`, `-` | **Not scaled for pointers**: `p + 1` on an `int*` moves one byte.  Only a subscript scales (below). |
| multiplicative      | `*`, `/`, `%` | Signed `IDIV` semantics: truncates toward zero. |
| cast                | `(T) x` | Any type name: keywords, `struct T*`, `enum T`, typedefs, with `*`s and qualifiers.  Changes the type the parser tracks (so `*(char*) p` loads one byte, `((struct T*) p)->f` works); only `(char)` changes the value. |
| prefix unary        | `&`, `*`, `-`, `!`, `~`, `++`, `--`, `sizeof` | `&` takes a plain local only (`&g` is code 116, `&a[i]` is rejected).  `++`/`--` take any lvalue and are **not scaled** on pointers.  `sizeof` takes a type keyword, `struct T`, a typedef, or a plain local's name (`sizeof(*p)` is code 109; `sizeof(unsigned long)` is code 106). |
| postfix             | `()`, `[]`, `.`, `->`, `++`, `--` | `++`/`--` take any lvalue.  `[]` scales by 8, or by 1 for a `char*` or `char` array.  `.`/`->` need a struct type the parser knows: `mk()->v` on a call's result is code 100. |

A string literal is a `char*`, so `"abc"[1]` is `'b'`.  Adjacent
string literals are not concatenated (`"ab" "cd"` is rejected).

**Comma operator** (`a, b` as an expression) is **not** supported,
not even in a `for` header: `for (i = 0, j = 1; …)` is code 143.

**Constant expressions** (array sizes, `case` labels, enum values,
global initializers, `#if` lines) are computed at compile time with
the same operators, the ternary, `&&` and `||` (Ch 28 §9).  Their
operands are numbers, characters and enum constants; a variable is
code 125.

**Literals.**  Integers in decimal, hex (`0x1F`) and octal (`010` is
8), with any `u`/`U`/`l`/`L` suffix ignored.  Character and string
escapes: `\n`, `\t`, `\r`, `\a`, `\b`, `\f`, `\v`; one to three octal
digits (`\0`, `\033`); `\x` and hex digits (`\x1b`); any other `\c`
stands for `c` (so `\\`, `\'` and `\"` work).

## Statements

`cc-parse-stmt` in `112-cc-stmt.fth:856` dispatches the following
forms.  Anything not listed here is rejected by the parser with one
of the parser's codes (`100-cc-expr.fth` through `116-cc-prog.fth`; Appendix G).

| Form | Accepted | Notes |
|---|---|---|
| `expr ';'`                                                | yes | The catch-all path. |
| `';'` (empty statement)                                   | yes | Also as a loop body: `while (f());`. |
| `'{' stmt* '}'`                                           | yes | Compound statement; introduces a scope. |
| `if (expr) stmt`                                          | yes | |
| `if (expr) stmt else stmt`                                | yes | |
| `while (expr) stmt`                                       | yes | |
| `do stmt while (expr) ';'`                                | yes | |
| `for (init? ; cond? ; step?) stmt`                        | yes | All three clauses optional.  No declaration in `init` (`for (int i …` is code 97). |
| `switch (expr) '{' (case K ':' / default ':' / stmt)* '}'` | yes | `K` is a constant expression: `case 'x':`, `case -1:`, `case T_PLUS:`, `case N + 1:`. |
| `break ';'`                                               | yes | Innermost loop or switch.  No "break outside loop" detection: one there compiles to a stray jump. |
| `continue ';'`                                            | yes | Innermost loop, also from inside a `switch` in it. |
| `goto LABEL ';'`                                          | yes | Function-local labels; max 64 labels per function; the target label must not be inside a `switch`. |
| `LABEL ':' stmt`                                          | yes | |
| `return ';'` / `return expr ';'`                          | yes | |
| local declaration                                         | yes | Base type then declarators separated by `,`, each `*`s, a name, and `[SIZE]` or `= expr`.  No initializer lists (`int a[3] = {1,2,3}` is code 159).  A function's parameters and locals share 32 eight-byte slots (an array takes one per element); code 162 past that.  A `static` local takes no slot. |

## Declarations

Top-level forms accepted by the top-level loop, `cc-parse-function-list`
(Ch 31):

| Form | Notes |
|---|---|
| `T name '(' params ')' '{' body '}'` (function definition) | The main case.  `T` may be any type: keywords, `struct T`, `enum T`, a typedef, with `*`s. |
| `T name '(' params ')' ';'` (function prototype)           | Registered as an `sk-func` with vaddr 0 so forward calls resolve; not emitted.  Calling a function with neither a prototype nor an earlier definition is code 93. |
| `T name [ = CONSTANT ] (',' …)* ';'` (global scalars / pointers) | The initializer is a constant expression.  No string initializers (`char* s = "hi";` is code 126). |
| `T name '[' SIZE ']' ';'`                                  | Global arrays start zeroed (they live in the bss); no initializer list. |
| `extern T name;` then `T name = C;`                        | One variable: the second declaration reuses the first's slot. |
| `struct TAG '{' field-decl* '}' ';'`                       | Up to 16 fields per struct; each field is a full 8-byte slot.  No forward declaration `struct TAG;` (code 203). |
| `enum [TAG] '{' name [= CONSTANT] (',' …)* '}' ';'`        | Tag optional. |
| `typedef T name ';'`, `typedef T (*name)(…);`              | Stored in the symbol table with kind `sk-typedef`.  `typedef struct T {…} Name;` is rejected (code 146), and a typedef of a struct type loses the descriptor that `->` needs. |

Parameter lists accept the same type forms as locals, plus `void`
as a single sentinel meaning "no parameters."  At most six parameters
and six arguments (code 122 for a seventh argument): every argument
travels in a register.  Variadic parameter lists (`...`) are
**rejected** (code 182).  A function-pointer parameter must be
spelled with a typedef; `int (*f)(int)` in a parameter list is code
183 (see `cc-parse-fnptr-decl` in `110-cc-decl.fth:396` for the local
form).

## Preprocessor

`040-cc-prep.fth` is the entire preprocessor: one pass over the
source before the lexer starts, which splices in `#include`d files,
expands every macro, and drops the lines of false conditional groups
(Ch 22).

| Directive | Accepted | Notes |
|---|---|---|
| `#include "path"`  | yes | Path tried verbatim, then under `tests/cc/`.  Nested up to four deep; each file up to 256 KiB. |
| `#include <path>`  | dropped | The compiler's built-in shims, typedefs and macros stand in for the system headers. |
| `#define NAME body` | yes | Any body, including an empty one; continued lines with `\`. |
| `#define NAME(a, b) body` | yes | Function-like, up to 16 parameters.  Arguments are expanded before substitution and the result is rescanned; a macro is not expanded inside its own expansion.  No `#` (stringizing) or `##` (pasting), no `...`. |
| `#undef NAME` | yes | |
| `#if`, `#ifdef`, `#ifndef`, `#elif`, `#else`, `#endif` | yes | `#if` / `#elif` take a constant expression with `defined NAME` and `defined(NAME)`; names left after expansion are 0.  Nested up to 64 deep. |
| `#error` | yes | Stops the compiler (code 40) unless it is in a dropped group. |
| `#pragma`, `#line`, anything else | dropped | Silently. |

Built-in macros: `NULL`, `EOF`, `EXIT_SUCCESS`, `EXIT_FAILURE`,
`stdin`, `stdout`, `stderr`, and `open(2)`'s flags `O_RDONLY`,
`O_WRONLY`, `O_CREAT`, `O_TRUNC`.  See `cc-prep-builtins` in
`040-cc-prep.fth`.  There is no `__FILE__`, `__LINE__` or `__STDC__`,
and no `-D`: the compiler reads the program on stdin, so a
configuration is `#define` lines placed in front of it.

`build-m2planet-monolith.sh` predates conditional compilation: it
still deletes each `.c` file's `#include "…"` lines and concatenates
the headers once, although `cc.h`'s own `#ifndef CC_H` guard now
works.

## Structs

Structs are storage and field-naming.

- Up to **16 fields** per struct (Ch 24 §1; a 56-byte header plus a
  field table of 40-byte records that grows 8, then 16).
- Every field occupies an **8-byte slot**, regardless of declared
  type.  `char` and `int` fields are equally 8 bytes wide inside a
  struct, and `sizeof(struct T)` is `8 * field-count`.
- No arrays inside a struct (`int arr[4];` as a field is rejected).
- Structs are passed and returned **by pointer only**, and assigned
  field by field (`b = a` on two struct values is code 120).
  Struct-typed locals and globals are fine (Ch 29 §6, Ch 31 §7).
  **Passing a struct by value is not rejected but miscompiled**:
  the callee reads garbage.
- A field may point to a struct defined later, but `->` through such a
  field has no descriptor (code 100); go through a local of the right
  type.  A struct *value* nested inline as a field compiles, but
  `sizeof` counts it as one 8-byte field.
- A field holding a function pointer cannot be called directly:
  `s->fn(4)` is rejected; copy it into a local first.
- Anonymous structs and unions: not supported.  Bitfields: not
  supported.

## What an ISO C programmer should expect *not* to find

The set below is exhaustive of the categories that ISO C
guarantees but this compiler omits.  Items already covered in the
tables above are not repeated.

- **Floating point.** No `float`, `double`, FPU code generation,
  or `<math.h>` linkage.
- **Unsigned integer arithmetic.** Comparisons, `>>`, `/` and `%` are
  signed; `unsigned` is only a spelling.
- **64-bit literals beyond `int` range** are accepted as
  integers but not range-checked.
- **Variadic functions.** No `...`, no `va_list`, no `va_arg`.
- **`union`.** Not implemented by the legacy type parser.
- **Initializer lists**, **compound literals**, **designated
  initialisers**, **statement expressions** (`({ ... })`), and other
  C99/GNU extensions.
- **Declarations inside `for`** (`for (int i = 0; …)`, code 97).
- **Multiple translation units.** The compiler reads stdin once
  and emits one ELF to `/tmp/cc-out`.  There is no linker step, so
  multi-file builds are done by `#include "…"` or by concatenation.
- **Standard library.** The compiler emits libc shims directly into
  the output ELF: eleven in every program (`putchar`, `exit`,
  `getchar`, `fputs`, `fputc`, `fopen`, `fclose`, `fwrite`, `fread`,
  `calloc`, `free`) and eight more only when called (`malloc`,
  `open`, `read`, `write`, `close`, `strlen`, `memcpy`, `strrchr`).
  `FILE*` is a file descriptor and I/O is unbuffered.  `free` does
  nothing; `calloc` and `malloc` bump through one 256 MiB mapping.
  Everything else must be provided by the C source under
  compilation: a function that is called but never defined stops the
  compile with code 206, and so does `memset`, which is declared for
  the upstream tests but has no body.

## Coverage in practice

The operational definition of "supported" is two proofs and the
gates.  Stage A: if M2-Planet uses a construct and its `.M1` output
stays byte-identical, the construct works.  `tests/pnut/sf-pnut-check.sh`:
if pnut uses it and the pnut this compiler builds generates the same
bytes as an M2-Planet-built pnut, it works.  The `tests/cc/` gates
cover the constructs neither program reaches.  If you write something
not in the subset, the likely outcome is the compiler stopping with
one of the codes in Appendix G, at the line it had reached; the
exceptions, constructs it accepts and gets wrong, are called out
above.

## Opt-in native profile for TinyCC

[Chapter 34](34-direct-tinycc.md) owns the native declaration, program,
initializer, and runtime code. `tests/tcc/compile-native.sh` enables
`cc-target-lp64` and `cc-prep-direct`; the normal compiler driver does
not. The shared expression and statement code dispatches on that mode.

| Area | Native contract |
|---|---|
| Integer storage | `char`/`unsigned char` 1 byte, `short`/`unsigned short` 2, `int`/`unsigned int` 4, `long` and the distinct `long long`, with unsigned variants, 8, pointers 8; typed loads, stores, casts, and signed/unsigned operations |
| Calls | Private all-stack ABI, every argument in an eight-byte slot, scalar return in `rax`; direct calls, function pointers, and portable-libc stack varargs; aggregate-by-value parameters, returns and arguments rejected with 212 |
| Local storage | Frame size calculated from declarations and patched after each function body, aligned to sixteen bytes |
| Aggregates | Structs/unions with aligned offsets, nested aggregates, forward tags in a separate namespace, typedef descriptors, anonymous member promotion, array members, value copy/assignment |
| Arrays | Element-sized storage and strides; two-dimensional objects; array parameters decay to pointers; general pointer-to-array declarators and nested array fields remain outside the profile |
| Initializers | Bounded brace lists, zero fill, adjacent/escaped character strings, inferred outer bounds, local aggregate copies, and constant-category static initializers including address fixups |
| Expressions | Width-aware integer semantics, pointer arithmetic, native comma expressions, broader lvalue address/`sizeof` support, adjacent string literals, direct and indirect calls |
| Statements | Declaration-form `for`, labels with statements, and label/`case` handling including targets inside switches |
| Preprocessor | Real quoted/angle includes, source-relative search for quoted names, configured include directories, repeatable inclusion, stringizing, token pasting, macro rescanning, and explicit missing-header failures |
| Runtime | Thirteen direct Linux syscall primitives; portable C libc supplies heap, strings, FILE operations and formatting; no host libc/object linkage |

The profile remains bounded: normal-mode floating types fail with error
214, including in signatures and casts; there is no general IEEE floating
arithmetic, C
bitfield parser, variable-length array implementation, designated
initializers, compound literals, or arbitrary external-object linker.
The target's existing bootstrap compatibility conditionals avoid those
forms where needed. Native integer/aggregate support does not imply
acceptance of every ISO C declarator or ABI form.

`SF_NATIVE_FLOATBITS=1` selects an additional **seed-only** restriction:
float, double and long-double data use eight-byte integer bit transport.
Only this mode provides fail-closed `localtime`, `ldexp`, and `longjmp`
bodies, each diagnosing its exact name and exiting 125. With the flag
unset they remain undefined and ordinary references are error 206; the
normal `ldexp` declaration fails earlier with 214 because it uses floating
types. This is not a
floating-point implementation, nor silent emulation of missing libc.

The rebuilt TinyCC is a different compiler: its own target backend and
standard call ABI support the real-floating, bitfield, VLA, and local-enum
programs tested after the direct bootstrap. The executable/object fixed
points and all 136 libc checks are reported separately from the focused
Forth compiler gates in [`tests/tcc/README.md`](https://github.com/delta9000/seed-forth/blob/master/tests/tcc/README.md).
