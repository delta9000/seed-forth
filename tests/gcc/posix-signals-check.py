#!/usr/bin/env python3
"""POSIX errno and signal gate: the complete Linux errno and signal number
sets, strerror/perror/strsignal/psignal text, signal sets, sigaction with
SA_SIGINFO/SA_NODEFER/SA_RESETHAND, masks, sigpending/sigsuspend, raise,
kill, killpg, alarm, pause and siginterrupt; see runtime/gcc-seed/ERRNO.md
and SIGNALS.md. Forth production is compared with host glibc -O0/-O2."""
from posix_runtime_harness import Gate

gate = Gate("posix-signals", "posix-signals-check.c",
            ["strerror.c", "sigaction.c", "sigset.c", "signal-send.c", "strsignal.c", "stdio.c"])
gate.build()
output = gate.compare()
if not output.startswith(b"EPERM 1\n") or b"\ndone\n" not in output:
    raise SystemExit("fixture did not complete:\n" + output.decode(errors="replace")[-2000:])
gate.lint()
gate.finish(output.count(b"\n"))
