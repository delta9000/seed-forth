# Process CPU clock and filesystem removal

The original GCC 4.0.4 `libiberty/getruntime.c` falls back to `clock()` when
getrusage/times are unavailable. `gcc/genautomata.c` calls that timing helper
and calls `remove()` for diagnostic-file cleanup. These implementations use
only the existing raw Linux AMD64 syscall bridge and Forth-built objects.

## CPU time

The bounded `time.h` declares `clock_t` as signed LP64 long, `CLOCKS_PER_SEC`
as 1,000,000L, and `clock()`. It includes the existing sys/types.h for time_t;
the separately documented [calendar layer](CALENDAR.md) adds wall-clock and
struct tm interfaces without changing this CPU-clock contract.

`clock()` reads CLOCK_PROCESS_CPUTIME_ID through syscall 228. This counts CPU
time consumed by all threads of the process, excluding sleep and child-process
CPU time. The returned value truncates nanoseconds to microseconds. No initial
reading is subtracted; callers measure intervals by subtracting two readings.
The function checks both multiplication and addition before converting to
clock_t. An unrepresentable result returns -1 with EOVERFLOW. A syscall failure
returns -1 with its kernel errno; there is no wall-clock fallback. A malformed
successful timespec returns -1 with EIO. Success preserves errno. These errno
choices are explicit runtime extensions to the C clock result contract. The
runtime errno storage remains single-threaded; process-wide clock accounting
does not imply a new thread-safe libc claim.

Fresh original libiberty configure is mandatory before using this header with
getruntime.c. With old HAVE_TIME_H absent, that source defaults CLOCKS_PER_SEC
to one and would incorrectly scale microsecond ticks. Do not hand-set the
configure answers or reuse the old getruntime object. The unrelated libcpp calendar checks require the additional genuine
[calendar interfaces](CALENDAR.md) and fresh original probes.

## Removal

`remove(path)` calls raw unlink (87). Only EISDIR requests raw rmdir (84).
There is no prior stat, symlink-target lookup, recursive traversal or retry.
Files, FIFOs and symlinks lose the specified name; symlink targets survive.
An empty directory can be removed; a nonempty directory reports the kernel
error. Open file descriptions and remaining hard links continue to refer to
the file after its name is removed. Success returns zero and preserves errno;
failure returns -1 with the final syscall errno. Path changes between the two
syscalls remain possible, as with other pathname-based filesystem interfaces.

The added errno constants are Linux E2BIG=7, ENOTDIR=20, EISDIR=21 and
ENOTEMPTY=39. E2BIG/ENOTDIR also satisfy measured original libcpp declarations;
adding their names does not simulate successful operations.

## Validation and references

Run `python3 tests/gcc/clock-remove-check.py`. Forth production verifies real
CPU-time brackets, busy work and sleep exclusion, disposable filesystem cases,
and injected syscall results covering all 4,095 Linux error encodings. Exact
checks cover submicrosecond truncation, the final representable tick, overflow,
malformed timespecs, directory fallback and errno preservation. Independent GCC
O0/O2 oracles repeat these checks. Host remove success errno is not compared:
the stronger preservation behavior belongs to this runtime's stated contract.

ABI facts were checked against installed Linux UAPI headers and Linux man-pages:
[clock](https://man7.org/linux/man-pages/man3/clock.3.html),
[clock_gettime](https://man7.org/linux/man-pages/man2/clock_gettime.2.html),
[remove](https://man7.org/linux/man-pages/man3/remove.3.html), and
[unlink](https://man7.org/linux/man-pages/man2/unlink.2.html).
No libc implementation was copied.
