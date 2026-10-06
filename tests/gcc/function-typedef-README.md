# Typedefs of function types

Bash 2.05b and readline declare their callback types as function types,
not pointers to functions:

```c
typedef int Function ();
typedef char *CPFunction ();
typedef int sh_builtin_func_t (WORD_LIST *);
```

The System V declarator check rejected any typedef whose declarator ended in
a parameter list with error 238. `cc-sysv-function-typedef`
(`121-cc-sysv.fth`, book chapter 36) now records such a typedef as base
`ty-func` with no star and the signature as its descriptor: the
pointer-to-function representation one star short. So:

- `Function *p`, `CPFunction *table[3]` and a member `VFunction *cb` are
  ordinary function pointers and call through the recorded signature; a
  `char *` result keeps all 64 bits;
- `Function g;` at file or block scope (with or without `extern`) declares a
  function, compatible with a later definition;
- a parameter `sh_fn_t f`, prototyped or in an identifier-list definition,
  adjusts to a pointer to function;
- `typedef Function Function2;` aliases the function type.

`python3 tests/gcc/function-typedef-check.py`, registered in
`tests/gcc/check.sh`, builds `function-typedef.c` with the Forth driver and
host GCC/glibc at `-O0`/`-O2` (strict C90, `-Werror`); the outputs must be
identical. It covers each form above, a static initializer table of
callbacks, `sizeof (Function *)`, a cast to `Function *`, a function
returning `Function *`, a provider returning a pointer above 4 GiB through a
`CPFunction *` table, and getenv through a block-scope
`extern CPFunction getenv;`.

Rejected: an array or member of function type, a function returning a
function type and a definition `F g { ... }` (238); a typedef with an
identifier list and `static F g;` in a block (233); a declaration through
the typedef that disagrees with a later definition (237).
