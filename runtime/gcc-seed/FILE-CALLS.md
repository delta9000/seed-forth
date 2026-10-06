# File-system calls, device numbers and realpath

`cp`, `mv`, `ln`, `install`, `touch`, `mkfifo`, `mknod`, `readlink`, `tar`
and `patch` need the rest of the POSIX file calls. Each wrapper below is one
Linux AMD64 syscall through `__seed_syscall6`; raw results in `[-4095, -1]`
become errno and -1, nothing is retried, and the kernel validates every
argument.

| Function | Syscall | Header |
|---|---|---|
| `symlink`, `readlink` | 88, 89 | `unistd.h` |
| `fchdir`, `fchown`, `lchown` | 81, 93, 94 | `unistd.h` |
| `truncate`, `ftruncate` | 76, 77 | `unistd.h` |
| `fsync`, `fdatasync` | 74, 75 | `unistd.h` |
| `chroot`, `sync` | 161, 162 | `unistd.h` (`sync` cannot fail) |
| `dup3`, `pipe2` | 292, 293 | `unistd.h` (`O_CLOEXEC` is the useful flag) |
| `fchmod`, `mknod` | 91, 133 | `sys/stat.h` |
| `flock` | 73 | `sys/file.h` with `LOCK_SH`/`EX`/`NB`/`UN` |
| `utimes` | 235 | `sys/time.h` (microseconds; NULL means now) |
| `ioctl` | 16 | `sys/ioctl.h`; see [TERMIOS.md](TERMIOS.md) |

`readlink` writes no terminating NUL and returns the byte count (truncated
to the buffer). `dup3` of equal descriptors fails with `EINVAL`, unlike
`dup2`. `mkfifo(path, mode)` is `mknod(path, (mode & 07777) | S_IFIFO, 0)`,
and `creat(path, mode)` (`fcntl.h`) is
`open(path, O_WRONLY | O_CREAT | O_TRUNC, mode)`; both are separate archive
members so a program's own versions do not collide with them. `ftruncate`
is likewise its own member (gnulib replaces it on some systems).

`fcntl.h` adds `O_DSYNC`, `O_ASYNC`/`FASYNC`, `O_DIRECT`, `O_NOATIME`,
`O_SYNC`/`O_RSYNC` (Linux values), `O_NDELAY` (= `O_NONBLOCK`) and
`O_LARGEFILE` (0: every LP64 open is large-file capable), and `open` accepts
the new bits; see [DESCRIPTOR-IO.md](DESCRIPTOR-IO.md).
`sys/stat.h` adds `S_IREAD`/`S_IWRITE`/`S_IEXEC`, `ACCESSPERMS`, `ALLPERMS`
and `DEFFILEMODE`. `ar.h` describes the 60-byte `struct ar_hdr` member
header (`ARMAG`, `SARMAG`, `ARFMAG`) that `make` reads to find archive
member times. `sys/mtio.h` holds only the Linux `struct mtop`, `struct
mtget`, `struct mtpos`, `MTIOC*` requests and `MT*` operations, for `tar`'s
tape code; use them with `ioctl`.

## Times in struct stat

`struct stat` keeps the kernel layout but its three time pairs are now POSIX
`struct timespec` members `st_atim`, `st_mtim` and `st_ctim`. As in glibc,
`st_atime`, `st_mtime` and `st_ctime` are macros for the `tv_sec` members;
the earlier `st_atime_nsec` names remain as macros for `tv_nsec` (now
`long`). Code configured with `ST_MTIM_NSEC tv_nsec` (coreutils) works
unchanged; a program that uses `st_mtime` as its own identifier will see the
macro, exactly as under glibc.

## Device numbers

`sys/sysmacros.h` (also included by `sys/types.h`, as older glibc did) gives
`major`, `minor` and `makedev` with glibc's 64-bit `dev_t` encoding: the
major number in bits 8–19 and 32–63, the minor in bits 0–7 and 20–31.
`major`/`minor` are macros returning `unsigned int`; `makedev` calls the
small `__seed_makedev` so each argument is evaluated once. `mknod` passes
the value to the kernel, which accepts majors below 4096 and minors below
2^20 (the "new" 32-bit encoding is the same bits).

## Directory entries

`dirent.h` adds `DT_UNKNOWN`, `DT_FIFO`, `DT_CHR`, `DT_DIR`, `DT_BLK`,
`DT_REG`, `DT_LNK`, `DT_SOCK`, `DT_WHT`, `IFTODT` and `DTTOIF`, `dirfd` and
`rewinddir`; see [DIRECTORIES.md](DIRECTORIES.md).

## realpath

`realpath(path, resolved)` (`stdlib.h`) resolves without the kernel's help:
starting from `getcwd` for a relative name, it walks components, drops `.`,
removes one component for `..` (never above `/`), `lstat`s each new prefix,
and replaces a symbolic link by its target (absolute targets restart at
`/`; relative ones are read from the link's directory) followed by the
unread rest. Every component must exist (`ENOENT`), a component followed by
more path or a trailing slash must be a directory (`ENOTDIR`), more than 40
links fail with `ELOOP`, results or pending text beyond `PATH_MAX` fail with
`ENAMETOOLONG`, an empty name is `ENOENT` and NULL is `EINVAL`. The answer
has no `.`, `..`, repeated slashes or links. With `resolved == NULL` the
result is a `malloc`'d copy of the exact length; otherwise `resolved` must
hold `PATH_MAX` bytes. This replaces the canonicalize-style stand-in that
discovery builds used.

## Gate

`python3 tests/gcc/posix-files-check.py` runs a fixture in a fresh empty
directory, built by the Forth compiler and by host GCC/glibc (`-O0`, `-O2`),
and requires identical output: links and their errors, short `readlink`,
`creat` with a umask, `fchmod`, owner no-ops, both truncations, syncs,
`EISDIR`/`EINVAL` failures, `utimes`/`utime` round trips through
`st_atim`/`st_mtim` nanoseconds, FIFOs and `mknod`, unprivileged device and
`chroot` refusals, `makedev`/`major`/`minor` edge values and `/dev/null`,
sorted directory listings with `d_type`, `dirfd`, `rewinddir`, `fchdir`,
twenty `realpath` cases (dots, slashes, relative and absolute links, a link
loop, dangling links, `ENOTDIR` forms, the allocating form), `dup3`,
`pipe2` flags, `FIONREAD`, `ENOTTY`, `O_SYNC` opens and contended `flock`s
from a child. Absolute names are printed relative to the directory.
