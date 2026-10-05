# Bounded descriptor control

Original binutils 2.30 `libiberty/pex-unix.c` saves, marks and restores
descriptors around child creation with `fcntl(fd, F_GETFD)`,
`fcntl(fd, F_SETFD, FD_CLOEXEC)`, and `fcntl(fd, F_DUPFD_CLOEXEC, 3)` (or
`F_DUPFD` plus `F_SETFD` when the former is undefined). `bfd/bfdio.c` sets
close-on-exec with `F_GETFD`/`F_SETFD`, and `bfd/opncls.c` reads the access
mode with `fcntl(fd, F_GETFL, NULL)`. No other `fcntl` command appears in
libiberty, bfd, binutils, gas, ld, opcodes, or zlib.

`fcntl.c` supplies `int fcntl(int descriptor, int command, ...)`, declared in
`fcntl.h` with these Linux AMD64 constants: `F_DUPFD` 0, `F_GETFD` 1,
`F_SETFD` 2, `F_GETFL` 3, `F_SETFL` 4, `F_DUPFD_CLOEXEC` 1030, and
`FD_CLOEXEC` 1. See the Linux [`fcntl` contract](https://man7.org/linux/man-pages/man2/fcntl.2.html).

## Arguments and results

`F_GETFD` and `F_GETFL` read no third argument, so the two-argument calls
above are valid; a supplied argument (such as `NULL`) is ignored and zero is
forwarded. `F_SETFD`, `F_SETFL`, `F_DUPFD`, and `F_DUPFD_CLOEXEC` read exactly
one `int`, which is sign-extended into the syscall argument. Callers must
supply it. Each accepted call makes one AMD64 syscall 72 through the existing
`__seed_syscall6` bridge, with no retry after `EINTR`. Only raw values in
`[-4095, -1]` become `errno` and `-1`; success returns the kernel result
unchanged (flags or the new descriptor) and preserves errno.

The kernel performs all descriptor validation and semantics: `EBADF` for a
closed descriptor, `EINVAL` for a negative or excessive duplication minimum,
the lowest free descriptor at or above the minimum, cleared close-on-exec on
an `F_DUPFD` copy, and a shared open file description (status flags and
offset). `F_SETFL` changes only the flags Linux allows, such as `O_APPEND`
and `O_NONBLOCK`; the access mode is unchanged.

Every other command fails with `EINVAL` before any syscall or argument
fetch, even for a valid Linux command such as record locks, ownership,
signals, leases, notification, pipe size or seals, and even for an invalid
descriptor. This prevents pointer-argument commands from being forwarded
with a misread argument. Add a command only with a consumer and a test.

## Close-on-exec and processes

The focused test keeps its own raw Linux pipe/fork/execve/wait4 scaffolding,
so it does not depend on the public
[process API](PROCESS-API.md), which is checked separately. It
shows that a pipe descriptor marked with `FD_CLOEXEC` is absent in an executed
`/bin/sh`, and present again after the flag is cleared.

## Focused gate

Run `python3 tests/gcc/fcntl-check.py`; it is registered in
`tests/gcc/check.sh`. Processes run serially under a one-GiB address-space
limit. The Forth-only production program checks real pipes and a regular file:
descriptor-flag round trips, access modes, `O_NONBLOCK` with real `EAGAIN`,
`O_APPEND`, `F_DUPFD` placement and sharing, `F_DUPFD_CLOEXEC`, `EBADF` for
each command, `EINVAL` for unknown and unsupported commands, and the exec
probe. The same program built by host GCC at `-O0`/`-O2` against glibc is the
independent public-behavior oracle (runtime-only `EINVAL` choices excluded).
A renamed Forth-built copy, and a separately host-compiled copy, of `fcntl.c`
check exact syscall arguments, sign extension, the error boundary, and that
unsupported commands make no syscall. When the pinned binutils source is
present, the gate also compiles unchanged `libiberty/pex-unix.c` with a
minimal hand-written configuration header; this makes no link claim.
