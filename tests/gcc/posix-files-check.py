#!/usr/bin/env python3
"""POSIX file-call gate: symlink/readlink/link, f*/l* ownership and mode
calls, (f)truncate, fsync, creat, mknod/mkfifo, utimes and struct timespec
stat times, major/minor/makedev, d_type/dirfd/rewinddir, realpath (symbolic
links, loops, "..", trailing slashes, errors), dup3/pipe2, ioctl and flock;
see runtime/gcc-seed/FILE-CALLS.md. Each build runs in its own empty
directory; Forth production is compared with host glibc -O0/-O2."""
from posix_runtime_harness import Gate

gate = Gate("posix-files", "posix-files-check.c",
            ["file-calls.c", "ftruncate.c", "mkfifo.c", "creat.c", "flock.c", "dup3.c", "utimes.c",
             "makedev.c", "ioctl.c", "dirent.c", "dirfd.c", "realpath.c", "descriptor-io.c"])
gate.build()
output = gate.compare()
if b"\ndone\n" not in output:
    raise SystemExit("fixture did not complete:\n" + output.decode(errors="replace")[-2000:])
gate.lint()
gate.finish(output.count(b"\n"))
