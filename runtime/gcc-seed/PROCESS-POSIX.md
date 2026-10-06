# exec lists, system, popen and process termination

`gawk` and `diff`/`sdiff` run commands through `system` and `popen`, `tar`
runs `gzip` with `execlp`, `make` and `bash` use `execle`/`execl`, and
coreutils programs register `close_stdout` with `atexit` and return from
`main`. These build on the [process API](PROCESS-API.md).

## exec with an argument list

`execl`, `execlp` and `execle` (`exec-list.c`) collect the NULL-terminated
variadic list into a vector of at most 4096 entries (4095 arguments plus the
NULL; a longer list fails with `E2BIG` before any exec) and call `execve`
with `environ`, `execvp`, or `execve` with the environment pointer that
follows the terminating NULL. Their failures are those of the call made.

## The shell

`paths.h` defines `_PATH_BSHELL` as `"/bin/sh"`: the single place the shell
path lives. `system` and `popen` run `sh -c COMMAND` from it with the current
`environ`. When the seed-built bash is installed as `/bin/sh` later, nothing
else changes.

## system

`system(NULL)` returns nonzero when `_PATH_BSHELL` is executable. Otherwise,
as POSIX requires, the caller ignores `SIGINT` and `SIGQUIT` and blocks
`SIGCHLD`, forks, and the child restores the original dispositions and mask
before `execve`; a failed exec exits 127. The parent waits for that child
(retrying `EINTR`), restores its dispositions and mask, and returns the wait
status (-1 if `fork` or `waitpid` fails), preserving errno across the
restoration.

## popen and pclose

`popen(command, mode)` accepts `"r"` or `"w"`, optionally followed by
`"e"` (glibc's close-on-exec request); any other mode fails `EINVAL`. It
creates the pipe with `pipe2(O_CLOEXEC)`, forks, and in the child closes the
descriptors of every stream still open from earlier `popen` calls (as POSIX
requires), moves its end onto descriptor 0 or 1 (clearing close-on-exec if
it is already there) and execs the shell. The parent keeps its end
close-on-exec only for `"e"`, wraps it with `fdopen`, and records
stream, descriptor and child in a list. `pclose` removes the record, closes
the stream, waits for exactly that child (retrying `EINTR`) and returns its
status; a stream `popen` did not create gives -1 with `ECHILD`.

## exit, _Exit, atexit and on_exit

`process.c` keeps a table of 64 exit handlers (POSIX requires at least 32)
shared by `atexit(fn)` and glibc's `on_exit(fn, argument)`; registering
NULL or into a full table returns -1. `exit(status)` pops handlers newest
first — each record is removed before it runs, so a handler that registers
another runs that one next and a handler that calls `exit` continues the
same sequence — then calls `__seed_exit_flush` if it is set (a hook for a
buffered stdio to flush every stream; today's streams are unbuffered and
leave it NULL), and ends the process with Linux `exit` (60), keeping only
the low status byte. `_Exit` makes that final call immediately, with no
handlers or flushing; `abort`'s last-resort fallback now uses it too.
`process.c` still references nothing but the syscall bridge.

Returning from `main` is `exit` of its result: the runtime-aware `_start`
([chapter 38](../../book/38-direct-gcc-runtime.md)) now calls the C `exit`
instead of making the system call itself. The raw entry used for minimal
syscall proofs is unchanged.

## wait3 and wait4

`sys/wait.h` adds `wait4` (61 with a `struct rusage` pointer) and
`wait3(status, options, usage)` = `wait4(-1, …)`, `WCONTINUED`, `WNOWAIT`,
`WCOREDUMP` (bit 7, as glibc) and `WIFCONTINUED` (status 0xffff).

## Gate

`python3 tests/gcc/posix-process-check.py` builds the fixture with the
Forth compiler and with host GCC/glibc (`-O0`, `-O2`) and requires identical
output and exit status 5: `execl` with `$0`/`$#`, `execlp` through `PATH`,
`execle` with a replacement environment, exec failures, `system` exit,
signal death, 127, `NULL`, a `SIGINT` sent by the command to its parent while
ignored, restored handler and mask, `popen` in both directions, exit status
through `pclose`, the descriptor list of a second `popen` child (no inherited
first stream), `"e"`, invalid modes, `wait4`/`wait3` with `WNOHANG` and
`ECHILD`, the new status macros, `exit` running a handler in a child,
`_Exit` skipping it, 32 registrations, and finally `atexit`/`on_exit`
handlers printing in reverse order after `main` returns 5.
