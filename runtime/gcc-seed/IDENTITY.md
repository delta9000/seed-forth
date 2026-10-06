# User, group, process-group and session identity

`id`, `whoami`, `install`, `chown`, `tar` (preserving owners), `make` and
`bash` (job control) need the identity calls; discovery builds supplied them
as scratch stand-ins, some returning `int` where POSIX has `uid_t`.

`identity.c` makes one Linux AMD64 syscall per function:

| Function | Syscall | Notes |
|---|---|---|
| `getuid`, `getgid`, `geteuid`, `getegid` | 102, 104, 107, 108 | cannot fail; errno untouched |
| `getppid`, `getpgrp` | 110, 111 | cannot fail |
| `getpgid`, `getsid` | 121, 124 | `ESRCH` for an unknown process |
| `setpgid`, `setsid` | 109, 112 | kernel `EPERM`/`EACCES`/`ESRCH` |
| `setuid`, `setgid`, `setreuid`, `setregid` | 105, 106, 113, 114 | `(uid_t)-1` = unchanged where allowed |
| `seteuid`, `setegid` | 117, 119 | as glibc: `setresuid(-1, id, -1)`; `-1` fails `EINVAL` |
| `getgroups` | 115 | `size` 0 returns the count; too small fails `EINVAL` |
| `setgroups` (`grp.h`, `setgroups.c`) | 116 | needs `CAP_SETGID` |

IDs are unsigned 32-bit values exactly as the kernel takes them. There is no
thread machinery, so unlike glibc no cross-thread credential broadcast is
needed. `getlogin` and the password/group databases are in
[PASSWD.md](PASSWD.md); `nice`, `getpriority` and resource limits are in
[SYSINFO.md](SYSINFO.md).

The gate is `python3 tests/gcc/posix-sysinfo-check.py` (see SYSINFO.md): it
prints the IDs and supplementary groups, checks `getpgrp() == getpgid(0)`,
`getsid`, every same-ID `set*` call, `seteuid(-1)`, `setuid(0)` and
`setgroups` refusals for an unprivileged user, and a child's `setsid` (new
session leader, second call `EPERM`) and `setpgid(0, 0)`. Output must equal
host glibc's at `-O0` and `-O2`.
