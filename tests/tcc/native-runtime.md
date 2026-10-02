# Direct native runtime boundary

`119-cc-native-runtime.fth` is part of the opt-in native compiler. Its
`cc-native-runtime` hook runs after the native ELF entry stub and before
source parsing. It emits Linux AMD64 instructions directly through Forth;
there is no host libc, assembler, linker, object input, or pnut executable.

Every argument occupies one eight-byte private-ABI stack slot. A leaf
primitive loads arguments at `rsp+8`, `rsp+16`, and `rsp+24`; it returns in
`rax`. Source-generated functions use the corresponding `rbp+16` convention
after their frame prologue. `read`, `write`, `lseek`, and `time` have signed
64-bit return types. Other integer primitives return `int`; `exit` returns
`void`. Ordinary C prototypes can update the symbol's type/descriptor.

## Implemented kernel operations

The finite primitive list is `exit`, `read`, `write`, `open`, `close`,
`lseek`, `unlink`, `mkdir`, `chmod`, `access`, `mprotect`, `time`, and
`gettimeofday`. `mmap` and `munmap` are unnecessary for this measured seed
profile: its portable C libc supplies a bounded static heap plus
`malloc`, `free`, and `realloc`. That libc also supplies FILE operations,
strings, formatting, and callbacks through the same private ABI.

Linux error results in the unsigned range corresponding to `-4095..-1`
become exactly `-1`; this boundary does not set `errno`. The original pnut
primitive returned raw `-errno`, despite portable-libc `fopen` and `fclose`
checking `fd == -1`. Native normalization fixes missing-file behavior and
is verified against the actual portable libc, not just synthetic wrappers.

## Restricted seed-only failures

The complete target call inventory was checked using the direct
`libc-first.c` profile and, independently, the saved oracle AST. Host GCC
was used only to strip comments for the audit, and pycparser only to
inspect it; neither output was a bootstrap compiler input. After indirect
function-pointer calls are excluded and all C function bodies plus the
13 kernel primitives are accounted for, exactly three names lack
implementations: `localtime`, `ldexp`, and `longjmp`.

Only when `cc-bootstrap-floatbits` is enabled, these three exact names
receive fail-closed bodies. Each writes `seed-forth bootstrap: unsupported
NAME` plus a newline to stderr and exits 125. No arbitrary undefined
function is accepted. Without this restricted seed flag, these three
names remain undefined. Ordinary references fail with error 206; normal
native mode rejects floating types with 214, so the usual `ldexp` prototype
fails that earlier check.

The restrictions are observable, not statements that these paths can
never execute:

- `ldexp` is used when TinyCC reads hexadecimal floating literals
- `localtime` is used for `__DATE__` and `__TIME__`
- `longjmp` is used after compilation errors while
  `error_set_jmp_enabled` is set. The portable-libc stub `setjmp` returns
  zero, and `tcc_compile` then enables that path. Successful builds avoid
  it; malformed input need not

The original pnut recipe enables `UNDEFINED_LABELS_ARE_RUNTIME_ERRORS`.
Its `vendor/pnut/exe.c:assert_all_labels_defined` supplies a diagnostic and
then returns from unresolved named functions. This native boundary is
intentionally stricter: an unsupported operation cannot continue.

Do not enable portable libc's `ADD_LIBC_STUB` wholesale. It adds 24
functions, including all 16 ctype helpers, three time functions, two
signal stubs, `ldexp`, `longjmp`, and an aborting `mprotect`; the last
conflicts with the working kernel primitive. Its `localtime` also aborts
for a non-null timestamp, exactly what the TinyCC caller supplies.

Every downstream build must terminate successfully; reaching any of
these three failures exits 125 and invalidates that build. The generated
full TinyCC needs separate acceptance tests; boundary tests alone are not
a TinyCC self-build or fixed-point claim. The rebuilt boot2 and boot3
have independently passed real float, double, and long-double arithmetic,
bitfields, variable-length arrays, and local-enum acceptance programs,
and their executable/object fixed points match the existing control.
Those results are recorded in [README.md](README.md); they do not expand
the seed-only runtime contract described here.

## Tests

Run `tests/tcc/native-runtime-check.sh` for:

- All 13 kernel primitives, including a sparse file offset above 4 GiB,
  a two-argument `open`, error normalization, and LP64 time structures
- An eight-argument call mixing signed char/short, unsigned int, long,
  array-to-pointer decay, pointers, and an unsigned 64-bit value
- A real `exit(37)` that does not return
- Visible exit-125 behavior for each restricted seed failure
- Undefined-function error 206 for `localtime`/`longjmp` in normal mode,
  floating-type error 214 for the normal `ldexp` prototype, and error 206
  for an unrelated unknown function in both modes

Run `tests/tcc/native-runtime-libc-check.sh [STAGED_LIBC64]` after staging
the pinned portable-libc sources. This compiles and runs that actual C
libc with the direct compiler, checking FILE read/write/seek/tell/close,
removal, failed `fopen`, and eight-value `fprintf` varargs. It also checks
that no bootstrap-failure diagnostic appeared. Both harnesses use
isolated output directories and execute no host C toolchain.
