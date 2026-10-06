# Integer input measured from original Flex

Flex2.5.11 misc.c uses exactly plain %d, %o and %x through sscanf; scanopt.c
uses atoi for a decimal column count. This stage implements those conversions
with ASCII whitespace, optional signs, hexadecimal prefixes, real variadic
destination pointers and assignment counts. The format walker also handles
ordinary literals, percent literals, whitespace and repeated supported fields.
Percent conversions skip leading input whitespace through the same path as
numeric conversions; ordinary literal characters still match the next input
byte exactly. scanf-percent-check.py covers this distinction, EOF, mismatch,
and assignment counts with independent host C90 O0/O2 comparisons.
It does not advertise width, suppression, length modifiers, other conversion
letters or floating input. `%c` and `fscanf` were added later for GCC's
driver; see [DRIVER-RUNTIME.md](DRIVER-RUNTIME.md#fscanf). Original binutils
added `%u`, the `l` modifier and `%s`; see [below](#binutils-conversions).
Unsupported formats fail with EINVAL before
consuming that field's argument; prior completed assignments remain counted.

Empty input before the first assignment returns EOF; a nonmatching field
returns the number already assigned. An incomplete 0x prefix is a matching
failure and leaves its destination unchanged. The host libc accepts that
incomplete prefix as zero, so this explicit choice is checked only for the
production runtime. Valid complete fields match the independent host oracle.

Representable signed decimal and unsigned octal/hexadecimal fields have exact
32-bit results. Negative unsigned fields use unsigned modular negation. An
unrepresentable magnitude sets ERANGE and leaves that field unassigned; this is
an explicit extension where the C scanf contract otherwise leaves behavior
undefined. atoi similarly saturates to INT_MIN/MAX with ERANGE on overflow.
No-conversion atoi returns zero. Successful and ordinary nonmatching operations
preserve errno; the host resets errno on an empty scanf input, so that detail
is tested as a target contract and excluded from the shared oracle comparison.

integer-input-check.py calculates 203 scanf and 49 atoi expectations, checks
assignment/mismatch/EOF cases, eight spilled pointer arguments, unsupported
formats, overflow and a protected-page input boundary. Separate host C90 O0/O2
builds compare representable results. The production compiler, runtime and
linker remain Forth-built; host execution is only an independent oracle.

## Binutils conversions

Original binutils 2.30 `bfd/archive.c` reads every archive member size with
`sscanf(hdr.ar_size, "%lu", ...)`, and `binutils/readelf.c` reads the program
interpreter with `fscanf(file, "%4095s", ...)` (a format built from
`PATH_MAX - 1`). Without them `ar`, `nm` and `objdump` reported every archive
as malformed. The scanner now also accepts:

- `%u`: decimal like `%d`, stored as `unsigned int`; a minus sign negates
  modularly, as for `%o` and `%x`.
- `l` before `d`, `u`, `o` or `x`: the same field stored as `long` or
  `unsigned long`, with 64-bit limits; an unrepresentable magnitude sets
  ERANGE and leaves the field unassigned, as for the 32-bit forms.
- `%s` with an optional positive width: after skipping white space, at most
  that many non-white-space bytes (all of them without a width) and a NUL.
  As in C, bytes are copied without interpretation, so a stream's NUL byte
  is stored and the C string ends there.

Any other width (zero, or on another conversion), `l` with another
conversion, `h`, `%i` and suppression remain EINVAL. `integer-input-check.py`
now lists `%i`, `%hd`, `%lc`, `%2d`, `%*d` and `%0s` as unsupported.
`tests/gcc/binutils-runtime-check.py` compares the archive and readelf
patterns, `ULONG_MAX`, `LONG_MIN`, negative unsigned fields, `%3s` splitting
and a stream with an embedded NUL with host glibc
([FILE-METADATA.md](FILE-METADATA.md)).

## Consumed-byte count: %n

coreutils `stty` restores a saved `-g` setting with
`sscanf(text, "%x:%x:%x:%x%n", ..., &n)` and then checks that `n` reaches
the end of the text. `%n` (and `%ln` for a `long`) stores the number of
input bytes consumed so far by this call, reads no input, skips no white
space, and does not count as an assignment, as ISO C specifies; it works in
`sscanf` and `fscanf`, including after the last input byte.
`tests/gcc/scanf-count-check.py` compares a Forth-built fixture with its
host-glibc build: the `stty` pattern on complete, longer, short, empty and
nonmatching text, `%n` around white space, literals, `%s` and `%d`, at
empty input, and through `fscanf` with the following byte left unread.
