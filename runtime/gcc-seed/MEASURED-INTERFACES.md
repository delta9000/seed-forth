# Four measured original-GCC runtime interfaces

The preliminary historical a535 inventory contains 206 successful cc1 objects,
not a complete cohort. `prefix.o` references `access`, `toplev.o` references
`getpid`, `rtlanal.o` and `builtins.o` reference `strpbrk`, and `builtins.o`
references `strspn`. None is defined by the 38 historical runtime objects;
the pinned original libiberty tree has no fallback file for these names.

The unchanged GCC 4.0.4 source at commit
`944765863eec87a9f37e297994fd2af960397138` calls them at:

- `gcc/prefix.c:290`: real-directory execute/search permission
- `gcc/toplev.c:505`: mix the process ID into a random seed
- `gcc/rtlanal.c:4795`: find the first e/E/V RTL format character
- `gcc/builtins.c:8773,8927`: constant string builtin evaluation

## Machine and syscall contracts

`unistd.h` declares `int access(const char *, int)` and `pid_t getpid(void)`.
The existing Linux AMD64 `pid_t` is signed four-byte int. Mode constants are
F_OK=0, X_OK=1, W_OK=2, R_OK=4. Local Linux UAPI `asm/unistd_64.h` identifies
access=21 and getpid=39; the host headers independently confirm the public
types and constants. This is the AMD64 table, not asm-generic's other-ABI
numbers. Tests retain those local header hashes and execute an ABI probe.

`access` makes exactly one raw Linux syscall. The kernel validates all mode
bits and the pathname, follows symlinks, checks real user/group IDs, applies
its privileged-user rules, and reports pathname/permission errors. The wrapper
does not read the pathname, alter credentials, open a descriptor or write to
caller memory. Results -4095 through -1 become -1 with positive errno. Success
preserves errno. A permission check can race with later file operations and
must not be treated as a guarantee that a subsequent open will succeed.

`getpid` makes the Linux syscall on every call and returns its pid_t result.
Linux defines no getpid error return; it does not set errno. It is not cached,
so the wrapper cannot retain a parent's PID across a process change. Process
creation itself is not introduced by this stage. Runtime errno remains the
existing single-threaded storage; no thread-local libc ABI is claimed.

## Byte-string contracts

`strspn` returns the size_t length of the initial sequence whose unsigned
bytes occur in the accept string. `strpbrk` returns the original input pointer
to its first accepted byte, or NULL. Neither includes or searches past the
first NUL in either input; the NUL is not an accepted byte. Empty strings and
empty sets work naturally. Arguments may overlap because both are read-only.
No allocation, hidden bound, widened read or write is used. Worst-case time
is the product of the two string lengths; this stage favors visible byte
bounds over an optimized lookup table.

## Separate evidence

Run `python3 tests/gcc/measured-runtime-check.py`. It builds static Forth-only
production executables and separately uses host libc/source at O0/O2 and
bidirectional caller/callee objects as independent oracles. Exhaustive byte
pairs, embedded NUL tails, duplicates, long strings, overlaps, pointer/offset
answers and guard-page boundaries are checked against Python set membership.
Own temporary permission fixtures cover all valid flag combinations, invalid
bits, symlinks, loops, missing/non-directory paths and unchanged file bytes.
Read-only guarded path tails, EFAULT and ENAMETOOLONG cover the kernel copy
boundary. Test-only syscall doubles check all 4095 errno values, full-width
arguments, signed mode promotion, PID result widths and non-caching.

Every subprocess is serial, bounded to 1 GiB and a 300-second timeout, with
an owned process group and unique scratch path. Source identities and the
unchanged 1772-byte seed are checked before and after. This focused proof is
not a new configure replay, complete cc1 link, executed GCC or bootstrap.
`setbuf` remains absent and requires a separately reviewed stream contract.

The focused owner gate passed 68,010 vectors (65,536 exhaustive byte pairs);
67,742 vectors fit both guarded pages and run at all four edge combinations.
Independent review separately exercised dual read-only string pages and
24 real fork-child PID observations across O0/O2 Forth/host providers, plus
a fresh static Forth-only executable. No runtime defect was found. All 38
previous runtime objects and a 36,872-byte ordinary runtime executable remain
byte-identical to the frozen 07ff base. Distinct real/effective credentials
were not exercised under the ordinary uid=1000 test account; the exact raw
access syscall, flag forwarding, and ordinary-user kernel behavior were.

The first owner reverse-ABI link exposed a test-only private stdout accessor
in a host-libc caller. Its corrected host-oracle branch avoids that accessor;
the Forth production branch retains its stdout error check. Both failure and
complete corrected rerun are retained. The serial test supervisor now records
each attempt before launch and records exact argv, limits, start/end times,
output paths/hashes, return code, exception, and owned-group cleanup before
raising a failure. Linux child-subreaper mode lets it reap orphan descendants
of that group. Process inspection cannot prevent signaling and bounded waits;
unverified cleanup remains a failure. A separate controlled supervisor check
retains an intentional timeout and launch exception as failed command attempts,
checks the killed/reaped descendant, and then proves recovery. These are test
supervisor checks, not additional successful runtime behavior cases. Earlier
packets preserve the original timeout-log omission as historical evidence.
