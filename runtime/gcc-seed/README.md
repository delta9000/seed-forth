# Bounded Linux AMD64 C runtime

These are original seed-forth implementations under the repository MIT
license, not copied or adapted libc source. The target is Linux AMD64 with
LP64 types, signed plain `char`, and the System V integer/pointer calling
convention. The public headers intentionally declare only implemented
interfaces; they do not claim a complete ISO C or POSIX environment.

The Forth compiler builds `memory.c`, `string.c`, and `alloc.c` as relocatable
objects. `122-cc-sysv-runtime.fth` supplies the raw Linux syscall bridge and
single-threaded errno object. No state in these C files requires a global
data initializer. The allocator stores a pair of LP64 sizes immediately
before each allocation and maps each allocation separately. This deliberately
simple design has page and syscall overhead; it is a bootstrap allocator,
not a general-purpose allocator replacement.

## Defined allocation choices

- Successful pointers have 16-byte alignment
- `malloc(0)` requests a distinct minimal allocation that can be freed
- Either zero argument to `calloc` behaves like `malloc(0)`
- An overflowing `calloc` fails with `ENOMEM`
- Requests exceeding `LONG_MAX` minus metadata fail with `ENOMEM`
- Kernel mapping errors become `NULL` plus the kernel errno value
- `free(NULL)` is a no-op, and `free` preserves errno
- `realloc(NULL, n)` is `malloc(n)`
- `realloc(p, 0)` frees a nonnull `p` and returns `NULL`
- Shrinking `realloc` can retain the mapping; growing allocates and copies
- Failed growing `realloc` leaves the original allocation and bytes intact

As with ordinary C allocation APIs, freeing an invalid pointer, double-freeing,
or accessing an allocation after its lifetime has ended is undefined. The
runtime provides no threads, signals, locale, floating parsing, dynamic loader,
or whole-libc compatibility promise. Add interfaces when an original GCC
source consumer and a corresponding test establish the need.

Production reconstruction and any host compiler/libc oracle are separate
checks. A successful host oracle must never be reported as evidence that a
production object came from the Forth compiler.

Run `python3 tests/gcc/runtime-check.py` for the Forth-only production build
and execution test. Its report records retained objects, executable and hashes.
Run `python3 tests/gcc/runtime-oracle-check.py` for the optional comparison
between Forth-built functions and host libc at host GCC `-O0` and `-O2`.
See [chapter 39](../../book/39-direct-gcc-libc.md) for the design and proof boundary.

The source-built `process.c` and `stat.c` extend this boundary with terminating
`exit` and Linux AMD64 `stat`/`fstat`. The public `sys/types.h` and `sys/stat.h`
contracts, original GCC consumers, ABI references, limitations and independent
verification are described in [Configure runtime contracts](CONFIGURE.md).

The source-built `sort.c` supplies the `qsort` consumed by original GCC
`genmodes.c`. Its constant-space heapsort, callback/reentrancy contract,
arbitrary element representations and independent production/oracle checks
are described in [Source-built qsort](SORT.md).

The source-built `ctype.c` supplies exactly the seven functions used by original
oyacc 6.6: `isalpha`, `isalnum`, `isdigit`, `isprint`, `isspace`, `isupper`, and
`tolower`. They implement the fixed ASCII C locale for EOF or unsigned-char
arguments. No locale switching or extended character classification is claimed.
The input to every function is evaluated once; EOF is never classified and
`tolower(EOF)` returns EOF.

The `assert.h` macro and source-built `assert.c` implement the C89 assertion
contract. Enabled assertions evaluate their expression once, print its spelling,
file and line to real stderr on failure, and invoke the existing real `abort`.
`NDEBUG` suppresses evaluation entirely. Reincluding the header after changing
`NDEBUG` updates the macro as required. Implicit C99 function-name metadata is
not supplied; the failure helper accepts an optional explicit function name.

Run `python3 tests/gcc/ctype-assert-check.py` for Forth-built production checks
covering EOF and every byte, side effects, NDEBUG and header reinclusion, exact
error text and real SIGABRT. Results and hashes are retained in a fresh directory.
If host GCC is available, a separate C90 build of the same ctype fixture with
host headers/libc at `-O0` and `-O2` is compared as an independent oracle. Those
host executables are never production inputs.
