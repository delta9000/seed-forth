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
runtime provides no threads, dynamic loader, or whole-libc compatibility promise. Signal handling and the fixed C/POSIX locale
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

`perror` prints `strerror(errno)`, which has the glibc text for every Linux
error number ([ERRNO.md](ERRNO.md)); original GCC 4 `makedepend` reaches
`EISDIR`, `ENOTDIR`, `ENAMETOOLONG` and `ELOOP` when opening invalid output
paths. The stdio production test checks exact messages, nonempty/empty/null
prefixes, and preservation of the incoming errno value.

The source-built `process.c` and `stat.c` extend this boundary with terminating
`exit` and Linux AMD64 `stat`/`fstat`. The public `sys/types.h` and `sys/stat.h`
contracts, original GCC consumers, ABI references, limitations and independent
verification are described in [Configure runtime contracts](CONFIGURE.md).

The source-built `qsort.c` supplies the `qsort` consumed by original GCC
`genmodes.c` and cc1. It is musl 1.1.24's smoothsort, used so that equal
elements end where musl puts them and the Forth-built cc1 makes musl-linked
GCC's choices. Its provenance, contract and independent production/oracle
checks are described in [Source-built qsort](SORT.md).

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

The plumbing tools (gawk, coreutils, make, the shells and lexers) need the
numeric and stream services of an ordinary C library:

- [Correctly rounded floating input](DECIMAL-INPUT.md): `strtod`, `strtof`,
  `strtold` and `atof` with C99 decimal and hexadecimal syntax, infinities,
  NaN payloads, end pointer and glibc's `ERANGE` rules.

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
Original libiberty `pex-unix.c`, the subprocess layer GCC's driver also uses,
needs the [process API](PROCESS-API.md): `pipe`, `dup2`, `fork`, `vfork` (an
ordinary fork), `execve`, `execv`, `execvp` with PATH search, `waitpid`, `wait`,
`kill`, `sleep`, the Linux `sys/wait.h` status macros, and `strerror`.

Original binutils 2.30 bfd's native x86-64 Linux core-file header needs
[core-note records, gettimeofday and features.h](PROCFS.md): the Linux x86-64
`NT_PRSTATUS`/`NT_PRPSINFO` data types in `sys/procfs.h`, a raw syscall 96
`gettimeofday` in `sys/time.h`, and an empty `features.h` marker.

The original GCC Linux host hooks use the real bounded public
[mmap and munmap interfaces](MAPPING.md). Private file and anonymous mappings
retain kernel ownership and errors; unsupported flags fail explicitly.
The allocator continues to use its existing independent raw mapping calls.

Original GCC 4.0.4 `xgcc`, `cpp` and `collect2` need the
[driver runtime](DRIVER-RUNTIME.md): `sys/param.h` `MAXPATHLEN`, `dup`,
`chdir`, `link`, the kernel's atomic `rename`, `putenv` over a runtime-owned
`environ` vector that stores caller strings, and `fscanf` with `%c` over the
existing integer scanner. A runtime `putenv` also removes libiberty's
`putenv.o`, the one driver object that referenced an undefined plain `alloca`.

Original binutils 2.30 `gas`, `ld`, `ar`, `nm`, `objdump` and `readelf` need
the [binutils runtime](FILE-METADATA.md): the `sys/stat.h` permission macros,
`lstat`, `chmod`, `chown`, `umask`, `mkdir`, `rmdir`, `<utime.h>` `utime`,
`rewind`, `mktemp`, `towlower`, `mbstowcs`, `gmtime`, `ctime` and a bounded
`strftime`, the [`%u`, `l` and `%s` scanner conversions](INTEGER-INPUT.md#binutils-conversions),
plus [correctly rounded decimal `atof`](DECIMAL-INPUT.md) for `binutils/stabs.c`.

## POSIX surface for the plumbing tools

The GNU tools that replace the host plumbing (make, bash, sed, grep, gawk,
coreutils, tar, gzip, patch, diffutils; see
[../../gcc-direct/PLUMBING.md](../../gcc-direct/PLUMBING.md)) need a broad
POSIX layer. Each topic has its contract and a gate in
`tests/gcc/posix-*-check.py` that compares a Forth-built fixture with host
GCC/glibc at `-O0` and `-O2` (shared driver:
`tests/gcc/posix_runtime_harness.py`):

- [error numbers and their text](ERRNO.md): every Linux errno, `strerror`,
  `perror`;
- [signals](SIGNALS.md): every signal number, `sigaction`, sets, masks,
  `sigsuspend`, `raise`, `killpg`, `alarm`, `pause`, `strsignal`, `psignal`;
- [identity](IDENTITY.md): `get*id`/`set*id`, groups, process groups and
  sessions;
- [system information](SYSINFO.md): `uname`, `gethostname`, `limits.h` and
  `unistd.h` constants, `sysconf`, `pathconf`, resource limits, priority,
  `times`, POSIX clocks, `nanosleep`, `usleep`, `settimeofday`;
- [file calls](FILE-CALLS.md): links, ownership, truncation, syncing,
  `mknod`/`mkfifo`/`creat`, `flock`, `utimes`, `struct timespec` stat times,
  `major`/`minor`/`makedev`, `ar.h`, `sys/mtio.h`, `dup3`/`pipe2` and a real
  `realpath`;
- [processes](PROCESS-POSIX.md): `execl`/`execlp`/`execle`, `system`,
  `popen`/`pclose`, `wait3`/`wait4`, `atexit`/`on_exit`/`_Exit`, and `exit`
  on return from `main`;
- [users and groups](PASSWD.md): `/etc/passwd` and `/etc/group` lookups and
  `getlogin`;
- [terminals](TERMIOS.md): `termios.h`, `sys/ioctl.h`, `ioctl`, window size,
  `ttyname`, `tcgetpgrp`/`tcsetpgrp`;
- [strings and numbers](STRINGS-POSIX.md): `strings.h`, `memory.h`,
  `strndup`/`strnlen`/`stpcpy`/`strtok`/`strcoll`, `strtoll` family,
  `div`/`labs`, glibc-sequence `rand`/`random`, `isblank`, `getline`,
  and the `alloca.h` policy;
- additions to [environment and locale](ENVIRONMENT.md) (`setenv`,
  `unsetenv`, `localeconv`), [wide characters](WIDE.md) (`mbstate_t`,
  `mbrtowc` and relatives), [directories](DIRECTORIES.md) (`d_type`,
  `dirfd`, `rewinddir`) and [buffering](DIRECTORY-BUFFERING.md) (`setbuf`
  and `setvbuf` accept caller buffers).
