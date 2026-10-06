# System information, limits, resources and clocks

Configure scripts and the plumbing tools ask the system about itself:
`uname`/`hostname` print names, `ls`/`du`/`pathchk` use `PATH_MAX`,
`NAME_MAX` and `pathconf`, `xargs`-like code and `bash` use `sysconf`, `nice`
uses priorities, `bash`'s `ulimit` and `times` use resource limits and
process times, and `sleep`/`tail -f` sleep with `nanosleep`.

## Constants

`limits.h` adds the Linux/glibc values `PATH_MAX` 4096, `NAME_MAX` 255,
`PIPE_BUF` 4096, `NGROUPS_MAX` 65536, `LINE_MAX` 2048, `RE_DUP_MAX` 32767,
`HOST_NAME_MAX` 64, `LOGIN_NAME_MAX` 256, `TTY_NAME_MAX` 32, `IOV_MAX` 1024,
the `BC_*`, `COLL_WEIGHTS_MAX`, `EXPR_NEST_MAX` and `CHARCLASS_NAME_MAX`
utility limits, and the `_POSIX_*`/`_POSIX2_*` minimums. Limits that vary at
run time (`ARG_MAX`, `OPEN_MAX`, `CHILD_MAX`) are deliberately absent, as in
glibc; ask `sysconf`.

`unistd.h` defines `_POSIX_VERSION` and `_POSIX2_VERSION` as 200809L (the
values glibc reports), `_POSIX_JOB_CONTROL`, `_POSIX_SAVED_IDS`,
`_POSIX_NO_TRUNC`, `_POSIX_CHOWN_RESTRICTED` (0) and `_POSIX_VDISABLE`
(`'\0'`). `_POSIX2_VERSION` matters: coreutils 5.0 selects its POSIX 1003.1-2001
option syntax (rejecting obsolete `head -1`) from it, exactly as with glibc.

## sysconf

Only the `_SC_*` names `unistd.h` defines exist (glibc's numbers); any other
name fails with `EINVAL`. Answers follow Linux glibc:

- `_SC_ARG_MAX`: a quarter of the stack soft limit, at least 131072;
- `_SC_CHILD_MAX`, `_SC_OPEN_MAX`: `RLIMIT_NPROC` and `RLIMIT_NOFILE` soft
  limits (an infinite process limit answers -1 with errno unchanged);
- `_SC_CLK_TCK` 100, `_SC_PAGESIZE` 4096, `_SC_NGROUPS_MAX` 65536,
  `_SC_STREAM_MAX` 16, `_SC_VERSION`/`_SC_2_VERSION` 200809, `_SC_JOB_CONTROL`
  and `_SC_SAVED_IDS` 1, `_SC_RTSIG_MAX` 32, the utility limits above,
  `_SC_GETPW_R_SIZE_MAX`/`_SC_GETGR_R_SIZE_MAX` 1024;
- `_SC_TZNAME_MAX` and `_SC_SYMLOOP_MAX`: -1 (no fixed limit), errno unchanged;
- `_SC_NPROCESSORS_CONF`/`_ONLN`: CPUs listed in
  `/sys/devices/system/cpu/possible` and `online`, falling back to the
  `sched_getaffinity` mask;
- `_SC_PHYS_PAGES`/`_SC_AVPHYS_PAGES`: `sysinfo` total and free RAM in pages.

`getpagesize` is 4096 and `getdtablesize` the `RLIMIT_NOFILE` soft limit.

## pathconf and fpathconf

`_PC_MAX_CANON`/`_PC_MAX_INPUT` 255, `_PC_PATH_MAX`/`_PC_PIPE_BUF` 4096,
`_PC_CHOWN_RESTRICTED` and `_PC_NO_TRUNC` 1, `_PC_VDISABLE` 0,
`_PC_SYMLINK_MAX` -1 and `_PC_2_SYMLINKS` 1 are constant answers.
`_PC_NAME_MAX` is the file system's `statfs` name length. `_PC_LINK_MAX`
and `_PC_FILESIZEBITS` come from the `statfs` type, using glibc's table for
the file systems where they differ (ext4 65000 and ext2/ext3 32000 links,
told apart by the mount's type in `/proc/self/mountinfo`; XFS, btrfs,
ReiserFS, UFS and Minix values; 127 links and 32 bits elsewhere, including
tmpfs and procfs). `statfs`/`fstatfs` errors (`ENOENT`, `EBADF`) are
returned; unknown names fail with `EINVAL`. The path is only stat'ed, never
opened.

## Names

`uname` fills the kernel's six 65-byte `new_utsname` fields (with
`domainname`). `gethostname` copies the node name and, like glibc, fails
with `ENAMETOOLONG` when it and its NUL do not fit (the bytes that fit are
copied).

## Resources, priority and process times

`sys/resource.h` gives the Linux `RLIMIT_*` numbers, `RLIM_INFINITY`
(all ones), `struct rlimit`, the kernel's 144-byte `struct rusage`,
`RUSAGE_SELF`/`RUSAGE_CHILDREN` and `PRIO_*`. `getrlimit` (97),
`setrlimit` (160) and `getrusage` (98) are single calls. `getpriority`
converts the kernel's `20 - nice` result back to a nice value (so -1 can be
a valid answer: clear errno first) and `setpriority` (141) passes it through.
`nice(increment)` behaves as glibc: it adds to the current value, returns
the new value, and reports a refused decrease as `EPERM`.

`sys/times.h` provides `struct tms` and `times` (100) in ticks of
`sysconf(_SC_CLK_TCK)`. `clock_t` is shared with `time.h`.

## Clocks and sleeping

`time.h` gains `struct timespec` (also used by `sys/stat.h`; it lives in the
private `seed-timespec.h`), `clockid_t`, `CLOCK_REALTIME`,
`CLOCK_MONOTONIC`, `CLOCK_PROCESS_CPUTIME_ID`, `CLOCK_THREAD_CPUTIME_ID`,
`clock_gettime` (228), `clock_getres` (229) and `nanosleep` (35): one call,
returning `EINTR` with the remaining time when interrupted and `EINVAL` for a
nanosecond field outside 0–999999999. `usleep` is a `nanosleep` of the
requested microseconds. `sys/time.h` gains `struct timezone` and
`settimeofday` (164, `EPERM` without `CAP_SYS_TIME`). Calendar conversion
and time zones are outside this document ([CALENDAR.md](CALENDAR.md)).

## Gate

`python3 tests/gcc/posix-sysinfo-check.py` builds one fixture with the Forth
compiler and with host GCC/glibc (`-O0`, `-O2`) and requires identical
output from identity calls ([IDENTITY.md](IDENTITY.md)), `uname` fields and
`gethostname` (including the one-byte failure), every constant above, every
`sysconf` name, all twelve `pathconf`/`fpathconf` names on `.` (ext4 in the
build tree), `/`, `/proc`, `/dev` and `/tmp`, missing paths, bad names and
descriptors, all sixteen resource limits, lowering `RLIMIT_NOFILE` and its
`sysconf`/`getdtablesize` view, `getrusage`, `times`, priorities and `nice`
(including the unprivileged refusal), clocks, `nanosleep` and `usleep`
timing, invalid clocks and requests, and `settimeofday` refusal.
