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
