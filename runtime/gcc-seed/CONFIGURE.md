# Configure runtime contracts

This increment supplies the interfaces demanded by the original GCC 4.0.4
configure source and its C preprocessor. It does not make every GCC configure
test pass, and does not claim a complete libc or a completed GCC bootstrap.

The source is the unmodified `gcc-mirror` release commit
`944765863eec87a9f37e297994fd2af960397138`, pinned in
[`gcc64/SOURCES`](../../gcc64/SOURCES). In that source:

- `gcc/configure:2517` and `:2518` include `sys/types.h` and `sys/stat.h` in
  the ANSI C compilation probe
- `gcc/configure:2667` uses `exit(42)` and many executable probes call `exit`
- `gcc/configure:10156` calls `fstat` in a vfork test; the other process APIs
  needed by that test remain outside this increment
- `libcpp/files.c:212` and `:261` use `fstat` and `stat`, respectively
- `gcc/system.h:457` onward and `libcpp/system.h:293` onward consume file-kind
  mode macros

No C bootstrap consumer requiring `lstat` was found. The Ada implementation
uses it, but Ada is outside this bootstrap's scope, so no `lstat` declaration
or implementation is supplied. Permission-changing APIs remain absent;
later [descriptor contracts](DESCRIPTORS.md) add measured file creation and
exclusive temporary files for original oyacc.

## ABI and provenance

The declarations and implementations are original seed-forth code under the
repository [MIT license](../../LICENSE). They encode ABI facts, rather than
copying libc implementations. The following primary sources were checked
on 2026-10-03:

- Linux v6.12 [AMD64 stat layout](https://github.com/torvalds/linux/blob/v6.12/arch/x86/include/uapi/asm/stat.h)
  defines the kernel field order, widths and padding
- Linux v6.12 [scalar ABI types](https://github.com/torvalds/linux/blob/v6.12/include/uapi/asm-generic/posix_types.h)
  and glibc 2.40 [x86 public type widths](https://github.com/bminor/glibc/blob/glibc-2.40/sysdeps/unix/sysv/linux/x86/bits/typesizes.h)
  establish the LP64 scalar types
- Linux v6.12 [file-kind constants](https://github.com/torvalds/linux/blob/v6.12/include/uapi/linux/stat.h)
  establish the mode masks and values
- Linux v6.12 [AMD64 syscall table](https://github.com/torvalds/linux/blob/v6.12/arch/x86/entry/syscalls/syscall_64.tbl)
  assigns `stat`, `fstat` and `exit` their syscall numbers
- Linux v6.12 [process termination](https://github.com/torvalds/linux/blob/v6.12/kernel/exit.c)
  establishes the low-byte status contract

The referenced Linux UAPI files identify their license as
`GPL-2.0 WITH Linux-syscall-note`; Linux `kernel/exit.c` is GPL-2.0-only;
the referenced glibc type header is LGPL-2.1-or-later. These sources remain
under their own licenses. No upstream source text is vendored here, and no
host header or object becomes an input to production compilation.

`struct stat` is 144 bytes with alignment 8 on Linux AMD64. Its field offsets
are checked against an independently compiled host header and an actual
kernel result. Size, block count and time seconds are signed 64-bit values;
device, inode and link counts are unsigned 64-bit values; mode, UID and GID
are unsigned 32-bit values. The time-seconds words have the kernel's binary
layout while exposing signed `time_t`, including pre-epoch timestamps.
The times are now POSIX.1-2008 `struct timespec` members `st_atim`,
`st_mtim` and `st_ctim` with the same bytes; `st_atime`/`st_mtime`/`st_ctime`
and the older `st_*time_nsec` names are macros for their fields (see
[FILE-CALLS.md](FILE-CALLS.md#times-in-struct-stat)). Padding and reserved
words are not public application data.

The wrappers pass the caller's buffer directly to syscall 4 or 5. Results
from -4095 through -1 become -1 with positive `errno`; successful calls
preserve `errno`. There is no narrow-field conversion or invented success.
The real kernel supplies path following, file-descriptor validation,
permissions, sparse file size, timestamps and file kind. The API is specific
to Linux AMD64 LP64; other operating systems, x32 and i386 need separate
layouts and entry points. Later parser/lexer stages add only their measured
interfaces; passing a narrow configure probe does not imply full conformance.

## Process termination

`exit` never returns. It writes out pending buffered stdio output (see
[STDIO-BUFFERING.md](STDIO-BUFFERING.md)), then invokes Linux syscall 60 with
the status low byte; the runtime-aware startup passes `main`'s result to this
`exit`. The supported runtime has one thread and no `atexit` or `tmpfile`
registration; kernel process termination releases open file descriptors.
If an external syscall filter denies termination, `exit` keeps attempting
termination instead of returning to its caller.

## Abnormal termination

The original libiberty `C_alloca` failure path requires `abort`. The bounded
runtime implements it with real SIGABRT delivery, including a previously
blocked or ignored signal. It first unblocks SIGABRT and sends it to the
current thread. An installed handler can leave through a nonreturning action;
if it returns, the runtime installs the default disposition, unblocks the
signal again, and sends it again. If signal delivery is denied, termination
falls back to status 134 through `exit`; `abort` never returns normally.
Normal operation terminates from signal 6 rather than merely returning that
numeric exit status.

The implementation uses Linux AMD64 syscall numbers from the pinned-reference
[syscall table](https://github.com/torvalds/linux/blob/v6.12/arch/x86/entry/syscalls/syscall_64.tbl).
Its private action buffer is the kernel ABI's four eight-byte words: handler,
flags, restorer, and mask. It is not glibc's public `struct sigaction` layout.
The [GNU C library description](https://www.gnu.org/software/libc/manual/2.30/html_node/Aborting-a-Program.html)
describes the signal/handler contract; this implementation is original project
code, not copied libc source. The supported runtime is still single-threaded.
The later [signal contract](SIGNAL.md) supplies bounded persistent handler
registration separately from this original abort increment.

`python3 tests/gcc/abort-check.py` builds production objects and their executable
with Forth, then verifies default, blocked, and ignored SIGABRT termination.
Separate host ABI oracles test a returning handler, `siglongjmp`, a handler
that exits, and a handler that changes the disposition/mask. A separate syscall
double verifies exact raw arguments and the failed-delivery fallback. Tests
disable core files only in their child processes. The optional `--compiler-root`
argument selects a recorded immutable compiler during concurrent development;
every report records its exact compiler/runtime input hashes.

## Verification

Run from the repository root:

```sh
python3 tests/gcc/configure-runtime-check.py
python3 tests/gcc/configure-runtime-oracle-check.py
```

The first command compiles runtime C and fixtures using the Forth compiler,
emits syscall/errno/startup objects from Forth, links with the Forth linker,
and retains objects, executables and SHA-256 records under `build-out`.
It tests all exposed type widths and signedness, struct size/alignment and
field offsets, a sparse file larger than 8 GiB, a negative mtime with
nanoseconds, a hard link, symlink following, directories, pipe descriptors,
ENOENT/EBADF/EFAULT and preservation of `errno` after success. An isolated
Forth-built syscall double checks argument registers, the raw-error bounds
and EOVERFLOW. It is linked only into the fault-test executable.

Exit is exercised with nine positive/negative statuses, verifies absence
of post-exit output, and leaves a buffered file stream open to prove that
exit writes its bytes. The test runner and Python `os.stat` are orchestration and
independent observation, not producers of target code.

The second command separately compiles the layout fixture against host
system headers and host libc at `-O0` and `-O2`, then compares its complete
output to the Forth-produced executable. It can reuse a production run by
accepting the path to that run's `report.json`; it rejects stale source
hashes. Host compilers, assemblers, linkers and libc are used only for this
explicitly labeled oracle and contribute no production bytes.
