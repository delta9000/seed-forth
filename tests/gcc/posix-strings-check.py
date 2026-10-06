#!/usr/bin/env python3
"""POSIX strings/numbers/environment gate: strings.h, strnlen/strndup/
stpcpy/stpncpy/strtok/strtok_r/strcoll/strxfrm, strtoll/strtoull/atoll/
strtoimax/strtoumax, labs/llabs/div/ldiv/lldiv, rand/srand/random/srandom
(glibc's sequences), isblank, setenv/unsetenv (seen by a child via system),
localeconv, the restartable C-locale multibyte calls and getline/getdelim;
see runtime/gcc-seed/STRINGS-POSIX.md, ENVIRONMENT.md and WIDE.md. Forth
production is compared with host glibc -O0/-O2."""
from posix_runtime_harness import Gate

gate = Gate("posix-strings", "posix-strings-check.c",
            ["strcasecmp.c", "strncasecmp.c", "bsd-string.c", "strndup.c", "strnlen.c", "stpcpy.c",
             "stpncpy.c", "strtok.c", "strcoll.c", "isblank.c", "strtoll.c", "strtoull.c", "atoll.c",
             "strtoimax.c", "strtoumax.c", "labs.c", "rand.c", "setenv.c", "getline.c", "localeconv.c",
             "mbstate.c", "environment.c"])
gate.build()
output = gate.compare(stdin=b"")
if b"\ndone\n" not in output:
    raise SystemExit("fixture did not complete:\n" + output.decode(errors="replace")[-2000:])
gate.lint()
gate.finish(output.count(b"\n"))
