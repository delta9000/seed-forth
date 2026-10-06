# Block-scope function declarations

Old GNU code (GNU make 3.82, bash, coreutils) declares library functions
inside the function that calls them:

```c
int f (void) { extern char *getenv (); return getenv ("HOME") != 0; }
```

The System V object adapter rejected every function declarator below file
scope with error 238. `cc-sysv-block-function` (`121-cc-sysv.fth`, book
chapter 36) now accepts one, with or without `extern`. It parses the
signature as a file-scope declaration does, so the declared return type is
honoured: a `char *` result is never truncated to `int`. If a function of
that name is visible, the declaration is checked for compatibility and the
visible function remains the target. Otherwise a block-scoped `sk-func`
symbol shares the translation-unit record that C90 implicit declarations
use, holding the declared signature, the pending call and address fixups,
and the object record. The name ends with its block; calls through it still
reach the one external function, through a later definition, a
`R_X86_64_PLT32` relocation, or the whole-program target's fixups.

`python3 tests/gcc/block-function-decl-check.py`, registered in
`tests/gcc/check.sh`, builds:

- `block-function-decl.c` with `block-function-decl-provider.c` through the
  Forth driver and through host GCC/glibc at `-O0`/`-O2` (strict C90,
  `-Werror`); the outputs must be identical. Nothing at file scope declares
  `getenv`, `open`, `close` or the provider functions. The program covers
  `extern char *getenv ();`, `char *getenv ();` after an array local, a
  declaration in a `case` block, the getenv result compared with the
  `environ` entry found independently (a stack pointer above 4 GiB), a
  provider returning a static buffer and one returning `0x123456789a0`, a
  block redeclaration of a file-scope prototype, the prototyped variadic
  `extern int open (const char *, int, ...);`, a block-declared function's
  address in a function-pointer variable, a definition later in the same
  file, and the name reused as a local after its block ends.
- `block-function-decl-local.c`, which needs no library, through the Forth
  driver, the whole-program System V target (`sysv-compile.sh`) and host GCC.

Rejected, each with its code: `static`, `auto` and `register` on a
block-scope function and an identifier list in the declaration (233); a
function definition inside a block (238); a declaration whose type
disagrees with a later definition, a file-scope prototype, another block's
declaration or an earlier implicit call, and a later `static` definition
(237); and use of the name after its block has ended (93).
