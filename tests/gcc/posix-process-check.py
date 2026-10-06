#!/usr/bin/env python3
"""POSIX process gate: execl/execlp/execle, system (status, NULL, SIGINT
ignored and SIGCHLD blocked while waiting), popen/pclose in both directions
(including descriptor isolation between popen children and the "e" mode),
wait3/wait4 and the wait-status macros, exit/_Exit, and atexit/on_exit
handlers run in reverse order on exit and on return from main; see
runtime/gcc-seed/PROCESS-POSIX.md. Forth production is compared with host
glibc -O0/-O2; main's status 5 must survive the handlers."""
from posix_runtime_harness import Gate

gate = Gate("posix-process", "posix-process-check.c",
            ["process.c", "exec-list.c", "system.c", "popen.c", "process-api.c"])
gate.build()
output = gate.compare(status=5)
if not output.rstrip().endswith(b"atexit first (runs last)\n--stderr--"):
    raise SystemExit("exit handlers did not finish the run:\n" + output.decode(errors="replace")[-2000:])
gate.lint()
gate.finish(output.count(b"\n"))
