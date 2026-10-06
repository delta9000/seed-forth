#!/usr/bin/env python3
"""POSIX identity and system-information gate: user/group/session IDs,
uname/gethostname, limits.h and unistd.h constants, sysconf, pathconf and
fpathconf on several file systems, resource limits and usage, priority,
times, clocks and sleeping; see runtime/gcc-seed/IDENTITY.md and SYSINFO.md.
Forth production is compared with host glibc -O0/-O2."""
from posix_runtime_harness import Gate

gate = Gate("posix-sysinfo", "posix-sysinfo-check.c",
            ["identity.c", "setgroups.c", "resource.c", "sysconf.c", "utsname.c", "clock-sleep.c"])
gate.build()
output = gate.compare()
if b"\ndone\n" not in output:
    raise SystemExit("fixture did not complete:\n" + output.decode(errors="replace")[-2000:])
gate.lint()
gate.finish(output.count(b"\n"))
