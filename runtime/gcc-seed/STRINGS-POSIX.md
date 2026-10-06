# Strings, integers, random numbers and line input

The remaining C89/POSIX string and number functions the plumbing tools call,
all in the fixed ASCII C locale. Each function that a program commonly
supplies itself (gnulib and libiberty replacements) is a separate archive
member, so the runtime's copy is linked only when the program has none.

## strings.h and memory.h

`strings.h` declares `strcasecmp` and `strncasecmp` (ASCII `A`–`Z` fold to
lower case; other bytes, including those above 127, compare as unsigned
char, so results match glibc's C locale), `index`/`rindex` (`strchr`/
`strrchr`), `bzero`, `bcopy` (overlap-safe, source first), `bcmp` (0 or
nonzero) and `ffs` (1-based lowest set bit, 0 for 0). `memory.h` includes
`string.h`.

## string.h additions

`strnlen`, `strndup`, `stpcpy`, `stpncpy` (pads with NULs and returns a
pointer to the first NUL written, or `dest + n`), `strtok` and `strtok_r`
(skip leading separators, NUL-terminate each token, NULL when exhausted),
`strcoll` (byte order: `strcmp`) and `strxfrm` (the identity transform: it
copies only when the whole string and its NUL fit, and returns the length).
`strsignal` is described in [SIGNALS.md](SIGNALS.md).

## stdlib.h and inttypes.h additions

On this LP64 target `long long`, `intmax_t` and `long` share one 64-bit
range, so `strtoll`, `strtoimax` and `atoll` are exactly `strtol`, and
`strtoull` and `strtoumax` exactly `strtoul` ([STRTOUL.md](STRTOUL.md)),
including end pointers, `ERANGE` saturation and `EINVAL` for a bad base.
`labs` and `llabs` (the most negative value has no result, as for `abs`),
`div`, `ldiv` and `lldiv` (quotient truncated toward zero) and the `div_t`,
`ldiv_t`, `lldiv_t` records are added.

`rand`, `srand`, `random` and `srandom` share glibc's degree-31 additive
lagged-Fibonacci generator: the 31-word state is seeded by the Lehmer
sequence `16807 * x mod (2^31 - 1)` (Schrage's method), the first 310 outputs
are discarded, and each result is `(r[i-3] + r[i-31]) >> 1` modulo 2^32. A
seed of 0 acts as 1. Every seed therefore gives glibc's sequence, which keeps
programs that print random numbers comparable with a host oracle.
`RAND_MAX` is 2147483647. There is no `initstate`/`setstate`.

`mblen` and `wcstombs` are in [WIDE.md](WIDE.md); `setenv`, `unsetenv` and
`localeconv` in [ENVIRONMENT.md](ENVIRONMENT.md); `realpath` in
[FILE-CALLS.md](FILE-CALLS.md).

## ctype.h

`isblank` is true only for space and tab (and false for `EOF`).

## getline and getdelim

`getdelim(&line, &capacity, delimiter, stream)` reads bytes with `fgetc`
through the first `delimiter` (kept) or end of file, growing `*line` with
`realloc` (120 bytes first, then doubling) and updating `*capacity`, and
NUL-terminates it. It returns the byte count, or -1 when nothing was read
(end of file or a read error) and fails `EINVAL` for NULL arguments.
`getline` uses `'\n'`. Embedded NUL bytes are counted.

They are declared in `stdio.h` only when the program asks for POSIX 2008 or
GNU interfaces (`_GNU_SOURCE`, `_POSIX_C_SOURCE >= 200809L` or
`_XOPEN_SOURCE >= 700`). Many older GNU programs define a function named
`getline` with different types (coreutils 5.0's `getline.h` declares
`int getline (...)` whenever the C library is not glibc); an unconditional
declaration would make them fail to compile.

## alloca

The Forth C compiler has no stack-allocating builtin, so the runtime defines
no `alloca`. `alloca.h` only declares `void *alloca(size_t)`, which gives
callers the right pointer type (an undeclared call would be truncated to
`int` on LP64). A program that uses `alloca` must link a portable C
implementation: gnulib's or libiberty's `alloca.c` built with `C_ALLOCA`
(make, tar and diffutils already do). A configure script's link test for a
working builtin `alloca` fails, which selects that path.

## Gate

`python3 tests/gcc/posix-strings-check.py` builds one fixture with the
Forth compiler and with host GCC/glibc (`-O0`, `-O2`) and requires identical
output: case-insensitive comparisons of ten words (including bytes above
127) at three lengths and `strcoll`, the BSD functions and `ffs` edges,
`strn*`, `stp*`, `strtok`/`strtok_r`, `strxfrm`, 19 numeric strings in four
bases through every integer conversion, `div` family signs, eight values
for five seeds of `rand` and four of `random` plus the 100001st, `isblank`
over -1..255, `setenv`/`unsetenv` (keep, replace, empty values, invalid
names) and the environment a `system` child sees, `localeconv`, the
restartable multibyte calls, and `getline`/`getdelim` over a long line, an
empty line, a missing final newline and an empty file.
