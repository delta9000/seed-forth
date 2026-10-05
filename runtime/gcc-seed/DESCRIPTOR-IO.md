# Public descriptor I/O on Linux AMD64

`descriptor-io.c` supplies `open`, `read`, `close`, and `lseek` to original
source clients, including GCC libcpp. The public prototypes live in the
existing `fcntl.h` and `unistd.h`; `sys/types.h` already defines signed
64-bit `off_t` and `ssize_t`, 64-bit `size_t`, and unsigned 32-bit `mode_t`.
No upstream source changes or configuration-result overrides are involved.

## Opening and the optional mode

`open` accepts the access modes `O_RDONLY`, `O_WRONLY`, and `O_RDWR`, and
these additional Linux AMD64 flags: `O_CREAT`, `O_EXCL`, `O_NOCTTY`,
`O_TRUNC`, `O_APPEND`, `O_NONBLOCK`, `O_DIRECTORY`, `O_NOFOLLOW`,
`O_CLOEXEC`, `O_PATH`, and `O_TMPFILE`. The wrapper rejects any other bit,
access mode 3, or the isolated internal `__O_TMPFILE` bit with `EINVAL`
before making a syscall or fetching a variadic argument. This is an
intentional bounded interface: Linux may otherwise ignore unknown bits.
It does not expose or promise `O_SYNC`, `O_DSYNC`, `O_DIRECT`, `O_ASYNC`,
`O_LARGEFILE`, or `O_NOATIME`. LP64 offsets need no `O_LARGEFILE` here.
Other combinations of accepted flags receive the kernel's own validation;
filesystem support for `O_TMPFILE` is not invented by the runtime.

A mode argument is consumed exactly when `O_CREAT` is present or the full
`O_TMPFILE` pattern (including `O_DIRECTORY`) is present. Plain two-argument
opens and directory opens never read an absent third argument. Callers must
provide that argument when required; omitting a required mode is not a valid
call. `va_arg` uses `mode_t`, which is unsigned int and is unchanged by default
argument promotions on this target. Ordinary nonnegative integer permission
literals are also representable in both signed and unsigned int. The mode is
zero-extended to the syscall's long argument. The kernel applies the process
umask. A successful descriptor, including descriptor 0, belongs to the caller.
See the Linux [`open` contract](https://man7.org/linux/man-pages/man2/open.2.html).

## Transfer, offsets, errors, and ownership

Each wrapper makes at most one call through the existing `__seed_syscall6`
bridge: AMD64 syscall 2, 0, 3, or 8 respectively. Only raw values in
`[-4095, -1]` become `errno` and public `-1`; successful calls preserve errno.
The raw bridge and its register protocol are unchanged. The tests also inject
`-4096` to check the exact decoding boundary; Linux does not normally return
that value from these calls.

`read` returns the kernel's actual byte count, including partial progress or
zero at EOF. It neither fills the buffer in a loop nor retries `EINTR`. Its
count is forwarded at full target width; limits and invalid pointers are
checked by the kernel. A zero-length read still reaches the kernel, preserving
its invalid-descriptor behavior. See [`read`](https://man7.org/linux/man-pages/man2/read.2.html).

`close` never retries, including after `EINTR` or I/O errors. Linux can have
already released the descriptor when reporting such failures; retrying risks
closing a reused descriptor. See [`close`](https://man7.org/linux/man-pages/man2/close.2.html).

`lseek` preserves signed 64-bit arguments and results and forwards the whence
value for kernel validation. Public `SEEK_SET`, `SEEK_CUR`, and `SEEK_END`
constants are available from `unistd.h`, as they already were from `stdio.h`.
A pipe returns `ESPIPE`; failed seeks do not become fabricated offsets.
See [`lseek`](https://man7.org/linux/man-pages/man2/lseek.2.html).

There is no new `FILE` ownership or buffering layer. Existing `fdopen`
transfers close ownership only on success; subsequent `fclose` closes that
descriptor. After a failed `fdopen`, the caller still owns the descriptor.
Callers must not separately close a successfully adopted stream descriptor.
The raw syscall calls inside stdio remain unchanged. The bounded public
`fcntl` is documented separately in [FCNTL.md](FCNTL.md); no `openat`, `dup`,
`pipe`, or general POSIX surface is implied.

## Focused gate

Run `python3 tests/gcc/descriptor-io-check.py`. The gate is serial and limits
each subprocess to 1 GiB of virtual address space. Production executables and
renamed fault-test runtime copies are preprocessed, compiled, and linked only
by the Forth toolchain starting with the unchanged 1772-byte seed. Separate
GCC/libc builds at both O0 and O2 provide independent public-behavior oracles;
GCC also independently compiles the actual wrapper source for the same forced
syscall assertions. No host-built object is used in a production executable.

The public test covers mode/umask, exclusive creation, non-creation opens,
close-on-exec, append, truncation, signed relative offsets, a sparse file above
4 GiB, partial regular-file and pipe reads, EOF, EAGAIN, pipe seeks, invalid
whence/negative offset/descriptor, errno preservation, directory and symlink
flags, O_PATH, actual O_TMPFILE when supported, descriptor 0, and both fdopen
ownership paths. The fault test checks exact syscall arguments, unsigned
mode promotion, literal modes, full O_TMPFILE versus directory-only opens,
unsupported flags without argument consumption, EINTR without retry, close
I/O failure, wide offsets/counts, and both sides of the raw error boundary.
The JSON report records the compiler identity, input hashes, artifact hashes,
actual O_TMPFILE filesystem support, host optimizations, and memory bound.

The focused gate is also registered in `tests/gcc/check.sh`. To additionally
compile the unchanged complete original `files.c`, `pch.c`, and `makedepend.c`
consumer translation units, supply `--gcc-source-root PATH` and
`--gcc-libcpp-config PATH`, the latter naming a directory containing an
accepted original configure-generated `config.h`. Pinned source hashes and
the configuration hash are checked and recorded. No source or configuration
is changed, and output objects go only into this gate's private build directory.
This optional source contract does not run fresh configure and does not
establish an original GCC program link or execution.
