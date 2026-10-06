# Process creation, replacement and waiting

Original binutils 2.30 `libiberty/pex-unix.c` runs every subprocess for
the `pex_*` interface, which GCC's driver and collect2 also use to run cc1,
as and ld. Under a glibc-like configuration (`HAVE_SYS_WAIT_H`,
`HAVE_WAITPID`, working fork/vfork) it calls `vfork`, `dup2`, `close`,
`execv`, `execvp`, `_exit`, `write`, `waitpid`, `kill`, `pipe`, `sleep`,
`fcntl` and `fdopen`, assigns `environ` in the child, and uses `<sys/wait.h>`
and `SIGTERM`. `xstrerror.c` and `make-temp-file.c` call `strerror`.

`process-api.c` and `strerror.c` supply the missing calls; declarations live
in `unistd.h`, `sys/wait.h`, `signal.h` (`kill`) and `string.h` (`strerror`).
`errno.h` adds `ESRCH`, `ENOEXEC`, `ECHILD`, `ENODEV`, `ETIMEDOUT` and
`ESTALE` with their Linux values.

## Single calls

`pipe`, `dup2`, `fork`, `execve`, `waitpid` and `kill` each make one AMD64
syscall (22, 33, 57, 59, 61 with a null rusage, 62) through `__seed_syscall6`.
Raw values in `[-4095, -1]` become errno and `-1`; nothing is retried, and
the kernel validates descriptors, process IDs, signals and options. `wait`
is `waitpid(-1, status, 0)`. Like glibc, `fork` does not flush stdio: a program
with pending buffered output calls `fflush` first ([STDIO-BUFFERING.md](STDIO-BUFFERING.md)). A successful `execve` does not return.
`environ` is the existing runtime global set at startup (it is NULL under the
raw entry, which Linux accepts as an empty environment). See
[fork](https://man7.org/linux/man-pages/man2/fork.2.html),
[execve](https://man7.org/linux/man-pages/man2/execve.2.html) and
[wait4](https://man7.org/linux/man-pages/man2/wait4.2.html).

## vfork is fork

A real vfork child runs on the parent's stack until it execs or exits. This
compiler gives no guarantee that the child leaves the parent's frame intact:
returning from the `vfork` wrapper itself, or any call the child makes,
overwrites stack the suspended parent will resume on. POSIX allows `vfork`
to be an ordinary fork, so the runtime does exactly that. The child gets
private memory and the parent runs concurrently. pex-unix restores `environ`
and descriptors in the parent, which is correct under either behavior.

## exec with the current environment and PATH search

`execv(path, argv)` is `execve(path, argv, environ)`, reading `environ` at
call time, so a child can assign it first, as pex-unix does. `execvp`:

- an empty name fails with `ENOENT`; a name containing `/` is passed to
  `execv` without searching;
- otherwise it tries each `PATH` element from `getenv("PATH")` in order, or
  `/bin:/usr/bin` when `PATH` is unset; an empty element is the current
  directory, and a candidate longer than 4095 bytes is skipped with
  `ENAMETOOLONG`;
- `ENOENT`, `ENOTDIR`, `ESTALE`, `ENODEV` and `ETIMEDOUT` continue the search;
  `EACCES` continues but is remembered; any other error is returned at once;
- when the search is exhausted, errno is `EACCES` if any candidate gave it,
  else the last error.

A file that the kernel rejects with `ENOEXEC` (no `#!` line, not ELF) is
not retried with `/bin/sh` as POSIX describes: `execvp` returns `ENOEXEC`.
Compiler drivers run real executables; add the fallback with a consumer.

## Status words and sleep

`sys/wait.h` defines `WNOHANG` 1, `WUNTRACED` 2 and the Linux status
encoding: normal exit is `code << 8`, a signal death keeps the signal in bits
0–6 (bit 7 is the core flag), and a stop is `signal << 8 | 0x7f`. The
`WIFEXITED`, `WEXITSTATUS`, `WIFSIGNALED`, `WTERMSIG`, `WIFSTOPPED` and
`WSTOPSIG` macros evaluate their argument once. `WCONTINUED`, `WCOREDUMP`,
`WIFCONTINUED`, `wait3` and `wait4` are now in
[PROCESS-POSIX.md](PROCESS-POSIX.md), with `execl`/`execlp`/`execle`,
`system`, `popen` and the exit handlers.

`sleep` calls `nanosleep` (syscall 35) once. It returns 0 and preserves errno
on completion. After a signal interrupts it (`EINTR`), it returns the unslept
seconds, rounding a remaining partial second up so an interrupted sleep never
reports 0; it does not resume. Any other failure returns the full request.

## strerror

`strerror` returns fixed glibc C-locale text for 0 and every errno value
`errno.h` defines, and `Unknown error N` (in one static buffer, overwritten
by the next unknown lookup) otherwise. It preserves errno. `errno.h` now
holds every Linux error number and `perror` uses `strerror`; see
[ERRNO.md](ERRNO.md).

## Focused gate

Run `python3 tests/gcc/process-api-check.py`; it is registered in
`tests/gcc/check.sh`. Processes run serially under a one-GiB limit. The
Forth-built program forks and execs `/bin/sh` and a Forth-built child, moves
data through pipes both ways, uses `dup2` for stdin/stdout redirection and
file output, and checks exit and signal statuses, `execve`/`execv`
environments, `execvp` search success, skipped and final `EACCES`, `ENOENT`
and the default path, vfork, `WNOHANG`, `WUNTRACED` stops, `kill` with
`SIGKILL`/`ESRCH`/`EINVAL`, `ECHILD`, and `sleep` interrupted by `SIGUSR1`.
The same program built by host GCC with glibc at `-O0`/`-O2` is the oracle.
The W* macros are evaluated for every 16-bit status word and wider values,
and `strerror` for every defined value and some unknown ones. That output must
match host glibc byte for byte. Host GCC also lints the runtime sources
against the runtime headers alone.

When the pinned binutils source is present, the gate compiles unchanged
libiberty `pex-unix.c`, `pex-common.c`, `xmalloc.c`, `xstrerror.c`,
`make-temp-file.c`, `concat.c`, `xexit.c`, `xstrdup.c` and `mkstemps.c` with
the Forth driver and a hand-written glibc-like `config.h` (no `wait4`,
`getrusage`, `gettimeofday`, `dup3` or spawn). Host GCC lint with
`-Werror=implicit-function-declaration` over the runtime headers checks every
unit. A Forth-linked `tests/gcc/pex-check.c` then uses the public API: a
`printf | tr` PATH-searched pipeline read with `pex_read_output`, a `PEX_LAST`
output file with exit status 3, a signal death, an absolute-path Forth child,
and a missing program reported by the child on stderr with status 255.
A host GCC/glibc build of the same units must behave identically.
