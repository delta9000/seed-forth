# Wall clock, time zones and calendar runtime

Original GCC 4.0.4 `libcpp/macro.c` needs `time(NULL)`, `localtime(&tt)` and
six standard `struct tm` fields for its cached `__DATE__` and `__TIME__` text.
Original binutils 2.30 adds `gmtime`, `ctime` and `strftime`
([FILE-METADATA.md](FILE-METADATA.md)), and later tools (`tar -tv`, `gzip -l`,
`ls -l`, `date`) expect a working `localtime` in any zone. This original MIT
implementation supplies the C and POSIX calendar interfaces with glibc's
observable behaviour, without changing `clock()` or its process-CPU contract
([CLOCK-REMOVE.md](CLOCK-REMOVE.md)).

`calendar.c` holds `time`, the conversions, the TZ parser, `tzset`,
`localtime`/`localtime_r`, `gmtime`/`gmtime_r`, `mktime`, `timegm`,
`asctime`/`asctime_r`, `ctime`/`ctime_r`, `difftime` and the globals
`tzname`, `timezone` and `daylight`. `strftime.c` holds `strftime`. Both
are members of the default libc archive.

## Wall clock and representation

`time_t` remains signed 64-bit long, seconds since 1970-01-01 00:00:00 UTC.
`time()` uses real Linux AMD64 `clock_gettime` syscall 228 with CLOCK_REALTIME=0.
Status is separate from seconds, so timestamp -1 is a successful value when
errno was zero. Success preserves errno, writes the optional result pointer,
and truncates the nanosecond part. A syscall error returns -1 and its errno;
an unexpected status or invalid nanosecond field returns -1 and EIO. The
returned value is stored through a nonnull output pointer on both success and
failure. Supplied nonnull pointers must refer to valid objects.

`struct tm` is the standard nine consecutive 32-bit ints (36 bytes,
alignment 4). glibc's `tm_gmtoff` and `tm_zone` extension fields are absent,
so whole glibc records are not ABI aliases; see the `%z`/`%Z` rule below.

The calendar is proleptic Gregorian with astronomical year numbering (year 0
exists). Seconds have the POSIX 86400-per-day interpretation; leap seconds are
not represented. Conversion splits a timestamp into days and seconds first, so
no intermediate overflows for any `time_t`, then uses one 400-year
(146097-day) cycle division and at most three single-year steps. A year whose
`tm_year` would not fit an int fails with EOVERFLOW, so 2038 is not a boundary.

## Time zones

The zone comes only from the `TZ` environment variable:

- Unset or empty: UTC, with `tzname` both "UTC". glibc reads
  `/etc/localtime` when TZ is unset; this runtime deliberately never does,
  so builds do not depend on the host's zone. Set TZ explicitly for local
  time.
- A POSIX string `std offset [dst [offset] [,start[/time],end[/time]]]`.
  Names are three or more letters, or `<...>` holding three or more
  letters, digits, `+` or `-` (`<+0530>-5:30`, `<-03>3`). Offsets are
  `[+-]hh[:mm[:ss]]` west of UTC; hours are capped at 24 and minutes and
  seconds at 59, as glibc does. A missing DST offset is one hour ahead of
  standard time. Rules are `Jn` (1..365, February 29 never counted), `n`
  (0..365, counted) or `Mm.w.d` (week 5 = last), each with an optional
  `/time` that may be negative or beyond 24 hours (`/-2`, `/26`, `/167`;
  default 02:00). A DST name with no rule, or with `,` alone, uses the US
  rules `M3.2.0,M11.1.0`; a single rule takes `M11.1.0` as its end. Numbers
  are read as glibc's `sscanf("%hu")` reads them (leading blanks and a sign
  accepted, 16-bit wrap).
- `UTC0`, `GMT0` and other zero-offset strings are UTC under their own name.
  The bare names `UTC` and `GMT` are UTC with that name, as glibc's zoneinfo
  files give.
- A value starting with `:`, a zoneinfo name (`Europe/London`), a name with
  no offset (`EST`), or any other string whose standard part does not parse
  means UTC with `tzname` "UTC". glibc would open the zoneinfo file (and
  without one, strips `:` and keeps the leading name with offset 0); no
  timezone database is read here. Likewise glibc resolves `EST5EDT` and a
  DST name without rules through zoneinfo files (`EST5EDT`, `posixrules`)
  when they exist, which can apply historical rules; this runtime always
  uses the POSIX meaning.

Daylight time applies when the instant lies between the two transitions of
its UTC year; when the end comes before the start in the year (southern
hemisphere), it applies outside them. A transition is the rule's local
date and time interpreted with the offset in force before it (standard time
for the start, daylight time for the end). For years up to 1970 the
transition arithmetic starts from 1970-01-01, exactly as glibc's does, so
earlier instants are standard time under northern rules and daylight time
under southern ones.

A malformed daylight part (name, start or end rule) leaves standard time
only, with `daylight` 0; glibc keeps partially initialised rules. Zone names
longer than 63 bytes make the string unparsable. The zone text is cached;
`localtime`, `localtime_r`, `mktime`, `strftime` and `tzset` reread
`getenv("TZ")` and reparse only when it changed (glibc's `localtime_r`
reads TZ once). `tzset` sets `tzname[0]` and `tzname[1]` (the standard name
twice when there is no daylight part), `timezone` (seconds west for standard
time) and `daylight` (1 when the two offsets differ). The `tzname` strings
are overwritten when TZ changes. Before the first call `tzname` is "UTC".

## Conversions

`localtime` and `gmtime` share one static record, overwritten by the next
successful call; `_r` forms write the caller's. `localtime` sets `tm_isdst`
to 0 or 1, `gmtime` to 0. NULL arguments fail with EINVAL (glibc faults). A
year outside int fails with EOVERFLOW and leaves the static record unchanged.
Success preserves errno.

`mktime` inverts `localtime` by probing, as glibc does. Out-of-range months
carry into years and the other fields are folded in arithmetically, for any
int values; seconds outside 0..59 are clamped for the search and added back
afterwards. Up to six conversions converge on the instant. It then sets every
field, including `tm_wday`, `tm_yday` and `tm_isdst`, and returns the
instant. With `tm_isdst` < 0 the matching offset wins; in a spring-forward
gap the result is the daylight-side instant as far past the transition as
the request lies past it. A `tm_isdst` of 0 or > 0 that disagrees with the
rules borrows the offset of the nearest instant having the requested flag
(searched in 601200-second steps, earlier first, up to 229222800 seconds
away), else shifts by one hour. Like glibc, the first guess uses the offset
found by the previous call, so a result in a gap can depend on it. An
unrepresentable result returns -1 with EOVERFLOW and leaves the record
unchanged. `timegm` sets `tm_isdst` to 0 and inverts `gmtime` the same way,
with its own previous-offset state.

`asctime` and `ctime` produce `"Thu Jan  1 00:00:00 1970\n"`
(`"%.3s %.3s%3d %.2d:%.2d:%.2d %d\n"`, "???" for an unknown weekday or month)
in one static buffer; `asctime_r` and `ctime_r` write a 26-byte caller
buffer and fail with EOVERFLOW when the text does not fit (years beyond 9999,
for example). A year that overflows int is EOVERFLOW; `ctime` returns NULL
with `localtime`'s errno. `difftime` returns the exact difference rounded once
to double.

## strftime

Conversions follow glibc's C locale exactly: `%a %A %b %B %c %C %d %D %e %F
%g %G %h %H %I %j %k %l %m %M %n %p %P %r %R %s %S %t %T %u %U %V %w %W %x %X
%y %Y %z %Z %%`. `%c` is `%a %b %e %H:%M:%S %Y`, `%x` and `%D` are `%m/%d/%y`,
`%X` and `%T` are `%H:%M:%S`, `%r` is `%I:%M:%S %p`. The GNU flags `_` (space
pad), `-` (no pad), `0` (zero pad), `^` (upper case) and `#` (swap case) and
decimal field widths apply as in glibc, including widths on text, on
composites (`%12F`) and on `%z`'s sign. `E` and `O` are accepted where glibc
accepts them and change nothing in the C locale; an invalid combination,
an unknown conversion or a trailing `%` is copied through verbatim (with the
width). glibc 2.43 has no `+` flag, `%:z` or `%+`, and neither does this.

Fields are used as given, never normalized: out-of-range names print "?",
numbers print their int-wrapped values, and week numbers use `tm_yday` and
`tm_wday` as the caller set them. `%s` is `mktime` of a copy. Because the
record has no `tm_gmtoff`/`tm_zone`, `%z` is the current TZ's standard or
daylight offset chosen by `tm_isdst` (nothing when it is negative), and `%Z`
is `tzname[tm_isdst]` ("" when negative, "?" above 1). glibc gives the same
for a record without those fields, but for a record from its own `gmtime`
it prints "GMT" and "+0000"; here such a record prints the local standard
zone.

The result is the length when it and its terminator fit in the size;
otherwise 0, with the buffer's first byte set to zero. A zero size returns 0.

## Header probes

`time.h` declares the above and keeps `clock_t`, CLOCKS_PER_SEC and `clock()`.
`sys/time.h` supplies the genuine LP64 `struct timeval` (two signed long
fields), `suseconds_t` and `time_t`, with independent include guards. It
declares no select, interval timer, or timezone record APIs; the later
`gettimeofday` declaration is documented in [PROCFS.md](PROCFS.md). The headers
can be included in either order.

Rerun original libcpp configure. Its actual AC_HEADER_TIME compile sets
TIME_WITH_SYS_TIME, allowing original system.h to include both headers; its
actual AC_STRUCT_TM probe finds the record in time.h. Never force these
answers or reuse an old configuration.

## Verification

`python3 tests/gcc/calendar-tz-check.py` is the differential gate. The
fixture `tests/gcc/calendar-tz-check.c` is built by the Forth compiler and,
as an oracle only, by host GCC against glibc. Both run under 53 TZ values
(the forms above, US, European, southern, half-hour and odd-second zones,
`J` and `n` rules, negative and >24 h transition times, extreme offsets,
the UTC fallbacks) and must print identical bytes: tzname, timezone and
daylight; local, UTC, `ctime`, `ctime_r` and `asctime_r` results for
extreme, random (±2^40 s and 1900..2039), year-boundary and leap-day
instants; a hash of every six-hour sample of 165 years; each DST transition
to the second, with `mktime` at fifteen minute offsets around it under every
`tm_isdst`; `mktime` round trips; and `mktime`/`timegm` on 3000 random
out-of-range records and on int-limit fields. A second mode runs `strftime`
over every printable conversion character with nine flag sets, four widths
and both modifiers, composites, sizes 0 to 29, ISO and Sunday/Monday week
numbers around each new year of one 400-year cycle plus years -420..20,
out-of-range and int-limit records, `asctime_r` limits and `difftime` bits.
About two million lines are compared. The oracle runs with TZDIR set to an
empty directory, so that glibc parses each string as POSIX rather than
opening a zoneinfo or `posixrules` file; for the UTC fallbacks it gets the
TZ string that means UTC to glibc. The expected glibc is 2.43; other versions
may choose differently inside `mktime` gaps.

`TZ=UTC0 python3 tests/gcc/calendar-check.py --gcc-source PATH` keeps the
earlier serial checks with the unchanged pinned GCC
944765863eec87a9f37e297994fd2af960397138 tree: an independent Python
calendar over the full int-year range, ABI offsets, real clock observation
windows, errno and syscall faults, the UTC fallback and POSIX zone spot
checks, header include probes and an extracted unmodified original macro
formatting and caching block. It does not claim a completed libcpp build or
full GCC bootstrap.

No libc source was copied. Gregorian cycles follow elementary calendar
arithmetic, the rule weekday uses Zeller's congruence, and the TZ grammar is
POSIX's. Where glibc makes its own choices (the 1970 transition base,
`mktime`'s probing, flag and width rules) the behaviour was reimplemented
and confirmed by the differential test. Syscall ABI and public field names
can be checked in installed Linux AMD64 UAPI headers and manual pages. The
output-pointer rule on every `time()` return path follows
[WG14 N1548, section 7.26.2.4](https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1548.pdf).
