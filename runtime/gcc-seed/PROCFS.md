# Core-note records, gettimeofday and features.h

For a native `x86_64-*-linux*` build, original binutils 2.30 `bfd/configure.ac`
sets `CORE_HEADER="hosts/x86-64linux.h"`, and `bfd/elf.c` and
`bfd/elf64-x86-64.c` include it unconditionally. That unchanged header
includes `<features.h>`, `<sys/time.h>`, `<sys/types.h>` and `<sys/procfs.h>`,
then defines the 32-bit, x32 and 64-bit Linux core-note records in terms of
`struct elf_siginfo`, `pid_t` and `ELF_PRARGSZ`. Original libiberty
`mkstemps.c` calls `gettimeofday` for temporary-name entropy when configure
finds it. These are original seed-forth definitions; no libc or kernel header
text was copied.

## `<features.h>`

A marker header. Sources written for glibc include it first; this runtime has
no feature-test-macro machinery and is not glibc, so the header defines
nothing. In particular `__GLIBC__` stays undefined, so consumers do not take
glibc-specific paths.

## `<sys/time.h>` and `gettimeofday`

`struct timeval` (two signed `long` fields, 16 bytes) and `suseconds_t` are
unchanged from the [calendar layer](CALENDAR.md); `time_t` still comes from
`sys/types.h`, so every type has one definition. The header now also declares

    int gettimeofday(struct timeval *now, void *zone);

`timeofday.c` makes exactly one raw Linux AMD64 syscall 96 with both pointers
unchanged; there is no vDSO path and no retry. Success returns 0 and preserves
errno. A kernel result in -4095..-1 returns -1 with that errno; any other
result is success.

- `now` receives seconds and microseconds since the Epoch (CLOCK_REALTIME,
  the same clock as `time()`). The kernel also accepts NULL. glibc declares
  this parameter nonnull, so portable callers should not rely on that.
- `zone` may be NULL. When nonnull, Linux stores its two-`int` timezone
  record (minutes west of Greenwich, then the obsolete DST kind; normally
  both 0) unchanged. No `struct timezone` is declared; pass a pointer to two
  ints. The runtime never consults TZ for it. POSIX leaves a nonnull zone
  unspecified.
- An invalid pointer fails with EFAULT, as reported by the kernel. (glibc's
  vDSO path faults in user space instead.)

Interval timers, `settimeofday`, `select` and `struct timezone` are not
supplied.

## `<sys/procfs.h>`

Pure Linux x86-64 ELF core-note data definitions, no functions, laid out
exactly as the kernel writes `NT_PRSTATUS` and `NT_PRPSINFO`:

| Name | Definition |
|------|------------|
| `elf_greg_t` | `unsigned long long`, one saved register |
| `ELF_NGREG` | 27, a plain integer constant also usable in `#if` |
| `elf_gregset_t` | `elf_greg_t[27]`, 216 bytes |
| `struct elf_siginfo` | `si_signo`, `si_code`, `si_errno` ints; 12 bytes |
| `struct elf_prstatus` / `prstatus_t` | 336 bytes, alignment 8: `pr_info` 0, `pr_cursig` (short) 12, `pr_sigpend` 16, `pr_sighold` 24 (unsigned long), `pr_pid`/`pr_ppid`/`pr_pgrp`/`pr_sid` (pid_t) 32-44, four `struct timeval` times 48-111, `pr_reg` 112, `pr_fpvalid` 328 |
| `ELF_PRARGSZ` | 80 |
| `struct elf_prpsinfo` / `prpsinfo_t` | 136 bytes, alignment 8: four chars `pr_state`, `pr_sname`, `pr_zomb`, `pr_nice`; `pr_flag` (unsigned long) 8; `pr_uid`, `pr_gid` (unsigned int) 16, 20; `pr_pid`, `pr_ppid`, `pr_pgrp`, `pr_sid` (int) 24-36; `pr_fname[16]` 40; `pr_psargs[80]` 56 |

glibc computes `ELF_NGREG` from `sizeof(struct user_regs_struct)`; the value is
the same but this runtime has no `<sys/user.h>`. Not supplied, because no
consumer on the bfd path uses them: `elf_fpregset_t`/`prfpregset_t`,
`prgregset_t`, `psaddr_t`, `lwpid_t`, `struct user_regs_struct`, and the
Solaris-style `pstatus_t`, `psinfo_t` and `lwpstatus_t` records.

## bfd configure consistency

bfd's `AC_CHECK_HEADERS(sys/procfs.h)` and `BFD_HAVE_SYS_PROCFS_TYPE` probes
now give exactly the host glibc answers: `HAVE_SYS_PROCFS_H`,
`HAVE_PRSTATUS_T`, `HAVE_PRPSINFO_T` and `HAVE_PRPSINFO_T_PR_PID` are defined;
every `*32_t`, `pr_who`, `pstatus`, `psinfo`, `lwpstatus` and `win32_pstatus`
probe fails. `hosts/x86-64linux.h` then supplies `HAVE_PRSTATUS32_T`,
`HAVE_PRPSINFO32_T` and `HAVE_PRPSINFO32_T_PR_PID` itself, which is the
ordinary native x86-64 Linux configuration: `elf.c` reads and writes 336-byte
`prstatus_t` and 136-byte `prpsinfo_t` notes plus their 32-bit forms, and
takes the core LWP id from `pr_pid`. The earlier configuration, made while
the header was missing, has all of these undefined; `elf.c` and
`elf64-x86-64.c` then still preprocess cleanly and merely omit the generic
`elf.c` note readers (`elf64-x86-64.c` decodes notes by size itself). Rerun
configure rather than editing `config.h`.

With `gettimeofday` linkable, a fresh libiberty configure defines
`HAVE_GETTIMEOFDAY` and drops its `gettimeofday.c` replacement. Under a stale configuration the
replacement still compiles against the new compatible prototype.

## Verification

Run `python3 tests/gcc/procfs-time-check.py` (registered in
`tests/gcc/check.sh`). The Forth-built `procfs-layout.c` prints the size,
alignment and every member offset, size and signedness of the records above;
its output must equal, byte for byte, the same program built by host GCC with
glibc headers (`-std=gnu99 -U_FORTIFY_SOURCE`, `-O0` and `-O2`). Host GCC also
compiles it against the runtime headers alone, where pointer initializers
prove exact type identity. `timeofday-check.c` checks errno preservation,
microsecond range, agreement with `time()`, 2,000 non-decreasing readings,
NULL pointers, the zone record and EFAULT for both pointers against the host
oracle; the driver interleaves Forth and host readings inside Python
wall-clock brackets. A renamed fault copy of `timeofday.c` checks exact
forwarding and every Linux error encoding. Each header compiles standalone
and twice. The bfd configure probe bodies run under both compilers with equal
answers. The unchanged `hosts/x86-64linux.h` is compiled after the original
`ansidecl.h` and its record layouts, including the note sizes
`elf64-x86-64.c` matches (336, 296, 136, 124), must equal host GCC/glibc.
Unchanged libiberty `mkstemps.c` (with `HAVE_GETTIMEOFDAY`) and
`gettimeofday.c` compile; no link claim.
