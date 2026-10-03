# Source-built signal handlers

Original oyacc 6.6 `main.c` installs handlers for SIGINT, SIGTERM and SIGHUP,
preserving an inherited ignored disposition. This requires real disposition
changes and a real handler-return path, even though oyacc's particular handler
normally terminates. `signal.c`, `signal.h`, and the Forth restorer builder
provide that bounded Linux AMD64 interface.

## Contract and ABI

`signal(number, handler)` returns the preceding handler, SIG_DFL, or SIG_IGN.
Failure returns SIG_ERR and sets errno to the kernel error; numbers outside
1..64 fail with EINVAL before a syscall. SIGKILL and SIGSTOP cannot be changed
and the real kernel rejects them. A successful installation preserves errno.
SIG_DFL is the null handler representation; SIG_IGN is one; SIG_ERR is minus
one. A callable handler must have the `void (int)` ABI. The header's
`sig_atomic_t` is a signed 32-bit int on this fixed target.

The implementation chooses persistent BSD-style semantics: no reset on
handler entry, delivery of the same signal is blocked during its handler,
and eligible interrupted system calls are restarted. It installs an empty
additional mask and the SA_RESTART flag. It does not promise threads,
real-time signal queue APIs, signal-set APIs, alternate stacks, siginfo
handlers, or a complete POSIX signal library. The remaining runtime is not
made asynchronously reentrant by adding this interface.

The internal kernel action is 32 bytes: handler at byte 0, 64-bit flags at
byte 8, restorer pointer at byte 16, and an eight-byte signal mask at byte 24.
The rt_sigaction call is syscall 13 with mask size 8. These are kernel ABI
facts, not a copied host-libc struct layout. The kernel's own handler entry
blocks the delivered signal; rt_sigreturn restores the previous mask and
interrupted machine context.

AMD64 additionally requires SA_RESTORER. The Forth builder emits a real code
section exporting `__seed_sigreturn`: `mov eax,15; syscall; ud2`. It adds no
stack frame and does not alter RSP before syscall 15. The trailing trap
prevents execution from continuing if the normally nonreturning syscall
unexpectedly returns. The C driver includes this Forth-built object in its
hashed runtime set. No host assembler or host-generated trampoline is used.

These ABI choices are grounded in the Linux v6.12
[x86 signal declarations](https://github.com/torvalds/linux/blob/v6.12/arch/x86/include/uapi/asm/signal.h),
[generic flag definitions](https://github.com/torvalds/linux/blob/v6.12/include/uapi/asm-generic/signal-defs.h),
[AMD64 syscall table](https://github.com/torvalds/linux/blob/v6.12/arch/x86/entry/syscalls/syscall_64.tbl),
and [frame setup/return implementation](https://github.com/torvalds/linux/blob/v6.12/arch/x86/kernel/signal_64.c).
The Linux man-pages [signal semantics](https://man7.org/linux/man-pages/man2/signal.2.html)
explain the chosen persistent BSD behavior and its portability limits.

## Verification boundary

`python3 tests/gcc/signal-check.py` builds the runtime, test executable and
restorer with Forth, then uses actual Linux delivery. It checks old-handler
returns, SIG_IGN, SIG_DFL termination, invalid numbers, uncatchable signals,
the returned kernel action's layout/flags/mask/restorer, repeated handler
return, blocked pending delivery, nonrecursive self-delivery, and restoration
of the pre-handler signal mask.

The blocking-read check observes the test child actually waiting in read
through its own `/proc/PID/syscall`, delivers SIGUSR1, waits for the handler's
raw-write marker and the resumed read, then supplies the data byte. It therefore
checks a genuinely interrupted blocking syscall rather than only the flag
value. The Python runner targets only its own temporary child processes and
uses timeouts. Each run retains its sources, executable hashes and report in
a new directory. When available, independently built host C90/header/libc
versions at O0 and O2 exercise the same public behavior as separate oracles.
The host may explicitly include the delivered signal in its additional mask;
this runtime leaves that mask empty and relies on kernel blocking. Both
variants must pass the same deferred-delivery and mask-restoration checks.
Those host programs never supply a production input.
