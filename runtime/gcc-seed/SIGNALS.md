# POSIX signals: numbers, sets, sigaction and delivery

The plumbing tools need far more than the persistent `signal()` handlers of
[SIGNAL.md](SIGNAL.md): `make` and `bash` block `SIGCHLD` around job control
with `sigprocmask` and wait with `sigsuspend`; `sort`, `tail` and `tee` name
`SIGPIPE`, `SIGQUIT` and `SIGALRM`; `kill` and `bash` print signal names;
`system` and `popen` must ignore and block signals around a child.

## Numbers and records

`signal.h` defines all Linux AMD64 numbers 1–31 (with `SIGIOT`, `SIGCLD`
and `SIGPOLL` aliases), `NSIG` 65 and, as glibc reports them, `SIGRTMIN` 34
and `SIGRTMAX` 64. Here they are constants: the runtime has no threads that
need glibc's reserved 32 and 33, but keeping glibc's range makes
`strsignal` and real-time numbering agree with host programs.

`sigset_t` has glibc's 128-byte size; only its first 64-bit word (signals
1–64) is passed to the kernel. `siginfo_t` has the kernel's 128-byte layout,
with `si_signo`, `si_errno`, `si_code`, and the variant fields `si_pid`,
`si_uid`, `si_status`, `si_value`, `si_utime`, `si_stime`, `si_addr`,
`si_band` and `si_fd` as macros into a union, as in glibc. `struct
sigaction` has glibc's 152-byte layout (`sa_handler`/`sa_sigaction` share a
union). The `SA_*`, `SIG_BLOCK`/`SIG_UNBLOCK`/`SIG_SETMASK`, `SI_*` and
`CLD_*` constants have their Linux values.

## Calls

All are single raw syscalls; kernel errors become errno and -1.

- `sigaction` (rt_sigaction, 13) always sets `SA_RESTORER` and the runtime's
  `__seed_sigreturn` trampoline (the caller's `sa_restorer` is ignored), and
  passes the first mask word. The previous action is returned with the
  kernel's flags (including `SA_RESTORER`, as glibc reports it) and a
  zero-extended mask. Numbers outside 1–64 fail `EINVAL` before the call;
  the kernel rejects `SIGKILL`/`SIGSTOP` handlers.
- `sigprocmask` (14), `sigpending` (127) and `sigsuspend` (130) with an
  eight-byte set. `sigsuspend` returns -1/`EINTR` after a handler runs.
- `sigemptyset`, `sigfillset`, `sigaddset`, `sigdelset`, `sigismember` work
  on 1–64; other numbers fail `EINVAL`. Unlike glibc, 32 and 33 are ordinary
  members (glibc refuses them for its thread library).
- `siginterrupt(sig, flag)` reads the disposition and clears (`flag` nonzero)
  or sets `SA_RESTART`.
- `raise` is `tgkill(getpid(), gettid(), sig)`, so an unblocked signal's
  handler has run before it returns (`si_code` is `SI_TKILL`, as glibc).
- `killpg(group, sig)` is `kill(-group, sig)`; like glibc only a negative
  group fails `EINVAL` (0 means the caller's own group).
- `alarm` (37) cannot fail; `pause` (34) returns -1/`EINTR`.

## Text

`strsignal` returns glibc's C-locale descriptions ("Hangup" …
"Bad system call"), `Real-time signal N` for 34–64 (N counted from
`SIGRTMIN`) and `Unknown signal N` otherwise; numbered texts share one
static buffer. `psignal(sig, prefix)` writes `prefix: text` (or just the
text) to stderr and, exactly like glibc, prints `Unknown signal N` for every
number without a name, including the real-time ones. `sys_siglist[NSIG]`
holds the named descriptions with NULL elsewhere; glibc 2.32 removed it from
its headers, but older tools (bash 2.05b) still use it when present.

## Gate

`python3 tests/gcc/posix-signals-check.py` runs one fixture built by the
Forth compiler and by host GCC/glibc (`-O0`, `-O2`) and requires identical
output: every number and flag value, `strsignal`/`psignal` from -1 to 66,
set operations including invalid numbers, `sigaction` old/new values and
masks, `SA_NODEFER`, `SA_RESETHAND`, `SIG_IGN`, `SA_SIGINFO` records from
`raise`, `kill` and a real `SIGCHLD` (`CLD_EXITED`, status 7), blocking
with `sigpending` and `sigsuspend`, `alarm`/`pause`, a read interrupted
after `siginterrupt`, `killpg` in a child's own process group, and a child
killed by its own `raise(SIGTERM)`. Runtime-only checks (`sys_siglist`,
members 32/33) run under `#ifndef __GLIBC__`.
