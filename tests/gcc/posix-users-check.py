#!/usr/bin/env python3
"""POSIX user/group database gate: getpwent/setpwent/endpwent, getpwnam,
getpwuid, the group equivalents and getlogin over crafted /etc/passwd and
/etc/group files (comments, blank and malformed lines, duplicates, extra
colons, member lists); see runtime/gcc-seed/PASSWD.md. Each program runs in
a private user and mount namespace (unshare -rm) where the files from
tests/gcc/posix-users are bind-mounted over /etc, with NSS limited to
"files" for the glibc oracle. Forth production is compared with host glibc
-O0/-O2."""
from pathlib import Path
import shutil
import subprocess
from posix_runtime_harness import Gate, ROOT

DATA = ROOT / "tests/gcc/posix-users"
probe = subprocess.run(["unshare", "-rm", "true"], capture_output=True)
if probe.returncode != 0:
    print("SKIP: posix-users needs unprivileged user/mount namespaces (unshare -rm)")
    raise SystemExit(0)
gate = Gate("posix-users", "posix-users-check.c",
            ["passwd.c", "group.c", "dbfile.c", "getlogin.c", "setgroups.c"])
etc = gate.work / "etc"
etc.mkdir()
for name in ("passwd", "group", "nsswitch.conf"):
    shutil.copy(DATA / name, etc / name)
WRAPPER = ["unshare", "-rm", "sh", "-c",
           'for f in passwd group nsswitch.conf; do mount --bind "$0/$f" "/etc/$f" || exit 90; done; exec "$@"',
           str(etc)]
gate.build()
output = gate.compare(wrapper=WRAPPER)
if b"\ndone\n" not in output or b"getpwnam alice [alice]" not in output:
    raise SystemExit("fixture did not complete:\n" + output.decode(errors="replace")[-2000:])
gate.lint()
gate.finish(output.count(b"\n"), namespace="unshare -rm with bind-mounted passwd, group, nsswitch.conf")
