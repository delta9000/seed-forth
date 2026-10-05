# Bounded wall-clock and UTC calendar runtime

Original GCC 4.0.4 `libcpp/macro.c` needs `time(NULL)`, `localtime(&tt)` and
six standard `struct tm` fields for its cached `__DATE__` and `__TIME__` text.
This original MIT implementation adds those real operations without changing
`clock()` or its process-CPU accounting contract.

Original binutils 2.30 adds `gmtime`, `ctime` and a bounded `strftime` over
the same conversion; see [FILE-METADATA.md](FILE-METADATA.md).

## Explicit timezone and representation boundary

Run configure, build and programs with `TZ=UTC0`. `localtime` accepts exactly
that spelling, meaning fixed zero offset and no daylight-saving transitions.
An absent/empty TZ, aliases such as UTC/GMT, an Olson zone, an offset, or any
other string returns NULL and EINVAL. The runtime does not inspect host
`/etc/localtime`, timezone databases, or locale settings, and never silently
substitutes UTC. It rereads the real process environment on every call.

`time_t` remains signed 64-bit long, seconds since 1970-01-01 00:00:00 UTC.
`time()` uses real Linux AMD64 `clock_gettime` syscall 228 with CLOCK_REALTIME=0.
Status is separate from seconds, so timestamp -1 is a successful value when
errno was zero. Success preserves errno, writes the optional result pointer,
and truncates the nanosecond part. A syscall error returns -1 and its errno;
an unexpected status or invalid nanosecond field returns -1 and EIO. The returned
value is stored through a nonnull output pointer on both success and failure. Negative seconds, including LONG_MIN,
are representable by `time_t`; this does not promise the kernel can produce
every such value. Supplied nonnull pointers must refer to valid objects.

`localtime()` converts into a single static record overwritten by the next
successful call. NULL input is EINVAL. Success preserves errno; failure leaves
the prior static record unchanged. All nine standard fields are supplied:
seconds/minutes/hours, month day, zero-based month, year minus 1900, Sunday-based
weekday, zero-based year day, and tm_isdst=0. The record is nine consecutive
32-bit ints (36 bytes, alignment 4). Host-libc extension fields such as
`tm_gmtoff` and `tm_zone` are absent; whole host-libc records are not ABI aliases.
The runtime and errno remain single-threaded, with no reentrancy promise.

The calendar is proleptic Gregorian with astronomical year numbering (year 0
exists). Every divisible-by-4 year is leap except centuries not divisible by
400. Seconds have the POSIX 86400-per-day interpretation; leap seconds are not
represented. Division normalizes negative epoch remainders without overflowing
on LONG_MIN. A 400-year/146097-day decomposition leaves at most 399 single-year
steps and eleven month steps. Intermediate arithmetic fits signed long for all
time_t inputs. A year offset outside INT_MIN..INT_MAX fails with EOVERFLOW
before narrowing. Thus 2038 is not a boundary, but `struct tm.tm_year` has its
own explicit finite range. Original libcpp's fixed date buffer and `tm_year +
1900` arithmetic do not support arbitrary extreme years; fixture formatting
checks use the original consumer's ordinary four-digit-year domain.

## Honest header probes

`time.h` supplies the above implemented functions and standard record, while
preserving `clock_t`, CLOCKS_PER_SEC and `clock()` unchanged. `sys/time.h`
supplies the genuine LP64 `struct timeval` record (two signed long fields),
`suseconds_t` and the existing `time_t`, with independent include guards. It
declares no select, interval timer, or timezone record APIs; the later
`gettimeofday` declaration is documented in [PROCFS.md](PROCFS.md).
The headers can be included in either order. Their presence is a bounded
record/inclusion contract, not a complete POSIX header claim.

Rerun original libcpp configure. Its actual AC_HEADER_TIME compile should now
set TIME_WITH_SYS_TIME, allowing original system.h to include both headers;
its actual AC_STRUCT_TM probe should find the record in time.h. Never force
these answers or reuse an old configuration. Full component/source builds
remain separate from this focused runtime proof.

## Verification

Run `TZ=UTC0 python3 tests/gcc/calendar-check.py --gcc-source PATH` with the
unchanged pinned GCC 944765863eec87a9f37e297994fd2af960397138 tree. The serial
harness caps each subprocess at 1 GiB address space. It retains commands,
source identities, Forth objects/executables and separately labelled host
GCC O0/O2 oracles. Coverage includes independent host calendar comparisons,
ABI offsets, exact supported-year boundaries, real clock observation windows,
errno/syscall faults, explicit timezone failures, header include probes and
an extracted unmodified original macro formatting/caching block. Host libc
success errno is not an oracle: the runtime's stronger preservation contract
is asserted separately. It does not
claim a completed libcpp build or full GCC bootstrap.

No libc implementation was copied. Gregorian cycles follow elementary calendar
arithmetic; syscall ABI and public field names can be checked in installed
Linux AMD64 UAPI headers and system manual pages.

The output-pointer rule on every `time()` return path follows
[WG14 N1548, section 7.26.2.4](https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1548.pdf).
