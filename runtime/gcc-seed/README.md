# Bounded Linux AMD64 C runtime

These are original seed-forth implementations under the repository MIT
license, not copied or adapted libc source. The target is Linux AMD64 with
LP64 types, signed plain `char`, and the measured System V calling contracts.
The public headers intentionally declare only implemented
interfaces; they do not claim a complete ISO C or POSIX environment.

The Forth compiler builds `memory.c`, `string.c`, and `alloc.c` as relocatable
objects. `122-cc-sysv-runtime.fth` supplies the raw Linux syscall bridge and
single-threaded errno object. No state in these C files requires a global
data initializer. The allocator stores a pair of LP64 sizes immediately
before each allocation. Payloads up to 2048 bytes use eight power-of-two
classes from 16 to 2048 bytes, sharing 64 KiB slabs. Freeing a small block
returns it to its class free list. Slabs stay mapped until process exit;
retention follows each class's lifetime high-water demand. Larger requests
use individual mappings, released by free. This single-threaded bootstrap
allocator is not safe for concurrent or signal-handler allocation.

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
runtime provides no threads, floating input parsing, dynamic loader, or
whole-libc compatibility promise. Signal handling and the fixed C/POSIX locale
have separate bounded contracts below. Add interfaces when an original source
consumer on the documented bootstrap path and a corresponding test establish
the need.

Production reconstruction and any host compiler/libc oracle are separate
checks. A successful host oracle must never be reported as evidence that a
production object came from the Forth compiler.

Run `python3 tests/gcc/runtime-check.py` for the Forth-only production build
and execution test. Its report records retained objects, executable and hashes.
Run `python3 tests/gcc/runtime-oracle-check.py` for the optional comparison
between Forth-built functions and host libc at host GCC `-O0` and `-O2`.
See [chapter 39](../../book/39-direct-gcc-libc.md) for the design and proof boundary.

The bounded `perror` message table includes `EISDIR`, `ENOTDIR`,
`ENAMETOOLONG`, and `ELOOP`: original GCC 4 `makedepend` reaches these when
opening invalid output paths. The stdio production test checks exact messages,
nonempty/empty/null prefixes, and preservation of the incoming errno value.
Unlisted errors retain the documented numeric `Unknown error` fallback.

The source-built `process.c` and `stat.c` extend this boundary with terminating
`exit` and Linux AMD64 `stat`/`fstat`. The public `sys/types.h` and `sys/stat.h`
contracts, original GCC consumers, ABI references, limitations and independent
verification are described in [Configure runtime contracts](CONFIGURE.md).

The source-built `sort.c` supplies the `qsort` consumed by original GCC
`genmodes.c`. Its constant-space heapsort, callback/reentrancy contract,
arbitrary element representations and independent production/oracle checks
are described in [Source-built qsort](SORT.md).

The same `sort.c` supplies `bsearch`, and `strerror.c` supplies `strerror`.
Original GCC `tree-eh.c` and `tree-dump.c` call them; libiberty can provide
both, but only a declaration makes their pointer results visible to callers.
See [bsearch and strerror](SEARCH-STRERROR.md).

The source-built `ctype.c` supplies the seven functions used by original
oyacc 6.6: `isalpha`, `isalnum`, `isdigit`, `isprint`, `isspace`, `isupper`, and
`tolower`. They implement the fixed ASCII C locale for EOF or unsigned-char
arguments. Only the ASCII C/POSIX locale is available.
The input to every function is evaluated once; EOF is never classified and
`tolower(EOF)` returns EOF. The measured Heirloom/Flex successor adds `isascii`,
`islower`, `isxdigit`, `toupper`, `iscntrl`, `isgraph`, and `ispunct`, with
complete argument-domain tests in
[Lexer classification](CTYPE-LEX.md).

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

The measured parser-generator path also uses [unsigned string conversion](STRTOUL.md),
[integer absolute values](ABS.md), [short option parsing](GETOPT.md), and
[persistent signal handlers](SIGNAL.md). Each document gives the implemented
contract, original source consumer, and production/reference checks. These
interfaces extend the bounded runtime without claiming a complete libc.

The parser/lexer source chain adds independently documented contracts for
[process startup](STARTUP.md), [descriptor ownership and temporary files](DESCRIPTORS.md),
[write](WRITE.md), [real process environment and C/POSIX locale](ENVIRONMENT.md),
[ASCII wide characters](WIDE.md), [ASCII wide stream formatting](WIDE-STDIO.md),
[target floating format metadata](FLOAT-HEADER.md), [application block size](BUFSIZ.md),
[Flex stream operations](STREAM-FLEX.md), [terminal detection](ISATTY.md), and
[bounded integer input](INTEGER-INPUT.md). The runtime-aware entry initializes
the program name and real environment before main; the separate raw entry
continues to support minimal syscall proofs. Each stage records its exact
implemented surface, explicit limits, owner tests and independent oracle use.

The original Flex nonlocal-return surface uses source-built `setjmp` and
`longjmp`. The private buffer layout, C90 usage limits and separate Forth-only
and host ABI checks are documented in [Ordinary nonlocal return](NONLOCAL.md).

Original GCC `libcpp/files.c` also needs [directory traversal](DIRECTORIES.md).
The source-built `dirent.c` supplies `opendir`, `readdir`, and `closedir` through
real Linux directory syscalls, with bounded buffers, checked records and
explicit EOF/error behavior. This resolves the header/runtime prerequisite;
the separate pointer-to-array parser limitation still blocks full libcpp.

The [approximate exp/log contract](MATH.md) is implemented in a separate
[explicit Forth-built math archive](MATH-LINKING.md), selected by literal `-lm`.

Original libcpp macro expansion uses the [bounded UTC calendar runtime](CALENDAR.md):
real wall-clock time, a standard nine-int `struct tm`, and Gregorian conversion
under explicit `TZ=UTC0`. Unsupported timezones fail rather than silently
changing the interpretation.

## Public descriptor I/O

The original-source GCC client path has public `open`, `read`, `close`, and
`lseek` declarations and real syscall-backed implementations. See
[DESCRIPTOR-IO.md](DESCRIPTOR-IO.md) for the explicit flag/varargs boundary,
64-bit offset semantics, ownership, and the focused Forth/host-oracle gate.

Original GCC precompiled-header macro restoration also uses the
[byte-string rejection span](STRCSPN.md). The isolated source-built
`strcspn.c` returns a `size_t` count and leaves existing string functions
unchanged. Its focused gate separates Forth production from host libc and
host-to-Forth ABI checks.

Original binutils 2.30 libiberty needs [exact-width integer types](STDINT.md)
(`stdint.h`, also included by `inttypes.h`) for `obstack.c`, and
[bounded descriptor control](FCNTL.md) for `pex-unix.c`: `fcntl` supports only
the close-on-exec, status-flag and duplication commands binutils uses, and
fails with EINVAL for every other command.

The original GCC Linux host hooks use the real bounded public
[mmap and munmap interfaces](MAPPING.md). Private file and anonymous mappings
retain kernel ownership and errors; unsupported flags fail explicitly.
The allocator continues to use its existing independent raw mapping calls.
