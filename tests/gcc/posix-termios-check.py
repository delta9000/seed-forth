#!/usr/bin/env python3
"""POSIX terminal gate: termios constants, tcgetattr/tcsetattr (all three
actions), cfmakeraw, cf*speed, window size ioctls, ttyname/ttyname_r,
tcgetpgrp/tcsetpgrp/tcgetsid, tcflush/tcdrain/tcflow/tcsendbreak and the
ENOTTY/EBADF failures; see runtime/gcc-seed/TERMIOS.md. Each program gets a
fresh pseudo-terminal (33x101) as standard input and controlling terminal
of a new session. Forth production is compared with host glibc -O0/-O2."""
import fcntl
import os
import pty
import struct
import subprocess
import termios
from posix_runtime_harness import Gate, ENVIRONMENT, limits

gate = Gate("posix-termios", "posix-termios-check.c", ["termios.c", "ttyname.c", "ioctl.c"])
gate.build()
outputs = {}
for name, program in gate.programs.items():
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 33, 101, 0, 0))

    def controlling():
        limits()
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)

    result = subprocess.run([str(program)], stdin=slave, capture_output=True, timeout=60,
                            preexec_fn=controlling, env=ENVIRONMENT, cwd=gate.directory(name))
    attributes = termios.tcgetattr(master)
    os.close(slave)
    os.close(master)
    if result.returncode != 0:
        raise SystemExit(f"{name}: exit {result.returncode}\n" + result.stderr.decode(errors="replace"))
    outputs[name] = result.stdout + b"--stderr--\n" + result.stderr
actual = outputs["forth"]
for name, expected in outputs.items():
    if expected != actual:
        for number, (a, e) in enumerate(zip(actual.splitlines(), expected.splitlines()), 1):
            if a != e:
                raise SystemExit(f"posix-termios: line {number}: forth {a!r} != {name} {e!r}")
        raise SystemExit("posix-termios: output lengths differ")
if b"\ndone\n" not in actual or b"window 33 101 0 0\n" not in actual:
    raise SystemExit("fixture did not complete:\n" + actual.decode(errors="replace")[-2000:])
gate.lint()
gate.finish(actual.count(b"\n"), terminal="fresh pty per program, 33x101, controlling terminal")
