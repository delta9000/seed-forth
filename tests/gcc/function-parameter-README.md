# Function-declared System V parameters

The original GCC 4.0.4 `gcc/cfgloopanal.c`, commit
`944765863eec87a9f37e297994fd2af960397138`, declares `for_each_edge` with
`void (callback) (struct graph *, struct edge *)` at source line 226.
The retained direct-Forth preprocessor output places that declaration at
flattened line 37209. The accepted compiler before this change rejects it
with error 233; a small C90 GCC oracle compiles and executes the same shape.

C adjusts a function-declared parameter to a pointer to the function.
`cc-sysv-adjust-function-parameter` reuses the saved parameter-list lexer
state and existing recursive signature parser, restores the outer lexer
state, and installs the same function-pointer type as the explicit
`(*callback)` spelling. Both typed prototypes and K&R parameter declarations
use this adjustment. It does not rewrite the source, erase signatures, or
change native-target parsing or array metadata.

Run `python3 tests/gcc/function-parameter-check.py` from the repository root.
The gate checks:

- Named, grouped, registered and K&R declarations, compatible explicit
  pointer prototypes, unspecified prototypes, and recursive callback types
- Indirect calls, pointer-object `sizeof`, pointer and binary64 returns,
  and eight integer arguments crossing the register/stack ABI boundary
- GCC C90 syntax and execution, mixed Forth/GCC objects in both directions
  at `-O0` and `-O2`, and a standalone all-Forth executable
- Incompatible callback return/argument types, tags, pointer depth, arity
  and varargs; invalid storage, duplicate names, strict void, invalid
  function arrays and unnamed definition parameters
- Preservation of existing output bytes and absence of failed new output
  for every rejection case

Every test command is serial and owns a process group, capped at 1 GiB
address space and 180 CPU seconds with a 200-second wall timeout. The gate
retains commands, outcomes, output, and fixture hashes under `build-out`.
The GCC toolchain is an independent oracle, never a producer for the direct
compiler's object or executable.

`function-parameter-ranked-composition.c` is a separate pending composition
witness for adjustment of a callback taking a pointer to a rank-four array.
It requires the independent ranked-array repair and is not claimed as a pass
by this gate. Existing unrelated declarator limits, including function-type
typedefs and general anonymous function declarators, are unchanged. This
component repair is not evidence that the complete GCC bootstrap runs.

One inherited signature-parser constraint gap remains: the compiler accepts
`int f(int cb(a,b));` and the explicit-pointer spelling
`int f(int (*cb)(a,b));`. GCC with `-std=c90 -pedantic-errors` rejects both:
identifier names without parameter types are invalid in this non-definition.
Their acceptance is a known limitation, not supported C syntax. This change
reuses the existing signature parser and does not claim general C conformance.
